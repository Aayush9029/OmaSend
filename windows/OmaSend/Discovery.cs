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
    private readonly CancellationTokenSource lifetime = new();
    public Discovery(PeerNetwork network, Settings settings)
    {
        this.network = network; hosts = settings.Hosts;
        services = new ServiceDiscovery(mdns);
        profile = new ServiceProfile("OmaSend-" + settings.DeviceId, "_omasend._tcp", (ushort)network.Port);
        profile.AddProperty("v", "1"); profile.AddProperty("id", settings.DeviceId); profile.AddProperty("name", settings.DeviceName);
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
                var query = new Makaretu.Dns.Message();
                query.Questions.Add(new Question { Name = e.ServiceInstanceName, Type = DnsType.ANY });
                var response = await mdns.ResolveAsync(query, timeout.Token);
                records.AddRange(response.Answers.Concat(response.AdditionalRecords));
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
                if (addresses.Count == 0)
                {
                    var query = new Makaretu.Dns.Message();
                    query.Questions.Add(new Question { Name = srv.Target, Type = DnsType.ANY });
                    var response = await mdns.ResolveAsync(query, timeout.Token);
                    addresses.AddRange(response.Answers.Concat(response.AdditionalRecords).OfType<AddressRecord>().Where(r => r.Name == srv.Target).Select(r => r.Address));
                }
                foreach (var ip in addresses.Where(ip => !ip.Equals(IPAddress.Any) && !ip.IsIPv6LinkLocal)) _ = network.Probe(ip.ToString(), srv.Port);
            }
        }
        catch (Exception ex) when (ex is OperationCanceledException or IOException or System.Net.Sockets.SocketException or ObjectDisposedException or ArgumentException) { }
        finally { resolving.TryRemove(key, out _); }
    }
    private async Task Maintain()
    {
        try
        {
            using var timer = new PeriodicTimer(TimeSpan.FromSeconds(8));
            do
            {
                services.QueryServiceInstances("_omasend._tcp");
                foreach (string host in hosts) _ = network.Probe(host.Trim());
                await ProbeTailscale();
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
