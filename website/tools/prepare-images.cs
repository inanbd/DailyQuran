#:package System.Drawing.Common@10.0.0
#:property PublishAot=false

// Prepares the website's images from the app's own, so the site never keeps
// hand-made copies. Run from the repository root, on Windows:
//
//   dotnet run website/tools/prepare-images.cs
//
//  * The Play Store screenshots (1080 x 2160) as 600 x 1200 JPEGs: never shown wider
//    than about 300 pixels, so this is still sharp on a 2x screen, at a
//    fraction of the download.
//  * The 512px store icon at the sizes browsers and search results ask for.

using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

string screens = "fastlane/metadata/android/en-US/images/phoneScreenshots";
string icon = "fastlane/metadata/android/en-US/images/icon.png";
string output = "website/src/DailyQuran.Web/wwwroot/img";

if (!Directory.Exists(screens))
{
    Console.Error.WriteLine("Run this from the repository root.");
    return 1;
}

foreach (string file in Directory.GetFiles(screens, "*.png"))
{
    string target = Path.Combine(output, "screens", Path.ChangeExtension(Path.GetFileName(file), ".jpg"));
    Resize(file, target, 600, 1200);
}

foreach (int size in new[] { 96, 180, 192 })
{
    Resize(icon, Path.Combine(output, $"icon-{size}.png"), size, size);
}
File.Copy(icon, Path.Combine(output, "icon-512.png"), overwrite: true);
return 0;

static void Resize(string source, string target, int width, int height)
{
    bool jpeg = Path.GetExtension(target) == ".jpg";
    using var original = Image.FromFile(source);
    using var resized = new Bitmap(width, height, jpeg ? PixelFormat.Format24bppRgb : PixelFormat.Format32bppArgb);
    using (var graphics = Graphics.FromImage(resized))
    {
        graphics.CompositingQuality = CompositingQuality.HighQuality;
        graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
        graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
        graphics.SmoothingMode = SmoothingMode.HighQuality;
        using var attributes = new ImageAttributes();
        // Keeps the edges from blending with transparent pixels outside the image.
        attributes.SetWrapMode(WrapMode.TileFlipXY);
        graphics.DrawImage(original, new Rectangle(0, 0, width, height), 0, 0, original.Width, original.Height, GraphicsUnit.Pixel, attributes);
    }
    Directory.CreateDirectory(Path.GetDirectoryName(target)!);
    if (jpeg)
    {
        // High enough that the app's text stays crisp at twice the size it is shown.
        ImageCodecInfo codec = ImageCodecInfo.GetImageEncoders().First(c => c.FormatID == ImageFormat.Jpeg.Guid);
        using var quality = new EncoderParameters(1);
        quality.Param[0] = new EncoderParameter(Encoder.Quality, 88L);
        resized.Save(target, codec, quality);
    }
    else
    {
        resized.Save(target, ImageFormat.Png);
    }
    Console.WriteLine($"{target}  {width}x{height}  {new FileInfo(target).Length / 1024} KB");
}
