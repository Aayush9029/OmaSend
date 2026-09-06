using System.Collections.Specialized;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace OmaSend;

public sealed class ClipboardService : IDisposable
{
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(450) };
    private uint sequence;
    public event Action<Message>? Changed;
    public event Action<string>? FileCopied;
    public event Action<string>? Error;
    [DllImport("user32.dll")] private static extern uint GetClipboardSequenceNumber();
    public ClipboardService()
    {
        sequence = GetClipboardSequenceNumber(); // Never send clipboard contents predating app startup.
        timer.Tick += (_, _) => Poll();
        timer.Start();
    }
    private void Poll()
    {
        if (GetClipboardSequenceNumber() == sequence) return;
        try
        {
            uint observed = GetClipboardSequenceNumber();
            if (Clipboard.ContainsFileDropList())
            {
                string? path = Clipboard.GetFileDropList().Cast<string>().FirstOrDefault(File.Exists);
                sequence = observed;
                if (path is not null) FileCopied?.Invoke(path);
                return;
            }
            Message? message = null;
            if (Clipboard.ContainsImage())
            {
                var source = Clipboard.GetImage();
                if (source is not null)
                {
                    var encoder = new PngBitmapEncoder();
                    encoder.Frames.Add(BitmapFrame.Create(source));
                    using var stream = new MemoryStream(); encoder.Save(stream);
                    if (stream.Length <= Wire.MaxClipboard) message = new() { Type = "clipboard", ContentType = "image/png", Data = Convert.ToBase64String(stream.ToArray()) };
                }
            }
            else if (Clipboard.ContainsText())
            {
                string text = Clipboard.GetText();
                if (!string.IsNullOrWhiteSpace(text) && Encoding.UTF8.GetByteCount(text) <= Wire.MaxClipboard)
                    message = new() { Type = "clipboard", ContentType = "text/plain", Text = text };
            }
            sequence = observed;
            if (message is not null) Changed?.Invoke(message);
        }
        catch (ExternalException) { /* Clipboard temporarily owned by another app. Retry next tick. */ }
        catch (Exception ex) when (ex is IOException or NotSupportedException or ArgumentException)
        { sequence = GetClipboardSequenceNumber(); Error?.Invoke("Could not read this clipboard format."); }
    }
    public static BitmapSource DecodeImage(string data, int decodeWidth = 0)
    {
        byte[] bytes = Convert.FromBase64String(data);
        if (bytes.Length > Wire.MaxClipboard) throw new InvalidDataException();
        using var stream = new MemoryStream(bytes);
        var image = new BitmapImage();
        image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad;
        if (decodeWidth > 0) image.DecodePixelWidth = decodeWidth;
        image.StreamSource = stream; image.EndInit(); image.Freeze();
        if ((long)image.PixelWidth * image.PixelHeight > 64_000_000) throw new InvalidDataException("Image dimensions exceed the safe limit.");
        return image;
    }
    public bool Write(Message message)
    {
        try
        {
            if (message.Type == "file" && message.FilePath is not null && File.Exists(message.FilePath))
                Clipboard.SetFileDropList(new StringCollection { message.FilePath });
            else if (message.Data is not null && message.ContentType?.StartsWith("image/", StringComparison.Ordinal) == true)
                Clipboard.SetImage(DecodeImage(message.Data));
            else if (message.Text is not null) Clipboard.SetText(message.Text);
            else return false;
            sequence = GetClipboardSequenceNumber();
            return true;
        }
        catch (Exception ex) when (ex is ExternalException or IOException or InvalidDataException or NotSupportedException or ArgumentException or FormatException)
        { Error?.Invoke("Could not copy this item. Try again when the clipboard is available."); return false; }
    }
    public void CopySecret(string value) => Write(new() { Text = value });
    public void Dispose() => timer.Stop();
}
