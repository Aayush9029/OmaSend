using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace OmaSend;

public partial class MainWindow : Window
{
    private readonly SettingsStore store;
    private readonly Settings settings;
    private readonly History history = new();
    private readonly ClipboardService clipboard;
    private readonly Forms.NotifyIcon tray;
    private PeerNetwork? network;
    private Discovery? discovery;
    private bool quitting;
    private Window? settingsWindow;
    public MainWindow(string root)
    {
        InitializeComponent();
        SourceInitialized += (_, _) =>
        {
            int enabled = 1;
            _ = DwmSetWindowAttribute(new System.Windows.Interop.WindowInteropHelper(this).Handle, 20, ref enabled, sizeof(int));
        };
        store = new SettingsStore(root); settings = store.Load();
        foreach (var item in settings.History.Reverse()) history.Add(item);
        clipboard = new ClipboardService();
        clipboard.Error += ShowError;
        clipboard.Changed += async item =>
        {
            if (network is null) return;
            var message = item with { OriginId = settings.DeviceId, OriginName = settings.DeviceName, Port = network.Port };
            Add(message, false);
            await network.Broadcast(message);
        };
        clipboard.FileCopied += async path =>
        {
            if (network is null) return;
            try { Add(await network.ShareFile(path), false); }
            catch (Exception ex) when (ex is IOException or InvalidDataException or UnauthorizedAccessException or OperationCanceledException or ArgumentException)
            { ShowError("Could not share this file. " + ex.Message); }
        };
        tray = new Forms.NotifyIcon { Text = "OmaSend", Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!), Visible = true };
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Open OmaSend", null, (_, _) => Dispatcher.Invoke(OpenPanel));
        menu.Items.Add("Settings", null, (_, _) => Dispatcher.Invoke(() => OpenSettings(this, new RoutedEventArgs())));
        menu.Items.Add("Quit OmaSend", null, (_, _) => Dispatcher.Invoke(Quit));
        tray.ContextMenuStrip = menu;
        tray.MouseClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) Dispatcher.Invoke(OpenPanel); };
        Closing += (_, e) => { if (!quitting) { e.Cancel = true; Hide(); } };
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) Hide(); };
        StartNetwork(); Render();
    }
    private void StartNetwork()
    {
        discovery?.Dispose(); network?.Dispose(); discovery = null; network = null;
        try
        {
            string downloads = Environment.GetEnvironmentVariable("OMASEND_DOWNLOADS") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "OmaSend");
            int port = int.TryParse(Environment.GetEnvironmentVariable("OMASEND_PORT"), out int p) && p is > 0 and < 65536 ? p : Wire.DefaultPort;
            var current = new PeerNetwork(settings.DeviceId, settings.DeviceName, settings.PairingCode, downloads, port)
            {
                // Preserve Attachment Manager / SmartScreen behavior for files arriving over the network.
                ProtectReceivedFile = path => File.WriteAllText(path + ":Zone.Identifier", "[ZoneTransfer]\r\nZoneId=3\r\n")
            };
            network = current;
            current.Received += message => Dispatcher.BeginInvoke(() =>
            {
                if (network != current) return;
                if (message.Type == "history_clear")
                { if (history.Remember(message.Id)) { history.Clear(); Persist(); Render(); } }
                else Add(message, true);
            });
            current.PeersChanged += () => Dispatcher.BeginInvoke(RenderPeers);
            current.Error += error => Dispatcher.BeginInvoke(() => ShowError(error));
            if (Environment.GetEnvironmentVariable("OMASEND_NO_DISCOVERY") != "1") discovery = new Discovery(current, settings);
        }
        catch (Exception ex) when (ex is System.Net.Sockets.SocketException or IOException or ArgumentException)
        { ShowError("Network unavailable. " + ex.Message); }
    }
    private void Add(Message message, bool received)
    {
        if (message.Data is not null)
        {
            try { _ = ClipboardService.DecodeImage(message.Data, 160); }
            catch (Exception ex) when (ex is IOException or InvalidDataException or NotSupportedException or ArgumentException or FormatException)
            { ShowError("Received image could not be decoded."); return; }
        }
        if (!history.Add(message)) return;
        if (received && settings.AutoCopy) clipboard.Write(message);
        Persist(); Render();
    }
    private void Persist()
    {
        try { settings.History = history.Snapshot; store.Save(settings); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception)
        { ShowError("Could not save clipboard history or settings."); }
    }
    private void RenderPeers()
    {
        var peers = network?.Peers ?? [];
        PeerTitle.Text = peers.Length == 0 ? "Looking for paired devices" : string.Join(", ", peers.Select(p => p.Name));
        PeerDetail.Text = peers.Length == 0 ? "Use the same pairing code on every device" : $"{peers.Length} {(peers.Length == 1 ? "device" : "devices")} connected · " + string.Join(" / ", peers.Select(p => p.Via).Distinct());
        PeerTitle.ToolTip = string.Join("\n", peers.Select(p => p.Name + " · " + p.Via));
        Pulse.Opacity = peers.Length > 0 ? 1 : .35;
    }
    private void Render()
    {
        RenderPeers();
        AutoLabel.Text = settings.AutoCopy ? "◉  Turn Off Auto Copy" : "◉  Turn On Auto Copy";
        HistoryRows.Children.Clear();
        var items = history.Snapshot;
        EmptyState.Visibility = items.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        foreach (var item in items)
        {
            var button = new Button { Margin = new Thickness(0, 1, 0, 1), ToolTip = $"{item.OriginName} · {DateTimeOffset.FromUnixTimeMilliseconds(Math.Clamp(item.CreatedAt, 0, 253402300799999)).LocalDateTime:g}" };
            System.Windows.Automation.AutomationProperties.SetName(button, "Copy " + (item.FileName ?? item.Text ?? "image"));
            var grid = new Grid(); grid.ColumnDefinitions.Add(new() { Width = new GridLength(24) }); grid.ColumnDefinitions.Add(new()); grid.ColumnDefinitions.Add(new() { Width = new GridLength(22) });
            var icon = new TextBlock { Text = item.Type == "file" ? "\uE8A5" : "\uE8C8", FontFamily = new FontFamily("Segoe Fluent Icons"), Foreground = (Brush)FindResource("Muted"), VerticalAlignment = VerticalAlignment.Center };
            grid.Children.Add(icon);
            FrameworkElement content;
            if (item.Data is not null)
            {
                try { content = new Image { Source = ClipboardService.DecodeImage(item.Data, 600), Height = 78, Stretch = Stretch.UniformToFill, ClipToBounds = true }; }
                catch { content = new TextBlock { Text = "Image unavailable" }; }
            }
            else content = new TextBlock { Text = item.FileName ?? item.Text, TextWrapping = TextWrapping.Wrap, MaxHeight = 42, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center, FontWeight = FontWeights.Medium };
            Grid.SetColumn(content, 1); grid.Children.Add(content);
            var copy = new TextBlock { Text = "\uE8C8", FontFamily = new FontFamily("Segoe Fluent Icons"), Foreground = (Brush)FindResource("Muted"), VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Right };
            Grid.SetColumn(copy, 2); grid.Children.Add(copy); button.Content = grid;
            button.Click += (_, _) => { if (clipboard.Write(item)) { ErrorText.Visibility = Visibility.Collapsed; } };
            HistoryRows.Children.Add(button);
        }
    }
    private void ToggleAuto(object sender, RoutedEventArgs e) { settings.AutoCopy = !settings.AutoCopy; Persist(); Render(); }
    private void ShowError(string text) { ErrorText.Text = text; ErrorText.Visibility = Visibility.Visible; }
    private void OpenPanel() { Show(); WindowState = WindowState.Normal; Activate(); }
    private void Quit()
    {
        quitting = true; clipboard.Dispose(); discovery?.Dispose(); network?.Dispose(); tray.Dispose();
        Application.Current.Shutdown();
    }
    private void OpenSettings(object sender, RoutedEventArgs e)
    {
        if (settingsWindow is not null) { settingsWindow.Activate(); return; }
        var panel = new StackPanel { Margin = new Thickness(24) };
        void Label(string text) => panel.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap });
        Label("Devices");
        Label("Use one pairing code on your Mac, Windows PC, and Linux computer. All paired devices can read shared items.");
        var code = new PasswordBox { Password = settings.PairingCode, MaxLength = 1024 }; panel.Children.Add(code);
        var copy = new Button { Content = "Copy this device’s pairing code" }; copy.Click += (_, _) => clipboard.CopySecret(settings.PairingCode); panel.Children.Add(copy);
        Label("Device name"); var name = new TextBox { Text = settings.DeviceName, MaxLength = 100 }; panel.Children.Add(name);
        Label("Optional peer IP addresses or hostnames (one per line)");
        var hosts = new TextBox { Text = string.Join("\n", settings.Hosts), AcceptsReturn = true, Height = 62 }; panel.Children.Add(hosts);
        Label("Local discovery is automatic. Tailscale peers are discovered when Tailscale is installed. Allow OmaSend on trusted private networks if Windows asks.");
        var startup = new CheckBox { Content = "Launch at sign-in", IsChecked = StartupEnabled() }; panel.Children.Add(startup);
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap, Foreground = Brushes.LightSalmon }; panel.Children.Add(status);
        var save = new Button { Content = "Save settings", Background = new SolidColorBrush(Color.FromRgb(49, 72, 117)) };
        save.Click += (_, _) =>
        {
            string secret = code.Password.Trim();
            if (secret.Length < 20) { status.Text = "Pairing codes must contain at least 20 characters."; return; }
            settings.PairingCode = secret; settings.DeviceName = string.IsNullOrWhiteSpace(name.Text) ? Environment.MachineName : name.Text.Trim();
            settings.Hosts = hosts.Text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Distinct().Take(32).ToArray();
            try { SetStartup(startup.IsChecked == true); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.SecurityException) { status.Text = "Could not update launch at sign-in."; return; }
            Persist(); StartNetwork(); Render(); settingsWindow?.Close();
        };
        panel.Children.Add(save);
        var clear = new Button { Content = "Clear history on connected devices" };
        clear.Click += async (_, _) =>
        {
            if (MessageBox.Show(settingsWindow, "Clear clipboard history on this computer and every connected device? Downloaded files are kept.", "Clear history", MessageBoxButton.OKCancel) != MessageBoxResult.OK) return;
            history.Clear(); Persist(); Render(); if (network is not null) await network.Broadcast(network.NewMessage("history_clear"));
        };
        panel.Children.Add(clear);
        Label("OmaSend 0.2.0 · Text, images, and files\nFiles arrive in Downloads/OmaSend. Closing the panel keeps OmaSend in the system tray.");
        settingsWindow = new Window { Title = "OmaSend Settings", Width = 470, Height = 730, MinWidth = 390, MinHeight = 500, Background = Background, Foreground = Foreground, FontFamily = FontFamily, FontSize = 14, Content = new ScrollViewer { Content = panel }, Owner = this, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        settingsWindow.Closed += (_, _) => settingsWindow = null;
        settingsWindow.Show();
    }
    private static bool StartupEnabled()
    {
        using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        return key?.GetValue("OmaSend") is string;
    }
    [System.Runtime.InteropServices.DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
    private static void SetStartup(bool enabled)
    {
        using var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        if (enabled) key.SetValue("OmaSend", $"\"{Environment.ProcessPath}\" --background"); else key.DeleteValue("OmaSend", false);
    }
}
