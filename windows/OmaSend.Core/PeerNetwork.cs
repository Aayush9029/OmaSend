using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;

namespace OmaSend.Core;

public sealed record Peer(string Id, string Name, string Host, int Port, string Via, DateTimeOffset LastSeen);

public sealed partial class PeerNetwork : IDisposable
{
    private readonly bool trustedLAN;
    private readonly string secret, deviceId, deviceName, downloads;
    private readonly CancellationTokenSource lifetime = new();
    private readonly ConcurrentDictionary<string, Peer> peers = new();
    private readonly ConcurrentDictionary<string, byte> probing = new();
    private readonly SemaphoreSlim connections = new(16);
    private readonly TcpListener listener;
    public int Port { get; }
    public event Action<Message>? Received;
    public event Action? PeersChanged;
    public event Action<string>? Error;
    public Action<string>? ProtectReceivedFile { get; init; }
    public Peer[] Peers => peers.Values.Where(p => DateTimeOffset.UtcNow - p.LastSeen < TimeSpan.FromSeconds(25)).OrderBy(p => p.Name).ToArray();
    public PeerNetwork(string id, string name, string pairingCode, string downloadsDirectory, int port = Wire.DefaultPort, IPAddress? bindAddress = null, bool trustedLAN = false)
    {
        this.trustedLAN = trustedLAN;
        deviceId = id; deviceName = name; secret = pairingCode; downloads = downloadsDirectory;
        listener = new TcpListener(bindAddress ?? IPAddress.IPv6Any, port);
        if (bindAddress is null) listener.Server.DualMode = true;
        listener.Start();
        Port = ((IPEndPoint)listener.LocalEndpoint).Port;
        _ = AcceptLoop();
        _ = Maintain();
    }
    public Message NewMessage(string type) => new() { Type = type, OriginId = deviceId, OriginName = deviceName, Port = Port };
    private void Upsert(Message message, string host, int port, string via)
    {
        if (lifetime.IsCancellationRequested || message.OriginId == deviceId) return;
        if (peers.Count >= 128 && !peers.ContainsKey(message.OriginId)) return;
        peers[message.OriginId] = new(message.OriginId, message.OriginName, host, port, via, DateTimeOffset.UtcNow);
        PeersChanged?.Invoke();
    }
    private async Task Maintain()
    {
        try
        {
            using var timer = new PeriodicTimer(TimeSpan.FromSeconds(5));
            while (await timer.WaitForNextTickAsync(lifetime.Token))
            {
                foreach (var p in peers.Values)
                {
                    if (DateTimeOffset.UtcNow - p.LastSeen > TimeSpan.FromMinutes(3)) peers.TryRemove(p.Id, out _);
                    else _ = Probe(p.Host, p.Port, p.Via);
                }
                PeersChanged?.Invoke();
            }
        }
        catch (OperationCanceledException) { }
    }
    public async Task Probe(string host, int port = Wire.DefaultPort, string via = "Local network")
    {
        string endpoint = host + ":" + port;
        if (probing.Count >= 32 || !probing.TryAdd(endpoint, 0)) return;
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
            timeout.CancelAfter(TimeSpan.FromSeconds(4));
            using var client = new TcpClient();
            await client.ConnectAsync(host, port, timeout.Token);
            CheckAddress(client);
            var stream = client.GetStream();
            await Wire.WriteFrame(stream, Seal(NewMessage("hello")), timeout.Token);
            var reply = Open(await Wire.ReadFrame(stream, timeout.Token));
            if (reply.Type == "hello_ack") Upsert(reply, host, port, via);
        }
        catch (Exception ex) when (Expected(ex)) { }
        finally { probing.TryRemove(endpoint, out _); }
    }
    private async Task AcceptLoop()
    {
        try
        {
            while (!lifetime.IsCancellationRequested)
            {
                var client = await listener.AcceptTcpClientAsync(lifetime.Token);
                if (!connections.Wait(0)) { client.Dispose(); continue; }
                _ = Handle(client);
            }
        }
        catch (Exception ex) when (Expected(ex)) { }
    }
    private async Task Handle(TcpClient client)
    {
        using (client)
        using (var timeout = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token))
        {
            try
            {
                timeout.CancelAfter(TimeSpan.FromSeconds(5));
                CheckAddress(client);
                var stream = client.GetStream();
                var message = Open(await Wire.ReadFrame(stream, timeout.Token));
                if (message.OriginId == deviceId) return;
                var address = ((IPEndPoint)client.Client.RemoteEndPoint!).Address;
                if (address.IsIPv4MappedToIPv6) address = address.MapToIPv4();
                Upsert(message, address.ToString(), message.Port is > 0 and <= 65535 ? message.Port.Value : Wire.DefaultPort,
                    address.ToString().StartsWith("100.", StringComparison.Ordinal) ? "Tailscale" : "Local network");
                switch (message.Type)
                {
                    case "hello":
                        await Wire.WriteFrame(stream, Seal(NewMessage("hello_ack")), timeout.Token);
                        break;
                    case "clipboard":
                    case "history_clear":
                        if (!lifetime.IsCancellationRequested) Received?.Invoke(message);
                        break;
                    case "file_offer":
                        timeout.CancelAfter(TimeSpan.FromMinutes(30));
                        await ReceiveFile(stream, message, timeout.Token);
                        break;
                }
            }
            catch (Exception ex) when (Expected(ex)) { }
            finally { connections.Release(); }
        }
    }
    public async Task Broadcast(Message message)
    {
        await Task.WhenAll(Peers.Select(async peer =>
        {
            try
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
                timeout.CancelAfter(TimeSpan.FromSeconds(10));
                using var client = new TcpClient();
                await client.ConnectAsync(peer.Host, peer.Port, timeout.Token);
        CheckAddress(client);
                await Wire.WriteFrame(client.GetStream(), Seal(message), timeout.Token);
            }
            catch (Exception ex) when (Expected(ex)) { if (!lifetime.IsCancellationRequested) Error?.Invoke($"Could not send to {peer.Name}. Check the connection."); }
        }));
    }
    private byte[] Seal(Message message) => Wire.Seal(secret, message, trustedLAN);
    private Message Open(byte[] frame) => Wire.Open(secret, frame, trustedLAN);
    private void CheckAddress(TcpClient client)
    {
        if (trustedLAN && !IsLAN(((IPEndPoint)client.Client.RemoteEndPoint!).Address)) throw new InvalidDataException("Trusted LAN requires a local network address.");
    }
    public static bool IsLAN(IPAddress address)
    {
        if (address.IsIPv4MappedToIPv6) address = address.MapToIPv4();
        if (IPAddress.IsLoopback(address) || address.IsIPv6LinkLocal || address.IsIPv6UniqueLocal) return true;
        var b = address.GetAddressBytes();
        return b.Length == 4 && (b[0] == 10 || b[0] == 172 && b[1] >= 16 && b[1] <= 31 || b[0] == 192 && b[1] == 168 || b[0] == 169 && b[1] == 254);
    }
    private static bool Expected(Exception ex) => ex is IOException or InvalidDataException or SocketException or OperationCanceledException or
        System.Security.Cryptography.CryptographicException or System.Text.Json.JsonException or ArgumentException or FormatException or UnauthorizedAccessException or ObjectDisposedException;
    public void Dispose() { lifetime.Cancel(); listener.Stop(); }
}
