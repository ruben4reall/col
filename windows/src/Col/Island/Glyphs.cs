using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using Col.Core;

namespace Col.Island;

/// <summary>
/// Col's own glyphs, drawn on a 16 by 16 grid: a filled part and a stroked part each. Vector shapes, so they stay sharp
/// at every scale and look the same on every version of Windows.
/// </summary>
internal static class Glyphs
{
    private static readonly Dictionary<string, (string? Fill, string? Stroke)> Shapes = new()
    {
        ["play"] = ("M4.5,2.6 C4.5,1.9 5.3,1.5 5.9,1.9 L13.2,7.1 C13.7,7.5 13.7,8.5 13.2,8.9 L5.9,14.1 C5.3,14.5 4.5,14.1 4.5,13.4 Z", null),
        ["pause"] = ("M3.5,2.5 H6.5 V13.5 H3.5 Z M9.5,2.5 H12.5 V13.5 H9.5 Z", null),
        ["next"] = ("M2,3 C2,2.4 2.7,2.1 3.1,2.5 L9.4,7.4 C9.8,7.7 9.8,8.3 9.4,8.6 L3.1,13.5 C2.7,13.9 2,13.6 2,13 Z M11.5,2.5 H13.5 V13.5 H11.5 Z", null),
        ["previous"] = ("M14,3 C14,2.4 13.3,2.1 12.9,2.5 L6.6,7.4 C6.2,7.7 6.2,8.3 6.6,8.6 L12.9,13.5 C13.3,13.9 14,13.6 14,13 Z M2.5,2.5 H4.5 V13.5 H2.5 Z", null),
        ["speaker"] = ("M1.5,6 H4.5 L8.5,2.5 V13.5 L4.5,10 H1.5 Z", "M10.8,5.6 C11.7,6.9 11.7,9.1 10.8,10.4 M12.6,3.8 C14.4,6.1 14.4,9.9 12.6,12.2"),
        ["speaker.mute"] = ("M1.5,6 H4.5 L8.5,2.5 V13.5 L4.5,10 H1.5 Z", "M10.5,6 L14.5,10 M14.5,6 L10.5,10"),
        ["timer"] = (null, "M8,4 A5.25,5.25 0 1 1 7.99,4 M8,6.5 V9.25 L9.75,10.5 M6.25,1.75 H9.75 M8,1.75 V4"),
        ["hand"] = (null, "M5.25,8.5 V3.75 A1,1 0 0 1 7.25,3.75 V7.5 M7.25,7.25 V2.75 A1,1 0 0 1 9.25,2.75 V7.25 M9.25,7.25 V3.75 A1,1 0 0 1 11.25,3.75 V8 M11.25,8 V6 A1,1 0 0 1 13.25,6 V10 C13.25,12.6 11.3,14.5 8.75,14.5 C6.9,14.5 5.8,13.6 4.9,12.3 L2.9,9.4 A1,1 0 0 1 4.5,8.2 L5.25,9.25"),
        ["check"] = ("M8,1 A7,7 0 1 1 7.99,1 Z", null),
        ["cup"] = ("M2.5,6 H11 V9.75 A3.25,3.25 0 0 1 7.75,13 H5.75 A3.25,3.25 0 0 1 2.5,9.75 Z", "M11,7 H12 A1.6,1.6 0 0 1 12,10.2 H11 M5,1.8 C4.4,2.6 5.6,3.4 5,4.2 M8,1.8 C7.4,2.6 8.6,3.4 8,4.2"),
        ["music"] = ("M5.5,10.75 A2.25,1.75 0 1 1 5.49,10.75 Z M13,8.75 A2.25,1.75 0 1 1 12.99,8.75 Z", "M7.75,12.5 V3.25 L15.25,1.75 V10.5"),
        ["bolt"] = ("M9.2,1 L3,9.2 H7.4 L6.6,15 L13,6.6 H8.6 Z", null),
        ["hammer"] = ("M6.2,2.2 L10.4,2.2 L13.4,5.2 L10.8,7.8 L8.6,5.6 L7.4,6.8 L5.8,5.2 Z", "M8,6.2 L2.4,11.8 A1.1,1.1 0 0 0 4,13.4 L9.6,7.8"),
        ["gear"] = (null, "M8,5.5 A2.5,2.5 0 1 1 7.99,5.5 M8,1.5 V3 M8,13 V14.5 M1.5,8 H3 M13,8 H14.5 M3.4,3.4 L4.5,4.5 M11.5,11.5 L12.6,12.6 M3.4,12.6 L4.5,11.5 M11.5,4.5 L12.6,3.4"),
        ["pin"] = (null, "M9.5,2 L14,6.5 M10.75,3.25 L7.5,6.5 L4.5,6.75 L9.25,11.5 L9.5,8.5 L12.75,5.25 M6.75,9.25 L2.5,13.5"),
        ["pinned"] = ("M10.75,3.25 L12.75,5.25 L9.5,8.5 L9.25,11.5 L4.5,6.75 L7.5,6.5 Z", "M9.5,2 L14,6.5 M6.75,9.25 L2.5,13.5"),
        ["copy"] = (null, "M5.5,5.5 H12.5 V13.5 H5.5 Z M3.5,10.5 V2.5 H10.5"),
        ["close"] = (null, "M4,4 L12,12 M12,4 L4,12"),
        ["terminal"] = (null, "M2,3 H14 V13 H2 Z M4.5,6 L6.5,8 L4.5,10 M8,10.5 H11.5"),
    };

    private static readonly Dictionary<string, Geometry> Cache = new();

    private static Geometry? Geometry(string? data)
    {
        if (data is null) return null;
        if (Cache.TryGetValue(data, out var cached)) return cached;
        var geometry = System.Windows.Media.Geometry.Parse(data);
        geometry.Freeze();
        Cache[data] = geometry;
        return geometry;
    }

    public static bool Has(string name) => Shapes.ContainsKey(name);

    /// <summary>A glyph at a size, in a colour. <paramref name="cutout"/> draws the check mark of "check" in another colour.</summary>
    public static FrameworkElement Make(string name, Brush brush, double size, Brush? cutout = null)
    {
        var canvas = new Canvas { Width = 16, Height = 16 };
        if (Shapes.TryGetValue(name, out var shape))
        {
            if (Geometry(shape.Fill) is { } fill) canvas.Children.Add(new Path { Data = fill, Fill = brush });
            if (Geometry(shape.Stroke) is { } stroke)
            {
                canvas.Children.Add(new Path
                {
                    Data = stroke, Stroke = brush, StrokeThickness = 1.5,
                    StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round,
                });
            }
            if (name == "check")
            {
                canvas.Children.Add(new Path
                {
                    Data = Geometry("M4.6,8.3 L6.9,10.6 L11.4,5.6"), Stroke = cutout ?? Brushes.Black, StrokeThickness = 1.7,
                    StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round,
                });
            }
        }
        return new Viewbox { Width = size, Height = size, Child = canvas, Stretch = Stretch.Uniform };
    }

    public static SolidColorBrush Brush(Rgba color)
    {
        var brush = new SolidColorBrush(Color.FromArgb(color.AlphaByte, color.RedByte, color.GreenByte, color.BlueByte));
        brush.Freeze();
        return brush;
    }

    public static SolidColorBrush Brush(byte r, byte g, byte b, byte a = 255)
    {
        var brush = new SolidColorBrush(Color.FromArgb(a, r, g, b));
        brush.Freeze();
        return brush;
    }
}
