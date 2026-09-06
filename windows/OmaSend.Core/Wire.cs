using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace OmaSend.Core;

public sealed record Message
{
    [JsonRequired] public int Version { get; init; } = 1;
    [JsonRequired] public string Type { get; init; } = "hello";
    [JsonRequired] public string Id { get; init; } = Guid.NewGuid().ToString();
    [JsonRequired] public string OriginId { get; init; } = "";
    [JsonRequired] public string OriginName { get; init; } = "";
    [JsonRequired] public long CreatedAt { get; init; } = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
    public string? Text { get; init; }
    public string? ContentType { get; init; }
    public string? Data { get; init; }
    public string? FileName { get; init; }
    public long? FileSize { get; init; }
    [JsonPropertyName("fileSHA256")] public string? FileSha256 { get; init; }
    public long? ResumeOffset { get; init; }
    public string? FilePath { get; init; }
    public int? Port { get; init; }
}

public static class Wire
{
    public const int DefaultPort = 53317, MaxClipboard = 10 * 1024 * 1024;
    // Base64 image data is base64-encoded a second time in the encrypted envelope.
    public const int MaxFrame = 20 * 1024 * 1024, ChunkSize = 1024 * 1024;
    public static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        MaxDepth = 16
    };
    private sealed record Envelope(int Version, string Nonce, string Ciphertext);
    public static string NewSecret() => Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    private static AesGcm Cipher(string secret)
    {
        if (secret.Length < 20 || secret.Length > 1024) throw new InvalidDataException("Pairing code must contain 20 to 1024 characters.");
        return new AesGcm(SHA256.HashData(Encoding.UTF8.GetBytes(secret)), 16);
    }
    public static byte[] Seal(string secret, Message message, bool trustedLAN = false)
    {
        if (trustedLAN) return JsonSerializer.SerializeToUtf8Bytes(new LanEnvelope(1, "lan", message), Json);
        using var aes = Cipher(secret);
        byte[] plain = JsonSerializer.SerializeToUtf8Bytes(message, Json), nonce = RandomNumberGenerator.GetBytes(12);
        byte[] cipher = new byte[plain.Length + 16];
        aes.Encrypt(nonce, plain, cipher.AsSpan(0, plain.Length), cipher.AsSpan(plain.Length), "omasend-v1"u8);
        return JsonSerializer.SerializeToUtf8Bytes(new Envelope(1, Convert.ToBase64String(nonce), Convert.ToBase64String(cipher)), Json);
    }
    private sealed record LanEnvelope(int Version, string Mode, Message Message);
    public static Message Open(string secret, byte[] frame, bool trustedLAN = false)
    {
        if (frame.Length > MaxFrame) throw new InvalidDataException("Frame too large.");
        if (trustedLAN)
        {
            var lan = JsonSerializer.Deserialize<LanEnvelope>(frame, Json);
            if (lan is not { Version: 1, Mode: "lan", Message: not null }) throw new InvalidDataException("Not a Trusted LAN message.");
            return Validate(lan.Message);
        }
        var env = JsonSerializer.Deserialize<Envelope>(frame, Json) ?? throw new InvalidDataException();
        if (env.Nonce is null || env.Ciphertext is null) throw new InvalidDataException("Encrypted message required.");
        if (env.Version != 1) throw new InvalidDataException("Unsupported protocol version.");
        var nonce = Convert.FromBase64String(env.Nonce);
        var cipher = Convert.FromBase64String(env.Ciphertext);
        if (nonce.Length != 12 || cipher.Length < 16) throw new InvalidDataException("Invalid envelope.");
        using var aes = Cipher(secret);
        var plain = new byte[cipher.Length - 16];
        aes.Decrypt(nonce, cipher.AsSpan(0, plain.Length), cipher.AsSpan(plain.Length), plain, "omasend-v1"u8);
        var message = JsonSerializer.Deserialize<Message>(plain, Json) ?? throw new InvalidDataException();
        return Validate(message);
    }
    private static Message Validate(Message message)
    {
        if (message.Version != 1 || string.IsNullOrWhiteSpace(message.Id) || message.Id.Length > 256 ||
            string.IsNullOrWhiteSpace(message.OriginId) || message.OriginId.Length > 256 || message.OriginName is null || message.OriginName.Length > 256 ||
            Encoding.UTF8.GetByteCount(message.Text ?? "") > MaxClipboard ||
            (message.Data is not null && Convert.FromBase64String(message.Data).Length > MaxClipboard)) throw new InvalidDataException("Invalid message.");
        if (message.Type == "clipboard" && !ValidClipboard(message)) throw new InvalidDataException("Unsupported clipboard content.");
        // A remote filesystem path must never become a local clipboard file reference.
        return message with { FilePath = null };
    }
    public static bool ValidClipboard(Message m) =>
        (!string.IsNullOrWhiteSpace(m.Text) && (m.ContentType is null || m.ContentType.StartsWith("text/", StringComparison.Ordinal))) ||
        (m.ContentType is "image/png" or "image/jpeg" or "image/gif" && !string.IsNullOrEmpty(m.Data));
    public static async Task WriteFrame(Stream stream, byte[] payload, CancellationToken ct)
    {
        if (payload.Length is <= 0 or > MaxFrame) throw new InvalidDataException("Invalid frame length.");
        byte[] header = new byte[4];
        BinaryPrimitives.WriteInt32BigEndian(header, payload.Length);
        await stream.WriteAsync(header, ct);
        await stream.WriteAsync(payload, ct);
    }
    public static async Task<byte[]> ReadFrame(Stream stream, CancellationToken ct)
    {
        byte[] header = new byte[4];
        await stream.ReadExactlyAsync(header, ct);
        int length = BinaryPrimitives.ReadInt32BigEndian(header);
        if (length is <= 0 or > MaxFrame) throw new InvalidDataException("Invalid frame length.");
        byte[] payload = new byte[length];
        await stream.ReadExactlyAsync(payload, ct);
        return payload;
    }
    private static byte[] FileAad(string id, long offset)
    {
        var prefix = Encoding.UTF8.GetBytes("omasend-file-v1" + id);
        byte[] aad = new byte[prefix.Length + 8];
        prefix.CopyTo(aad, 0);
        BinaryPrimitives.WriteInt64BigEndian(aad.AsSpan(prefix.Length), offset);
        return aad;
    }
    public static byte[] SealChunk(string secret, string id, long offset, byte[] plain, byte[]? nonce = null, bool trustedLAN = false)
    {
        if (offset < 0 || plain.Length is <= 0 or > ChunkSize) throw new InvalidDataException();
        if (trustedLAN)
        {
            byte[] lan = new byte[12 + plain.Length]; "OSL1"u8.CopyTo(lan);
            BinaryPrimitives.WriteInt64BigEndian(lan.AsSpan(4), offset); plain.CopyTo(lan, 12); return lan;
        }
        using var aes = Cipher(secret);
        byte[] payload = new byte[36 + plain.Length];
        BinaryPrimitives.WriteInt64BigEndian(payload, offset);
        (nonce ?? RandomNumberGenerator.GetBytes(12)).CopyTo(payload, 8);
        aes.Encrypt(payload.AsSpan(8, 12), plain, payload.AsSpan(20, plain.Length), payload.AsSpan(20 + plain.Length), FileAad(id, offset));
        return payload;
    }
    public static byte[] OpenChunk(string secret, string id, long offset, byte[] payload, bool trustedLAN = false)
    {
        if (trustedLAN)
        {
            if (offset < 0 || payload.Length is <= 12 or > ChunkSize + 12 || !payload.AsSpan(0, 4).SequenceEqual("OSL1"u8) || BinaryPrimitives.ReadInt64BigEndian(payload.AsSpan(4)) != offset) throw new InvalidDataException("Invalid LAN file chunk.");
            return payload[12..];
        }
        if (offset < 0 || payload.Length is <= 36 or > ChunkSize + 36 || BinaryPrimitives.ReadInt64BigEndian(payload) != offset) throw new InvalidDataException("Invalid file chunk.");
        using var aes = Cipher(secret);
        byte[] plain = new byte[payload.Length - 36];
        aes.Decrypt(payload.AsSpan(8, 12), payload.AsSpan(20, plain.Length), payload.AsSpan(20 + plain.Length), plain, FileAad(id, offset));
        return plain;
    }
}
