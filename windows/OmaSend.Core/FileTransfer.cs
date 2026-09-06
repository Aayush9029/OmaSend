using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;

namespace OmaSend.Core;

public sealed partial class PeerNetwork
{
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, byte> transfers = new();
    private readonly SemaphoreSlim fileSendSlots = new(4);
    public static string SafeFileName(string raw)
    {
        string name = raw.Replace('\\', '/').Split('/').Last();
        if (name.Length is 0 or > 240 || name is "." or ".." || name.EndsWith('.') || name.EndsWith(' ') ||
            name.Any(c => c < 32 || "<>:\"/\\|?*".Contains(c))) throw new InvalidDataException("Unsafe filename.");
        string stem = name.Split('.')[0].ToUpperInvariant();
        if (stem is "CON" or "PRN" or "AUX" or "NUL" ||
            (stem.Length == 4 && (stem.StartsWith("COM") || stem.StartsWith("LPT")) && char.IsDigit(stem[3]))) throw new InvalidDataException("Reserved filename.");
        return name;
    }
    private static async Task<string> HashFile(string path, CancellationToken ct)
    {
        await using var file = File.OpenRead(path);
        return Convert.ToHexStringLower(await SHA256.HashDataAsync(file, ct));
    }
    public async Task<Message> ShareFile(string path)
    {
        var info = new FileInfo(path);
        if (!info.Exists || info.Length <= 0 || (info.Attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0) throw new InvalidDataException("Choose a nonempty regular file.");
        var message = NewMessage("file") with
        {
            ContentType = "application/x-omasend-file", FileName = SafeFileName(info.Name), FileSize = info.Length,
            FilePath = info.FullName, FileSha256 = await HashFile(path, lifetime.Token)
        };
        await Task.WhenAll(Peers.Select(p => SendFileWithRetry(p, message)));
        return message;
    }
    private async Task SendFileWithRetry(Peer peer, Message message)
    {
        try
        {
            await fileSendSlots.WaitAsync(lifetime.Token);
            try
            {
                for (int attempt = 0; attempt < 6; attempt++)
                {
                    try { await SendFile(peer, message); return; }
                    catch (Exception ex) when (Expected(ex))
                    {
                        if (lifetime.IsCancellationRequested) return;
                        if (attempt == 5) { Error?.Invoke($"File transfer to {peer.Name} failed. Copy the file again to retry."); return; }
                        await Task.Delay(TimeSpan.FromSeconds(attempt + 1), lifetime.Token);
                    }
                }
            }
            finally { fileSendSlots.Release(); }
        }
        catch (OperationCanceledException) { }
    }
    private async Task SendFile(Peer peer, Message message)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        timeout.CancelAfter(TimeSpan.FromSeconds(5));
        using var client = new TcpClient();
        await client.ConnectAsync(peer.Host, peer.Port, timeout.Token);
        CheckAddress(client);
        timeout.CancelAfter(TimeSpan.FromMinutes(30));
        var ct = timeout.Token;
        var stream = client.GetStream();
        await Wire.WriteFrame(stream, Seal(message with { Type = "file_offer", FilePath = null }), ct);
        var resume = Open(await Wire.ReadFrame(stream, ct));
        long offset = resume.ResumeOffset ?? 0, size = message.FileSize!.Value;
        if (resume.Type != "file_resume" || resume.Id != message.Id || offset < 0 || offset > size) throw new InvalidDataException();
        await using var file = File.OpenRead(message.FilePath!);
        file.Position = offset;
        while (offset < size)
        {
            byte[] chunk = new byte[(int)Math.Min(Wire.ChunkSize, size - offset)];
            await file.ReadExactlyAsync(chunk, ct);
            await Wire.WriteFrame(stream, Wire.SealChunk(secret, message.Id, offset, chunk, trustedLAN: trustedLAN), ct);
            offset += chunk.Length;
        }
        await Wire.WriteFrame(stream, Seal(NewMessage("file_complete") with { Id = message.Id, FileSha256 = message.FileSha256 }), ct);
        var done = Open(await Wire.ReadFrame(stream, ct));
        if (done.Type != "file_done" || done.Id != message.Id) throw new InvalidDataException("Missing file acknowledgement.");
    }
    private async Task ReceiveFile(Stream stream, Message offer, CancellationToken ct)
    {
        string name = SafeFileName(offer.FileName ?? "");
        if (offer.FileSize is null or <= 0) throw new InvalidDataException();
        long size = offer.FileSize.Value;
        // Bind the partial to authenticated metadata, preventing another peer's ID from resuming it.
        string key = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes($"{offer.OriginId}\0{offer.Id}\0{name}\0{size}\0{offer.FileSha256}")));
        if (!transfers.TryAdd(key, 0)) return;
        try
        {
            Directory.CreateDirectory(downloads);
            string staging = Path.Combine(downloads, ".partial");
            Directory.CreateDirectory(staging);
            string partial = Path.Combine(staging, key + ".part");
            if (File.Exists(partial) && (File.GetAttributes(partial) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException();
            await using (var file = new FileStream(partial, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None, Wire.ChunkSize, true))
            {
                long offset = file.Length;
                if (offset > size) { file.SetLength(0); offset = 0; }
                var drive = new DriveInfo(Path.GetPathRoot(Path.GetFullPath(downloads))!);
                if (size - offset > drive.AvailableFreeSpace - 64 * 1024 * 1024) throw new IOException("Not enough disk space.");
                file.Position = offset;
                await Wire.WriteFrame(stream, Seal(NewMessage("file_resume") with { Id = offer.Id, ResumeOffset = offset }), ct);
                while (offset < size)
                {
                    var chunk = Wire.OpenChunk(secret, offer.Id, offset, await Wire.ReadFrame(stream, ct), trustedLAN);
                    if (chunk.LongLength > size - offset) throw new InvalidDataException();
                    await file.WriteAsync(chunk, ct);
                    offset += chunk.Length;
                }
                await file.FlushAsync(ct);
            }
            var complete = Open(await Wire.ReadFrame(stream, ct));
            string hash = await HashFile(partial, ct);
            if (complete.Type != "file_complete" || complete.Id != offer.Id || complete.FileSha256 != hash ||
                (offer.FileSha256 is not null && offer.FileSha256 != hash))
            {
                using var reset = File.Open(partial, FileMode.Truncate);
                throw new InvalidDataException("File hash mismatch.");
            }
            ct.ThrowIfCancellationRequested();
            ProtectReceivedFile?.Invoke(partial);
            string final = Path.Combine(downloads, name);
            for (int index = 2; ; index++)
            {
                try { File.Move(partial, final, false); break; }
                catch (IOException) when (File.Exists(final))
                { final = Path.Combine(downloads, $"{Path.GetFileNameWithoutExtension(name)} {index}{Path.GetExtension(name)}"); }
            }
            Received?.Invoke(offer with { Type = "file", FileName = name, FilePath = final, FileSha256 = hash });
            await Wire.WriteFrame(stream, Seal(NewMessage("file_done") with { Id = offer.Id }), ct);
        }
        finally { transfers.TryRemove(key, out _); }
    }
}
