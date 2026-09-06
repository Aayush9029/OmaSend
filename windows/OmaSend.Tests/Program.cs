using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Text.Json;
using OmaSend.Core;

const string secret = "omasend-test-secret-0123456789-abcdef";
if (args.Contains("--bridge"))
{
    var inbox = new ConcurrentQueue<Message>();
    using var node = new PeerNetwork("windows-test", "Windows test", secret, args[Array.IndexOf(args, "--bridge") + 1], 0, IPAddress.Loopback);
    node.Received += inbox.Enqueue;
    Console.WriteLine(JsonSerializer.Serialize(new { port = node.Port }, Wire.Json));
    while (Console.ReadLine() is string line)
    {
        try
        {
            using var command = JsonDocument.Parse(line);
            var root = command.RootElement;
            switch (root.GetProperty("action").GetString())
            {
                case "status": Console.WriteLine(JsonSerializer.Serialize(new { peers = node.Peers, messages = inbox.ToArray() }, Wire.Json)); break;
                case "send":
                    await node.Broadcast(node.NewMessage("clipboard") with { Text = root.GetProperty("text").GetString(), ContentType = "text/plain" });
                    Console.WriteLine("{}"); break;
                case "image":
                    await node.Broadcast(node.NewMessage("clipboard") with { Data = root.GetProperty("data").GetString(), ContentType = "image/png" });
                    Console.WriteLine("{}"); break;
                case "file": await node.ShareFile(root.GetProperty("path").GetString()!); Console.WriteLine("{}"); break;
                case "clear": await node.Broadcast(node.NewMessage("history_clear")); Console.WriteLine("{}"); break;
                case "quit": return;
            }
        }
        catch (Exception ex) { Console.WriteLine(JsonSerializer.Serialize(new { error = ex.Message })); }
    }
    return;
}
int passed = 0;
void Check(bool condition, string label) { if (!condition) throw new Exception(label); passed++; Console.WriteLine("PASS " + label); }
void Reject(Action action, string label) { try { action(); } catch { Check(true, label); return; } throw new Exception("Accepted " + label); }
var item = new Message { OriginId = "test", Type = "clipboard", Text = "Unicode 👋\n你好", ContentType = "text/plain" };
Check(Wire.Open(secret, Wire.Seal(secret, item)).Text == item.Text, "UTF-8 encrypted roundtrip");
const string vector = "{\"version\":1,\"nonce\":\"AAECAwQFBgcICQoL\",\"ciphertext\":\"BuLeQaS379eOUMKOqEQkmh/VItWh+DDVCEpm+aX9PgUW+hi7WSjtc1AkBkakzCrnyad5Iu8KDPnYSUCpct+jYu5X8nWbPJzO+zbgXMlzG7ZEigRZlzBagX3AnwmZH1Rk4wQw2kH62UJGHdtVLv43+3dwdsJVa/eQP+4yVhC/tmhANG7kw4iN7bjsz0q3aRHc0z1B+mf++WeF\"}";
Check(Wire.Open(secret, Encoding.UTF8.GetBytes(vector)).Text == "OmaSend interop", "existing Go/Swift vector");
Reject(() => Wire.Open("wrong-code-0123456789012345", Wire.Seal(secret, item)), "wrong key");
Reject(() => Wire.Open(secret, "{\"version\":1,\"nonce\":\"AA==\",\"ciphertext\":\"AA==\"}"u8.ToArray()), "malformed nonce");
Reject(() => Wire.Open(secret, Wire.Seal(secret, item with { Text = new string('x', Wire.MaxClipboard + 1) })), "oversized text");
Reject(() => Wire.Open(secret, Wire.Seal(secret, item with { Text = "   " })), "empty clipboard");
Check(Wire.Open(secret, Wire.Seal(secret, item with { FilePath = "C:\\private.txt" })).FilePath is null, "remote path stripped");
var chunk = Wire.SealChunk(secret, "transfer-1", 4096, "OmaSend file chunk"u8.ToArray(), Enumerable.Range(0, 12).Select(i => (byte)i).ToArray());
Check(Convert.ToHexStringLower(chunk) == "0000000000001000000102030405060708090a0b32adc977b3aae298861b94daa405389601db437066285b755d54209de91e130af412", "Go/Swift file vector");
Reject(() => Wire.OpenChunk(secret, "other", 4096, chunk), "file transfer ID binding");
Reject(() => Wire.OpenChunk(secret, "transfer-1", 0, chunk), "file offset binding");
chunk[^1] ^= 1; Reject(() => Wire.OpenChunk(secret, "transfer-1", 4096, chunk), "tampered chunk");
foreach (string name in new[] { "..", "CON", "report.txt:evil", "bad.", "NUL.exe", "a\u0001b" }) Reject(() => PeerNetwork.SafeFileName(name), "unsafe filename " + name);
Check(PeerNetwork.SafeFileName("../../safe.txt") == "safe.txt", "basename isolation");
var history = new History(); history.Add(item); history.Clear(); Check(!history.Add(item), "duplicate suppression survives clear");
for (int i = 0; i < 70; i++) history.Add(item with { Id = i.ToString() }); Check(history.Snapshot.Length == 50, "bounded history");
await using var frame = new MemoryStream(); await Wire.WriteFrame(frame, "framed"u8.ToArray(), default); frame.Position = 0;
Check(Encoding.UTF8.GetString(await Wire.ReadFrame(frame, default)) == "framed", "length prefix");
foreach (byte[] header in new[] { new byte[4], new byte[] { 127, 255, 255, 255 }, new byte[] { 0, 0, 0, 2, 1 } })
{
    bool rejected = false; try { await Wire.ReadFrame(new MemoryStream(header), default); } catch (Exception ex) when (ex is IOException or InvalidDataException) { rejected = true; }
    Check(rejected, "malformed or truncated frame");
}
string temp = Path.Combine(Path.GetTempPath(), "omasend-tests-" + Guid.NewGuid());
Directory.CreateDirectory(temp);
try
{
    using var a = new PeerNetwork("a", "Windows A", secret, Path.Combine(temp, "a"), 0, IPAddress.Loopback);
    using var b = new PeerNetwork("b", "Simulated peer B", secret, Path.Combine(temp, "b"), 0, IPAddress.Loopback);
    using var c = new PeerNetwork("c", "Simulated peer C", secret, Path.Combine(temp, "c"), 0, IPAddress.Loopback);
    var gotB = new ConcurrentQueue<Message>(); var gotC = new ConcurrentQueue<Message>();
    b.Received += gotB.Enqueue; c.Received += gotC.Enqueue;
    await a.Probe("127.0.0.1", b.Port); await a.Probe("127.0.0.1", c.Port);
    Check(a.Peers.Length == 2 && b.Peers.Single().Port == a.Port, "multiple authenticated peers and advertised return port");
    await a.Broadcast(a.NewMessage("clipboard") with { Text = "fanout" });
    await Task.Delay(150);
    Check(gotB.Count == 1 && gotC.Count == 1, "simultaneous two-peer broadcast without relay");
    string source = Path.Combine(temp, "sample.bin"); byte[] bytes = System.Security.Cryptography.RandomNumberGenerator.GetBytes(2 * Wire.ChunkSize + 17); await File.WriteAllBytesAsync(source, bytes);
    await a.ShareFile(source);
    Check(File.ReadAllBytes(Path.Combine(temp, "b", "sample.bin")).SequenceEqual(bytes) && File.ReadAllBytes(Path.Combine(temp, "c", "sample.bin")).SequenceEqual(bytes), "multi-chunk file fanout and full digest");
    using var wrong = new PeerNetwork("wrong", "Wrong code", Wire.NewSecret(), Path.Combine(temp, "wrong"), 0, IPAddress.Loopback);
    await wrong.Probe("127.0.0.1", a.Port);
    Check(wrong.Peers.Length == 0 && a.Peers.Length == 2, "wrong-code peer excluded");
}
finally { Directory.Delete(temp, true); }
Console.WriteLine($"{passed} checks passed. Network peers in this suite are simulated C# clients.");
