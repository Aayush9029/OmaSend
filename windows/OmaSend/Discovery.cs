using System.Diagnostics;
using System.Net;
using System.Text.Json;
using Makaretu.Dns;

namespace OmaSend;

public sealed class Discovery : IDisposable
{
    public sealed record Candidate(string Id, string Name, DateTimeOffset Seen);
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, Candidate> candidates = new();
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, byte> resolving = new();
    public Candidate[] Candidates => candidates.Values.Where(c => DateTimeOffset.UtcNow - c.Seen < TimeSpan.FromMinutes(2)).ToArray();
    public event Action? CandidatesChanged;
    private readonly MulticastService mdns = new();
    private readonly ServiceDiscovery services;
    private readonly ServiceProfile profile;
    private readonly PeerNetwork network;
    private readonly string[] hosts;
    private readonly bool trustedLAN;
    private readonly CancellationTokenSource lifetime = new();
    public Discovery(PeerNetwork network, Settings settings)
    {
        this.network = network; hosts = settings.Hosts; trustedLAN = settings.TrustedLAN;
        services = new ServiceDiscovery(mdns);
        profile = new ServiceProfile("OmaSend-" + settings.DeviceId, "_omasend._tcp", (ushort)network.Port);
        profile.AddProperty("v", "1"); profile.AddProperty("id", settings.DeviceId); profile.AddProperty("name", settings.DeviceName); profile.AddProperty("platform", "windows");
        services.ServiceInstanceDiscovered += (_, e) =>
        {
            if (!e.ServiceInstanceName.ToString().TrimEnd('.').EndsWith("._omasend._tcp.local", StringComparison.OrdinalIgnoreCase)) return;
            _ = Resolve(e, settings.DeviceId);
        };
        services.Advertise(profile);
        mdns.Start();
        services.Announce(profile);
        _ = Maintain();
    }
    private async Task Resolve(ServiceInstanceDiscoveryEventArgs e, string ownId)
    {
        string key = e.ServiceInstanceName.ToString();
        if (resolving.Count >= 16 || !resolving.TryAdd(key, 0)) return;
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
            timeout.CancelAfter(TimeSpan.FromSeconds(3));
            var records = e.Message.Answers.Concat(e.Message.AdditionalRecords).ToList();
            if (!records.OfType<SRVRecord>().Any(r => r.Name == e.ServiceInstanceName) || !records.OfType<TXTRecord>().Any(r => r.Name == e.ServiceInstanceName))
            {
                records = await ResolveRecords(e.ServiceInstanceName, records,
                    r => r.OfType<SRVRecord>().Any(s => s.Name == e.ServiceInstanceName) &&
                         r.OfType<TXTRecord>().Any(t => t.Name == e.ServiceInstanceName), timeout.Token);
            }
            var txt = records.OfType<TXTRecord>().Where(r => r.Name == e.ServiceInstanceName).SelectMany(r => r.Strings).ToArray();
            string id = txt.FirstOrDefault(s => s.StartsWith("id=", StringComparison.Ordinal))?[3..] ?? key;
            if (id == ownId) return;
            string name = txt.FirstOrDefault(s => s.StartsWith("name=", StringComparison.Ordinal))?[5..] ?? key.Split('.')[0];
            if (candidates.Count < 128 || candidates.ContainsKey(id)) candidates[id] = new(id, name[..Math.Min(name.Length, 100)], DateTimeOffset.UtcNow);
            CandidatesChanged?.Invoke();
            foreach (var srv in records.OfType<SRVRecord>().Where(r => r.Name == e.ServiceInstanceName))
            {
                var addresses = records.OfType<AddressRecord>().Where(r => r.Name == srv.Target).Select(r => r.Address).ToList();
                if (!addresses.Any(UsableAddress))
                {
                    var resolved = await ResolveRecords(srv.Target, records,
                        r => r.OfType<AddressRecord>().Any(a => a.Name == srv.Target && UsableAddress(a.Address)), timeout.Token);
                    addresses.AddRange(resolved.OfType<AddressRecord>().Where(r => r.Name == srv.Target).Select(r => r.Address));
                }
                foreach (var ip in addresses.Where(UsableAddress).Distinct()) _ = network.Probe(ip.ToString(), srv.Port);
            }
        }
        catch (Exception ex) when (ex is OperationCanceledException or IOException or System.Net.Sockets.SocketException or ObjectDisposedException or ArgumentException) { }
        finally { resolving.TryRemove(key, out _); }
    }
    private static bool UsableAddress(IPAddress ip) => !ip.Equals(IPAddress.Any) && !ip.Equals(IPAddress.IPv6Any) && !ip.IsIPv6LinkLocal;

    // ResolveAsync in Makaretu completes on the first matching name, even when
    // that packet contains only TXT or only SRV. Bonjour may split these records.
    private async Task<List<ResourceRecord>> ResolveRecords(DomainName name, List<ResourceRecord> seed,
        Func<List<ResourceRecord>, bool> complete, CancellationToken token)
    {
        var records = new List<ResourceRecord>(seed);
        var ready = new TaskCompletionSource<List<ResourceRecord>>(TaskCreationOptions.RunContinuationsAsynchronously);
        void OnAnswer(object? sender, MessageEventArgs args)
        {
            lock (records)
            {
                records.AddRange(args.Message.Answers.Concat(args.Message.AdditionalRecords)
                    .Where(r => r.Name == name).Take(Math.Max(0, 256 - records.Count)));
                if (complete(records)) ready.TrySetResult(new List<ResourceRecord>(records));
            }
        }
        mdns.AnswerReceived += OnAnswer;
        try
        {
            using var cancellation = token.Register(() => ready.TrySetCanceled(token));
            while (!ready.Task.IsCompleted)
            {
                mdns.SendQuery(name);
                await Task.WhenAny(ready.Task, Task.Delay(500, token));
            }
            return await ready.Task;
        }
        finally { mdns.AnswerReceived -= OnAnswer; }
    }
    private async Task Maintain()
    {
        try
        {
            using var timer = new PeriodicTimer(TimeSpan.FromSeconds(8));
            do
            {
                services.QueryServiceInstances("_omasend._tcp");
                services.Announce(profile);
                foreach (string host in hosts) _ = network.Probe(host.Trim());
                if (!trustedLAN) await ProbeTailscale();
            } while (await timer.WaitForNextTickAsync(lifetime.Token));
        }
        catch (OperationCanceledException) { }
        catch (ObjectDisposedException) { }
    }
    private async Task ProbeTailscale()
    {
        string executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Tailscale", "tailscale.exe");
        if (!File.Exists(executable)) return;
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
            timeout.CancelAfter(TimeSpan.FromSeconds(4));
            using var process = Process.Start(new ProcessStartInfo(executable, "status --json")
            { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true });
            if (process is null) return;
            using var stop = timeout.Token.Register(() => { try { if (!process.HasExited) process.Kill(); } catch (InvalidOperationException) { } });
            var stderr = process.StandardError.ReadToEndAsync(timeout.Token);
            string json = await process.StandardOutput.ReadToEndAsync(timeout.Token);
            await process.WaitForExitAsync(timeout.Token); await stderr;
            if (process.ExitCode != 0) return;
            using var doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("Peer", out var peers)) return;
            foreach (var property in peers.EnumerateObject())
            {
                var peer = property.Value;
                if (!peer.TryGetProperty("Online", out var online) || !online.GetBoolean() || !peer.TryGetProperty("TailscaleIPs", out var ips)) continue;
                foreach (var value in ips.EnumerateArray())
                    if (IPAddress.TryParse(value.GetString(), out var ip) && ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                    { _ = network.Probe(ip.ToString(), Wire.DefaultPort, "Tailscale"); break; }
            }
        }
        catch (Exception ex) when (ex is OperationCanceledException or IOException or JsonException or System.ComponentModel.Win32Exception or InvalidOperationException) { }
    }
    public void Dispose()
    {
        lifetime.Cancel();
        services.Unadvertise(profile); services.Dispose(); mdns.Dispose();
    }
}
