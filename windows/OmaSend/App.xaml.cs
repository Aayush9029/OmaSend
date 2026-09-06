using System.Windows;

namespace OmaSend;

public partial class App : Application
{
    private Mutex? instance;
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        string root = Environment.GetEnvironmentVariable("OMASEND_DATA_DIR") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OmaSend", "Data");
        string identity = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(root)))[..16];
        instance = new Mutex(true, "Local\\OmaSend-" + identity, out bool created);
        if (!created) { MessageBox.Show("OmaSend is already running. Open it from the system tray.", "OmaSend"); Shutdown(); return; }
        try
        {
            var window = new MainWindow(root);
            MainWindow = window;
            if (!e.Args.Contains("--background")) window.Show();
        }
        catch (Exception ex)
        {
            MessageBox.Show("OmaSend could not start. " + ex.Message, "OmaSend", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }
    protected override void OnExit(ExitEventArgs e) { instance?.Dispose(); base.OnExit(e); }
}
