using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using Col.Core;

namespace Col.Island;

/// <summary>
/// The pieces of the closed island, one per kind of item. Each knows its own width, from which the island's wings are
/// sized. The few that move (the equalizer, the spinner, a logo that hops) run their animations at a low frame rate,
/// and only while they are on screen.
/// </summary>
internal static class CompactViews
{
    public static readonly SolidColorBrush Island = Glyphs.Brush(0x05, 0x08, 0x0A);
    private static readonly SolidColorBrush Track = Glyphs.Brush(255, 255, 255, 0x40);
    private static readonly FontFamily Font = new("Segoe UI Variable Text, Segoe UI");

    /// <summary>Room around an item inside its wing.</summary>
    public const double WingPadding = 10;

    public static double Width(CompactItem item) => item.Kind switch
    {
        CompactKind.Glyph => 16,
        CompactKind.Artwork => 22,
        CompactKind.Equalizer => 18,
        CompactKind.Ring => 16,
        CompactKind.Level => 52,
        CompactKind.Battery => 25,
        CompactKind.Spinner => 16,
        CompactKind.AgentLogo => 20,
        CompactKind.Dot => 8,
        CompactKind.Text or CompactKind.Countdown => Math.Min(MeasureText(item.Text ?? ""), 96),
        _ => 16,
    };

    public static double MeasureText(string text, double size = 13, FontWeight? weight = null)
    {
        var formatted = new FormattedText(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface(Font, FontStyles.Normal, weight ?? FontWeights.SemiBold, FontStretches.Normal), size, Brushes.White, 1.0);
        return Math.Ceiling(formatted.WidthIncludingTrailingWhitespace);
    }

    public static FrameworkElement Make(CompactItem item, ImageSource? artwork, double pixelsPerDip)
    {
        var tint = Glyphs.Brush(item.Tint);
        FrameworkElement view = item.Kind switch
        {
            CompactKind.Glyph => Glyphs.Make(item.Glyph ?? "", tint, 16, Island),
            CompactKind.Artwork => Artwork(artwork, 22, 6),
            CompactKind.Equalizer => Equalizer(tint, item.Active),
            CompactKind.Text => Label(item.Text ?? "", tint),
            CompactKind.Countdown => Label(item.Text ?? "", tint, tabular: true),
            CompactKind.Ring => Ring(item.Value, tint),
            CompactKind.Level => Level(item.Value, item.Active),
            CompactKind.Battery => Battery(item.Value, item.Active),
            CompactKind.Spinner => Spinner(tint),
            CompactKind.AgentLogo => AgentLogo(item.Agent, 20, item.Attention),
            CompactKind.Dot => new Ellipse { Width = 8, Height = 8, Fill = tint },
            _ => new Border(),
        };
        view.VerticalAlignment = VerticalAlignment.Center;
        return view;
    }

    public static FrameworkElement Label(string text, Brush brush, bool tabular = false, double size = 13)
    {
        var block = new TextBlock
        {
            Text = text, Foreground = brush, FontSize = size, FontWeight = FontWeights.SemiBold, FontFamily = Font,
            TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 96,
        };
        if (tabular) System.Windows.Documents.Typography.SetNumeralAlignment(block, FontNumeralAlignment.Tabular);
        return block;
    }

    /// <summary>The cover of the track, or a note on grey when it has none.</summary>
    public static FrameworkElement Artwork(ImageSource? image, double size, double radius)
    {
        var border = new Border { Width = size, Height = size, CornerRadius = new CornerRadius(radius) };
        if (image is not null)
        {
            border.Background = new ImageBrush(image) { Stretch = Stretch.UniformToFill };
        }
        else
        {
            border.Background = Glyphs.Brush(0x2C, 0x2C, 0x2E);
            border.Child = Glyphs.Make("music", Glyphs.Brush(255, 255, 255, 0x99), size * 0.5);
        }
        return border;
    }

    /// <summary>Four bars that dance while the track plays, and rest, low, while it is paused.</summary>
    private static FrameworkElement Equalizer(Brush brush, bool playing)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Height = 16, Width = 18 };
        double[] periods = [0.42, 0.55, 0.37, 0.61];
        double[] rests = [0.35, 0.6, 0.45, 0.3];
        for (var index = 0; index < 4; index++)
        {
            var scale = new ScaleTransform(1, rests[index]);
            var bar = new Rectangle
            {
                Width = 3, Height = 16, RadiusX = 1.5, RadiusY = 1.5, Fill = brush,
                Margin = new Thickness(index == 0 ? 0 : 2, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center,
                RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = scale,
            };
            panel.Children.Add(bar);
            if (!playing) continue;
            var dance = new DoubleAnimation(0.25, 1, TimeSpan.FromSeconds(periods[index]))
            {
                AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever,
                EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut },
                BeginTime = TimeSpan.FromSeconds(index * 0.11),
            };
            // A low frame rate: the bars read as dancing, and the island costs little while music plays.
            Timeline.SetDesiredFrameRate(dance, 24);
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, dance);
        }
        return panel;
    }

    /// <summary>A ring that fills with the progress.</summary>
    public static FrameworkElement Ring(double progress, Brush brush, double size = 16, double thickness = 2.2)
    {
        var grid = new Grid { Width = size, Height = size };
        grid.Children.Add(new Ellipse { Stroke = Track, StrokeThickness = thickness });
        var radius = (size - thickness) / 2;
        var center = size / 2;
        var angle = Math.Clamp(progress, 0, 0.9999) * 2 * Math.PI;
        if (progress > 0)
        {
            var end = new Point(center + radius * Math.Sin(angle), center - radius * Math.Cos(angle));
            var figure = new PathFigure { StartPoint = new Point(center, center - radius), IsClosed = false };
            figure.Segments.Add(new ArcSegment(end, new Size(radius, radius), 0, angle > Math.PI, SweepDirection.Clockwise, true));
            grid.Children.Add(new Path
            {
                Data = new PathGeometry([figure]), Stroke = brush, StrokeThickness = thickness,
                StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
            });
        }
        return grid;
    }

    /// <summary>The volume: a gauge, grey when the sound is muted.</summary>
    private static FrameworkElement Level(double value, bool on)
    {
        var grid = new Grid { Width = 52, Height = 5 };
        grid.Children.Add(new Border { Background = Track, CornerRadius = new CornerRadius(2.5) });
        grid.Children.Add(new Border
        {
            Background = on ? Brushes.White : Glyphs.Brush(255, 255, 255, 0x66), CornerRadius = new CornerRadius(2.5),
            HorizontalAlignment = HorizontalAlignment.Left, Width = Math.Max(5, 52 * Math.Clamp(value, 0, 1)),
        });
        return grid;
    }

    /// <summary>A battery, filled to its charge: green while charging, red when low.</summary>
    public static FrameworkElement Battery(double level, bool charging)
    {
        var fill = charging ? Glyphs.Brush(Rgba.Green) : level <= 0.2 ? Glyphs.Brush(Rgba.Red) : Brushes.White;
        var grid = new Grid { Width = 25, Height = 12 };
        grid.Children.Add(new Border
        {
            Width = 22, HorizontalAlignment = HorizontalAlignment.Left, CornerRadius = new CornerRadius(3.5),
            BorderBrush = Glyphs.Brush(255, 255, 255, 0x73), BorderThickness = new Thickness(1),
        });
        grid.Children.Add(new Border
        {
            Margin = new Thickness(2, 2, 0, 2), HorizontalAlignment = HorizontalAlignment.Left, CornerRadius = new CornerRadius(1.75),
            Width = Math.Max(2, 18 * Math.Clamp(level, 0, 1)), Background = fill,
        });
        grid.Children.Add(new Border
        {
            Width = 2, Height = 4, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 0, 0.5, 0),
            CornerRadius = new CornerRadius(0, 1, 1, 0), Background = Glyphs.Brush(255, 255, 255, 0x73),
        });
        return grid;
    }

    /// <summary>A short arc that turns while an agent works.</summary>
    private static FrameworkElement Spinner(Brush brush)
    {
        var rotation = new RotateTransform(0, 8, 8);
        var figure = new PathFigure { StartPoint = new Point(8, 1.6), IsClosed = false };
        figure.Segments.Add(new ArcSegment(new Point(14.4, 8), new Size(6.4, 6.4), 0, false, SweepDirection.Clockwise, true));
        var grid = new Grid { Width = 16, Height = 16 };
        grid.Children.Add(new Ellipse { Stroke = Track, StrokeThickness = 2, Margin = new Thickness(0.6) });
        grid.Children.Add(new Path
        {
            Data = new PathGeometry([figure]), Stroke = brush, StrokeThickness = 2.2, StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round, RenderTransform = rotation,
        });
        var turn = new DoubleAnimation(0, 360, TimeSpan.FromSeconds(0.9)) { RepeatBehavior = RepeatBehavior.Forever };
        Timeline.SetDesiredFrameRate(turn, 30);
        rotation.BeginAnimation(RotateTransform.AngleProperty, turn);
        return grid;
    }

    private static readonly Dictionary<string, BitmapImage> Marks = new();

    /// <summary>The logo of the agent behind a session: its mark, or its initial on its colour.</summary>
    public static FrameworkElement AgentLogo(string? agent, double size, DateTimeOffset? attention = null)
    {
        var known = CodingAgents.Named(agent);
        FrameworkElement view;
        if (known is { } coding && Mark(coding.Mark()) is { } mark)
        {
            view = new Border
            {
                Width = size, Height = size, CornerRadius = new CornerRadius(size * 0.26),
                Background = new ImageBrush(mark) { Stretch = Stretch.UniformToFill },
            };
        }
        else
        {
            var initial = string.IsNullOrEmpty(agent) ? "?" : agent[..1].ToUpperInvariant();
            view = new Border
            {
                Width = size, Height = size, CornerRadius = new CornerRadius(size * 0.26), Background = Glyphs.Brush(Rgba.Blue),
                Child = new TextBlock
                {
                    Text = initial, Foreground = Brushes.White, FontSize = size * 0.55, FontWeight = FontWeights.Bold, FontFamily = Font,
                    HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
                },
            };
        }
        // An agent that just began to wait hops a few times, as an icon does in the Dock, then rests.
        if (attention is { } since && DateTimeOffset.Now - since < TimeSpan.FromSeconds(2) && Services.Motion.Enabled)
        {
            var hop = new TranslateTransform();
            view.RenderTransform = hop;
            var jump = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromSeconds(0.5), RepeatBehavior = new RepeatBehavior(3) };
            jump.KeyFrames.Add(new EasingDoubleKeyFrame(0, KeyTime.FromPercent(0)));
            jump.KeyFrames.Add(new EasingDoubleKeyFrame(-4, KeyTime.FromPercent(0.4), new QuadraticEase { EasingMode = EasingMode.EaseOut }));
            jump.KeyFrames.Add(new EasingDoubleKeyFrame(0, KeyTime.FromPercent(0.8), new QuadraticEase { EasingMode = EasingMode.EaseIn }));
            jump.KeyFrames.Add(new EasingDoubleKeyFrame(0, KeyTime.FromPercent(1)));
            hop.BeginAnimation(TranslateTransform.YProperty, jump);
        }
        return view;
    }

    public static BitmapImage? Mark(string name)
    {
        if (Marks.TryGetValue(name, out var cached)) return cached;
        try
        {
            var image = new BitmapImage();
            image.BeginInit();
            image.UriSource = new Uri($"pack://application:,,,/Assets/Marks/mark-{name}.png");
            image.DecodePixelWidth = 64;
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.EndInit();
            image.Freeze();
            Marks[name] = image;
            return image;
        }
        catch (Exception)
        {
            return null;
        }
    }
}
