using OmaSend;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Threading;

internal static class SettingsChecks
{
    public static void Run()
    {
        string root = Path.Combine(Path.GetTempPath(), "omasend-settings-test-" + Guid.NewGuid());
        Environment.SetEnvironmentVariable("OMASEND_NO_DISCOVERY", "1");
        using var port = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
        port.Start();
        Environment.SetEnvironmentVariable("OMASEND_PORT", ((System.Net.IPEndPoint)port.LocalEndpoint).Port.ToString());
        port.Stop();
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var xaml = System.Xml.Linq.XDocument.Load(Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../OmaSend/App.xaml")));
        System.Xml.Linq.XNamespace ns = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
        var resources = new System.Xml.Linq.XElement(ns + "ResourceDictionary", xaml.Root!.Element(ns + "Application.Resources")!.Elements());
        resources.Add(new System.Xml.Linq.XAttribute(System.Xml.Linq.XNamespace.Xmlns + "x", "http://schemas.microsoft.com/winfx/2006/xaml"));
        app.Resources = (ResourceDictionary)System.Windows.Markup.XamlReader.Parse(resources.ToString());
        var window = new MainWindow(root);
        void Invoke(string method) => typeof(MainWindow).GetMethod(method, BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(window, [window, new RoutedEventArgs()]);
        try
        {
            Invoke("OpenSettings");
            var panel = (StackPanel)window.FindName("DetailContent");
            if (panel.Children.OfType<Button>().Any(b => Equals(b.Content, "Save"))) throw new Exception("Save button still present.");
            var lan = panel.Children.OfType<CheckBox>().First();
            lan.IsChecked = true; lan.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
            var store = new SettingsStore(root);
            if (!store.Load().TrustedLAN) throw new Exception("Switch did not save immediately.");
            var name = panel.Children.OfType<TextBox>().First();
            name.Text = "Auto saved Windows";
            var frame = new DispatcherFrame();
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(900) };
            timer.Tick += (_, _) => { timer.Stop(); frame.Continue = false; };
            timer.Start(); Dispatcher.PushFrame(frame);
            if (store.Load().DeviceName != name.Text) throw new Exception("Text did not save after debounce.");
            var code = panel.Children.OfType<StackPanel>().SelectMany(p => p.Children.OfType<PasswordBox>()).Single();
            string oldCode = store.Load().PairingCode;
            code.Password = "short";
            code.RaiseEvent(new RoutedEventArgs(FrameworkElement.UnloadedEvent));
            if (store.Load().PairingCode != oldCode) throw new Exception("Invalid partial key replaced saved key.");
            Console.WriteLine("PASS immediate switch save, debounced text persistence, no Save button, invalid key retained");
        }
        finally
        {
            typeof(MainWindow).GetMethod("Quit", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(window, null);
            Directory.Delete(root, true);
        }
    }
}
