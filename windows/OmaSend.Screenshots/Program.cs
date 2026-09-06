using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using OmaSend;
using OmaSend.Core;

internal static class Program
{
 [STAThread]
 private static void Main(string[] args)
 {
  string output = Path.GetFullPath(args[0]);
  string root = Path.Combine(Path.GetTempPath(), "omasend-preview-" + Guid.NewGuid().ToString("N"));
  Environment.SetEnvironmentVariable("OMASEND_NO_DISCOVERY", "1");
  Environment.SetEnvironmentVariable("OMASEND_PORT", "54327");
  Environment.SetEnvironmentVariable("OMASEND_DOWNLOADS", Path.Combine(root, "downloads"));
  var settings = new Settings { DeviceName = "Windows PC", AutoCopy = true };
  settings.History = [
   new Message { Type = "clipboard", OriginId = "sample-mac", OriginName = "MacBook", ContentType = "text/plain", Text = "A shared clipboard for your computers." },
   new Message { Type = "clipboard", OriginId = "sample-linux", OriginName = "Linux", ContentType = "text/plain", Text = "https://github.com/Aayush9029/OmaSend" },
   new Message { Type = "clipboard", OriginId = settings.DeviceId, OriginName = settings.DeviceName, ContentType = "text/plain", Text = "Meeting notes\nReview the design and share the next draft." }
  ];
  new SettingsStore(root).Save(settings);
  var app = new App(); app.InitializeComponent();
  var window = new MainWindow(root) { ShowActivated = false };
  window.Show();
  var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
  timer.Tick += (_, _) =>
  {
   timer.Stop(); window.Show(); window.UpdateLayout();
   var bitmap = new RenderTargetBitmap((int)window.ActualWidth, (int)window.ActualHeight, 96, 96, PixelFormats.Pbgra32);
   var drawing = new DrawingVisual();
   using (var context = drawing.RenderOpen())
   {
    var bounds = new Rect(0, 0, window.ActualWidth, window.ActualHeight);
    context.DrawRectangle(window.Background, null, bounds);
    context.DrawRectangle(new VisualBrush((Visual)window.Content), null, bounds);
   }
   bitmap.Render(drawing);
   var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
   Directory.CreateDirectory(Path.GetDirectoryName(output)!);
   using (var stream = File.Create(output)) encoder.Save(stream);
   Console.WriteLine("Captured actual WPF window with sample history: " + output);
   Environment.Exit(0);
  };
  timer.Start(); Dispatcher.Run();
 }
}
