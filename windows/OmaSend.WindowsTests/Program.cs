using OmaSend;
using OmaSend.Core;
using System.Windows;
using System.IO;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "init")
        {
            var store = new SettingsStore(args[1]);
            store.Save(new Settings { DeviceName = "Windows 11", PairingCode = "omasend-test-secret-0123456789-abcdef", AutoCopy = true });
            Console.WriteLine("Initialized isolated UI test settings."); return;
        }
        if (args.Length > 0 && args[0] == "read") { Console.WriteLine(Clipboard.ContainsText() ? Clipboard.GetText() : Clipboard.ContainsImage() ? "IMAGE" : Clipboard.ContainsFileDropList() ? Clipboard.GetFileDropList()[0] : "EMPTY"); return; }
        if (args.Length > 0 && args[0] == "text") { Clipboard.SetText(args[1]); return; }
        if (args.Length > 0 && args[0] == "file") { Clipboard.SetFileDropList(new System.Collections.Specialized.StringCollection { args[1] }); return; }
        using var clipboard = new ClipboardService();
        string root = Path.Combine(Path.GetTempPath(), "omasend-win-tests-" + Guid.NewGuid());
        try
        {
            var store = new SettingsStore(root); var settings = new Settings(); store.Save(settings);
            if (store.Load().PairingCode != settings.PairingCode || System.Text.Encoding.UTF8.GetString(File.ReadAllBytes(Path.Combine(root, "settings.dat"))).Contains(settings.PairingCode)) throw new Exception("DPAPI storage failed");
            var text = new Message { Text = "OmaSend Windows clipboard test 👋" };
            if (!clipboard.Write(text) || Clipboard.GetText() != text.Text) throw new Exception("Native text clipboard failed");
            var image = new Message { Data = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", ContentType = "image/png" };
            if (!clipboard.Write(image) || !Clipboard.ContainsImage()) throw new Exception("Native image clipboard failed");
            string path = Path.Combine(root, "sample.txt"); File.WriteAllText(path, "sample");
            if (!clipboard.Write(new() { Type = "file", FilePath = path }) || Clipboard.GetFileDropList()[0] != path) throw new Exception("Native file clipboard failed");
            clipboard.Write(text);
            Console.WriteLine("PASS Windows DPAPI storage, text, PNG, and file clipboard APIs");
        }
        finally { Directory.Delete(root, true); }
    }
}
