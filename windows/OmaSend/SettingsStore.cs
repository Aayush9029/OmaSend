using System.Runtime.InteropServices;
using System.Text.Json;
using System.Security.AccessControl;
using System.Security.Principal;

namespace OmaSend;

public sealed class Settings
{
    public string DeviceId { get; set; } = Guid.NewGuid().ToString();
    public string DeviceName { get; set; } = Environment.MachineName;
    public string PairingCode { get; set; } = Wire.NewSecret();
    public bool TrustedLAN { get; set; }
    public bool AutoCopy { get; set; }
    public string[] Hosts { get; set; } = [];
    public Message[] History { get; set; } = [];
}

public sealed class SettingsStore
{
    private readonly string path;
    public SettingsStore(string root)
    {
        var directory = Directory.CreateDirectory(root);
        // Protect the whole directory as well as encrypting its contents for this Windows user.
        var acl = new DirectorySecurity();
        acl.SetAccessRuleProtection(true, false);
        acl.AddAccessRule(new FileSystemAccessRule(WindowsIdentity.GetCurrent().User!, FileSystemRights.FullControl,
            InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        directory.SetAccessControl(acl);
        path = Path.Combine(root, "settings.dat");
    }
    public Settings Load() => File.Exists(path)
        ? JsonSerializer.Deserialize<Settings>(Protect(File.ReadAllBytes(path), false), Wire.Json) ?? throw new InvalidDataException("Invalid saved settings.")
        : new Settings();
    public void Save(Settings settings)
    {
        var bytes = Protect(JsonSerializer.SerializeToUtf8Bytes(settings, Wire.Json), true);
        File.WriteAllBytes(path + ".tmp", bytes);
        File.Move(path + ".tmp", path, true);
    }
    [StructLayout(LayoutKind.Sequential)] private struct Blob { public int Size; public IntPtr Data; }
    [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CryptProtectData(ref Blob input, string? description, IntPtr entropy, IntPtr reserved, IntPtr prompt, int flags, out Blob output);
    [DllImport("crypt32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CryptUnprotectData(ref Blob input, IntPtr description, IntPtr entropy, IntPtr reserved, IntPtr prompt, int flags, out Blob output);
    [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);
    private static byte[] Protect(byte[] data, bool encrypt)
    {
        var input = new Blob { Size = data.Length, Data = Marshal.AllocHGlobal(data.Length) };
        Blob output = default;
        try
        {
            Marshal.Copy(data, 0, input.Data, data.Length);
            bool ok = encrypt ? CryptProtectData(ref input, "OmaSend", IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 1, out output)
                : CryptUnprotectData(ref input, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 1, out output);
            if (!ok) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            byte[] result = new byte[output.Size];
            Marshal.Copy(output.Data, result, 0, output.Size);
            return result;
        }
        finally { Marshal.FreeHGlobal(input.Data); if (output.Data != IntPtr.Zero) LocalFree(output.Data); }
    }
}
