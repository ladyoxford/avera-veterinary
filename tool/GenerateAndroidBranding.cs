using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

public static class GenerateAndroidBranding
{
    public static void Main()
    {
        using (var source = new Bitmap("assets/images/logo.png"))
        {
            source.MakeTransparent(Color.Black);
            SaveMark(source, "android/app/src/main/res/drawable-nodpi/avera_splash_icon.png", 432, 300, true);
            SaveMark(source, "android/app/src/main/res/drawable-nodpi/avera_icon_foreground.png", 432, 300, true);
            SaveMark(source, "android/app/src/main/res/mipmap-mdpi/ic_launcher.png", 48, 35, false);
            SaveMark(source, "android/app/src/main/res/mipmap-hdpi/ic_launcher.png", 72, 52, false);
            SaveMark(source, "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png", 96, 69, false);
            SaveMark(source, "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png", 144, 104, false);
            SaveMark(source, "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", 192, 138, false);
        }
    }

    private static void SaveMark(Bitmap source, string path, int canvasSize, int markSize, bool transparentBackground)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        using (var output = new Bitmap(canvasSize, canvasSize, PixelFormat.Format32bppArgb))
        using (var graphics = Graphics.FromImage(output))
        {
            graphics.Clear(transparentBackground ? Color.Transparent : Color.Black);
            graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            var offset = (canvasSize - markSize) / 2;
            graphics.DrawImage(source, new Rectangle(offset, offset, markSize, markSize));
            output.Save(path, ImageFormat.Png);
        }
    }
}
