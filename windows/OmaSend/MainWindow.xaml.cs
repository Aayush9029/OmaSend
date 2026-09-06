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
    private string page = "home";
    private string deviceLayout = "";
    private bool confirming;
    private bool openingPanel;
    public MainWindow(string root)
    {
        InitializeComponent();
        SourceInitialized += (_, _) =>
        {
            var handle = new System.Windows.Interop.WindowInteropHelper(this).Handle;
            int corners = 2; // Let Windows draw the outer flyout edge.
            _ = DwmSetWindowAttribute(handle, 33, ref corners, sizeof(int));
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
        tray.MouseClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) Dispatcher.Invoke(() => { if (IsVisible) Hide(); else OpenPanel(); }); };
        Closing += (_, e) => { if (!quitting) { e.Cancel = true; Hide(); } };
        Deactivated += (_, _) => { if (!confirming && !openingPanel) Hide(); };
        DpiChanged += (_, _) => Dispatcher.BeginInvoke(PositionPanel);
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
            var current = new PeerNetwork(settings.DeviceId, settings.DeviceName, settings.PairingCode, downloads, port, trustedLAN: settings.TrustedLAN)
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
            if (Environment.GetEnvironmentVariable("OMASEND_NO_DISCOVERY") != "1")
            {
                discovery = new Discovery(current, settings);
                discovery.CandidatesChanged += () => Dispatcher.BeginInvoke(RenderPeers);
            }
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
        var nearby = discovery?.Candidates.Where(c => !peers.Any(p => p.Id == c.Id)).ToArray() ?? [];
        PeerTitle.Text = peers.Length == 0 ? (nearby.Length == 0 ? "Looking for devices" : string.Join(", ", nearby.Select(c => c.Name))) : string.Join(", ", peers.Select(p => p.Name));
        PeerDetail.Text = peers.Length == 0 ? (nearby.Length == 0 ? "Not connected" : "Pair in Settings") : $"{peers.Length} {(peers.Length == 1 ? "device" : "devices")} connected";
        PeerTitle.ToolTip = string.Join("\n", peers.Select(p => p.Name + " · " + p.Via));
        if (page == "devices") RenderDevices();
    }
    private void Render()
    {
        RenderPeers();
        AutoButton.IsChecked = settings.AutoCopy;
        HistoryRows.Children.Clear();
        var items = history.Snapshot;
        EmptyState.Visibility = items.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        foreach (var item in items)
        {
            var button = new Button { Style = (Style)FindResource("RowButton"), Margin = new Thickness(0, 1, 0, 1), ToolTip = $"{item.OriginName} · {DateTimeOffset.FromUnixTimeMilliseconds(Math.Clamp(item.CreatedAt, 0, 253402300799999)).LocalDateTime:g}" };
            System.Windows.Automation.AutomationProperties.SetName(button, "Copy " + (item.FileName ?? item.Text ?? "image"));
            var grid = new Grid(); grid.ColumnDefinitions.Add(new()); grid.ColumnDefinitions.Add(new() { Width = new GridLength(30) });
            FrameworkElement content;
            if (item.Data is not null)
            {
                try { content = new Image { Source = ClipboardService.DecodeImage(item.Data, 600), Height = 78, Stretch = Stretch.Uniform, ClipToBounds = true }; }
                catch { content = new TextBlock { Text = "Image unavailable" }; }
            }
            else content = new TextBlock { Text = item.FileName ?? item.Text, TextWrapping = TextWrapping.Wrap, MaxHeight = 42, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center, FontWeight = FontWeights.Normal };
            grid.Children.Add(content);
            var copy = new TextBlock { Text = "\uE8C8", FontFamily = new FontFamily("Segoe Fluent Icons"), Foreground = (Brush)FindResource("TextFillColorSecondaryBrush"), VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Right };
            Grid.SetColumn(copy, 1); grid.Children.Add(copy); button.Content = grid;
            button.Click += (_, _) => { if (clipboard.Write(item)) { ErrorText.Visibility = Visibility.Collapsed; } };
            HistoryRows.Children.Add(button);
        }
    }
    private void ToggleAuto(object sender, RoutedEventArgs e) { settings.AutoCopy = !settings.AutoCopy; Persist(); Render(); }
    private void ShowError(string text) { ErrorText.Text = text; ErrorText.Visibility = Visibility.Visible; }
    public void OpenPanel()
    {
        openingPanel = true;
        try
        {
            new System.Windows.Interop.WindowInteropHelper(this).EnsureHandle();
            PositionPanel(); Show(); Activate();
        }
        finally { openingPanel = false; }
    }
    private void PositionPanel()
    {
        var screen = Forms.Screen.FromPoint(Forms.Cursor.Position);
        var area = screen.WorkingArea;
        var handle = new System.Windows.Interop.WindowInteropHelper(this).Handle;
        double scale = GetDpiForWindow(handle) / 96.0;
        int width = (int)Math.Ceiling(Width * scale), height = (int)Math.Ceiling(Height * scale);
        int gap = (int)Math.Ceiling(12 * scale);
        // Desktop origins are physical pixels, even when neighboring monitors use different DPI.
        _ = SetWindowPos(handle, IntPtr.Zero, Math.Max(area.Left, area.Right - width - gap),
            Math.Max(area.Top, area.Bottom - height - gap), width, height, 0x0014);
    }
    private void Quit()
    {
        quitting = true; clipboard.Dispose(); discovery?.Dispose(); network?.Dispose(); tray.Dispose();
        Application.Current.Shutdown();
    }
    private void OpenSettings(object sender, RoutedEventArgs e)
    {
        ShowDetail("settings", "Settings");
        var panel = DetailContent;
        void Label(string text) => panel.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap });
        var lan = new CheckBox { Content = "Trusted LAN · no pairing key", IsChecked = settings.TrustedLAN, Margin = new Thickness(0, 0, 0, 8) }; panel.Children.Add(lan);
        Label("Unencrypted. Anyone on this local network can read or send items.");
        var pairing = new StackPanel { Margin = new Thickness(0, 12, 0, 0) }; panel.Children.Add(pairing);
        pairing.Children.Add(new TextBlock { Text = "Pairing code" });
        var code = new PasswordBox { Password = settings.PairingCode, MaxLength = 1024, Margin = new Thickness(0, 6, 0, 8) }; pairing.Children.Add(code);
        var copy = new Button { Content = "Copy code", Margin = new Thickness(0, 0, 0, 16) }; copy.Click += (_, _) => clipboard.CopySecret(settings.PairingCode); pairing.Children.Add(copy);
        void UpdatePairing() => pairing.Visibility = lan.IsChecked == true ? Visibility.Collapsed : Visibility.Visible;
        lan.Checked += (_, _) => UpdatePairing(); lan.Unchecked += (_, _) => UpdatePairing(); UpdatePairing();
        Label("Device name"); var name = new TextBox { Text = settings.DeviceName, MaxLength = 100, Margin = new Thickness(0, 6, 0, 16) }; panel.Children.Add(name);
        Label("Peer addresses (optional)");
        var hosts = new TextBox { Text = string.Join("\n", settings.Hosts), AcceptsReturn = true, Height = 62, Margin = new Thickness(0, 6, 0, 16) }; panel.Children.Add(hosts);
        var startup = new CheckBox { Content = "Launch at sign-in", IsChecked = StartupEnabled(), Margin = new Thickness(0, 0, 0, 16) }; panel.Children.Add(startup);
        var status = new TextBlock { TextWrapping = TextWrapping.Wrap };
        status.SetResourceReference(TextBlock.ForegroundProperty, "SystemFillColorCriticalBrush"); panel.Children.Add(status);
        var save = new Button { Content = "Save", Margin = new Thickness(0, 8, 0, 8) };
        save.Click += (_, _) =>
        {
            string secret = code.Password.Trim();
            if (secret.Length < 20) { status.Text = "Pairing codes must contain at least 20 characters."; return; }
            settings.TrustedLAN = lan.IsChecked == true;
            settings.PairingCode = secret; settings.DeviceName = string.IsNullOrWhiteSpace(name.Text) ? Environment.MachineName : name.Text.Trim();
            settings.Hosts = hosts.Text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Distinct().Take(32).ToArray();
            try { SetStartup(startup.IsChecked == true); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.SecurityException) { status.Text = "Could not update launch at sign-in."; return; }
            Persist(); StartNetwork(); Render(); GoBack(this, new RoutedEventArgs());
        };
        panel.Children.Add(save);
        var clear = new Button { Content = "Clear history on connected devices" };
        clear.Click += async (_, _) =>
        {
            confirming = true;
            try
            {
                if (MessageBox.Show(this, "Clear clipboard history on this computer and every connected device? Downloaded files are kept.", "Clear history", MessageBoxButton.OKCancel) != MessageBoxResult.OK) return;
            }
            finally { confirming = false; }
            history.Clear(); Persist(); Render(); if (network is not null) await network.Broadcast(network.NewMessage("history_clear"));
        };
        panel.Children.Add(clear);
    }
    private void ShowDetail(string name, string title)
    {
        page = name; PageTitle.Text = title;
        HomePage.Visibility = HomeFooter.Visibility = Visibility.Collapsed;
        DevicesFooter.Visibility = name == "devices" ? Visibility.Visible : Visibility.Collapsed;
        BackButton.Visibility = DetailPage.Visibility = Visibility.Visible;
        DetailContent.Children.Clear(); deviceLayout = ""; DetailPage.ScrollToTop();
        OpenPanel(); BackButton.Focus();
    }
    private void GoBack(object sender, RoutedEventArgs e)
    {
        page = "home"; PageTitle.Text = "OmaSend";
        HomePage.Visibility = HomeFooter.Visibility = Visibility.Visible;
        DevicesFooter.Visibility = Visibility.Collapsed;
        BackButton.Visibility = DetailPage.Visibility = Visibility.Collapsed;
        DetailContent.Children.Clear(); AutoButton.Focus();
    }
    private void OpenDevices(object sender, RoutedEventArgs e)
    {
        ShowDetail("devices", "Devices"); RenderDevices();
    }
    private void RenderDevices()
    {
        var peers = network?.Peers ?? [];
        var nearby = discovery?.Candidates.Where(c => !peers.Any(p => p.Id == c.Id)).ToArray() ?? [];
        string layout = string.Join("|", peers.Select(p => p.Id + p.Name + p.Via).Order()) + "\n" +
            string.Join("|", nearby.Select(c => c.Id + c.Name).Order());
        if (deviceLayout == layout) return;
        deviceLayout = layout;
        DetailContent.Children.Clear();
        void Device(string name, string status)
        {
            var row = new Grid { Margin = new Thickness(0, 12, 0, 12) };
            row.ColumnDefinitions.Add(new() { Width = new GridLength(36) }); row.ColumnDefinitions.Add(new());
            row.Children.Add(new TextBlock { Text = "\uE770", FontFamily = new FontFamily("Segoe Fluent Icons"), FontSize = 20, VerticalAlignment = VerticalAlignment.Center });
            var labels = new StackPanel();
            labels.Children.Add(new TextBlock { Text = name, TextWrapping = TextWrapping.Wrap });
            var detail = new TextBlock { Text = status, FontSize = 12, Margin = new Thickness(0, 4, 0, 0) };
            detail.SetResourceReference(TextBlock.ForegroundProperty, "TextFillColorSecondaryBrush"); labels.Children.Add(detail);
            Grid.SetColumn(labels, 1); row.Children.Add(labels); DetailContent.Children.Add(row);
        }
        foreach (var peer in peers) Device(peer.Name, "Connected \u00B7 " + peer.Via);
        foreach (var candidate in nearby) Device(candidate.Name, "Not paired");
        if (peers.Length + nearby.Length == 0) Device("Looking for devices", "No devices found");
    }
    private static bool StartupEnabled()
    {
        using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        return key?.GetValue("OmaSend") is string;
    }
    [System.Runtime.InteropServices.DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr window);
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    private static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    private static void SetStartup(bool enabled)
    {
        using var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        if (enabled) key.SetValue("OmaSend", $"\"{Environment.ProcessPath}\" --background"); else key.DeleteValue("OmaSend", false);
    }
}
