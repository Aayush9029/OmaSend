using Makaretu.Dns;
using OmaSend;
using OmaSend.Core;
using System.Net;
using System.IO;

internal static class DiscoveryChecks
{
    public static async Task Run()
    {
        const string key = "omasend-discovery-test-secret-12345";
        string suffix = Guid.NewGuid().ToString("N");
        using var peer = new PeerNetwork("split-" + suffix, "Split Bonjour peer", key, Path.GetTempPath(), 0, IPAddress.Loopback);
        using var node = new PeerNetwork("node-" + suffix, "Discovery test", key, Path.GetTempPath(), 0, IPAddress.Loopback);
        using var responder = new MulticastService();
        DomainName instance = "Split-" + suffix + "._omasend._tcp.local";
        DomainName host = "Split-" + suffix + ".local";
        int responding = 0;
        void Send(ResourceRecord record, bool additional = false)
        {
            var message = new Makaretu.Dns.Message { QR = true };
            if (additional)
            {
                message.Answers.Add(new PTRRecord { Name = "_omasend._tcp.local", DomainName = instance });
                message.AdditionalRecords.Add(record);
            }
            else message.Answers.Add(record);
            responder.SendAnswer(message, false);
        }
        responder.QueryReceived += (_, e) =>
        {
            if (!e.Message.Questions.Any(q => q.Name == instance || q.Name == host) || Interlocked.Exchange(ref responding, 1) != 0) return;
            _ = Task.Run(async () =>
            {
                try
                {
                    // First matching-name response is deliberately incomplete.
                    Send(new TXTRecord { Name = instance, Strings = { "v=1", "id=split-" + suffix, "name=Split Bonjour peer" } });
                    await Task.Delay(150);
                    Send(new SRVRecord { Name = instance, Target = host, Port = (ushort)peer.Port }, additional: true);
                    await Task.Delay(150);
                    Send(AddressRecord.Create(host, IPAddress.Loopback), additional: true);
                }
                finally { Interlocked.Exchange(ref responding, 0); }
            });
        };
        responder.Start();
        using var discovery = new Discovery(node, new Settings { DeviceId = "node-" + suffix, PairingCode = key, DeviceName = "Discovery test" });
        for (int i = 0; i < 30 && !node.Peers.Any(p => p.Id == "split-" + suffix); i++)
        {
            Send(new PTRRecord { Name = "_omasend._tcp.local", DomainName = instance });
            await Task.Delay(500);
        }
        if (!node.Peers.Any(p => p.Id == "split-" + suffix)) throw new Exception("Split Bonjour records did not produce an authenticated peer.");
        Console.WriteLine("PASS split TXT/SRV/address packets, additional records, authenticated peer discovery");
    }
}
