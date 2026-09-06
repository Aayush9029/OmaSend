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
  // Opt in to WPF's theme API only for this deterministic screenshot fixture.
#pragma warning disable WPF0001
  var app = new App(); app.InitializeComponent(); app.ThemeMode = ThemeMode.Dark;
  var window = new MainWindow(root) { ShowActivated = false, ThemeMode = ThemeMode.Dark };
#pragma warning restore WPF0001
  window.Show();
  var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
  timer.Tick += (_, _) =>
  {
   timer.Stop(); window.Show(); window.UpdateLayout();
   // Match the existing macOS and Linux README canvases without stretching the UI.
   const int width = 746, height = 1045;
   var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
   var drawing = new DrawingVisual();
   using (var context = drawing.RenderOpen())
   {
    var background = new LinearGradientBrush(Color.FromRgb(12, 16, 30), Color.FromRgb(28, 57, 88), new Point(0, 0), new Point(1, 1));
    context.DrawRectangle(background, null, new Rect(0, 0, width, height));
    double scale = 640 / window.ActualWidth;
    double left = (width - window.ActualWidth * scale) / 2;
    double top = (height - window.ActualHeight * scale) / 2;
    context.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(45, 0, 0, 0)), null,
     new Rect(left - 8, top + 10, window.ActualWidth * scale + 16, window.ActualHeight * scale + 8), 15, 15);
    context.PushTransform(new TranslateTransform(left, top));
    context.PushTransform(new ScaleTransform(scale, scale));
    var bounds = new Rect(0, 0, window.ActualWidth, window.ActualHeight);
    context.PushClip(new RectangleGeometry(bounds, 8, 8));
    context.DrawRectangle(window.Background, null, bounds);
    context.DrawRectangle(new VisualBrush((Visual)window.Content), null, bounds);
    context.Pop(); context.Pop(); context.Pop();
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
