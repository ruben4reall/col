using System.IO;
using System.Media;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Col.Core;

namespace Col.Island;

/// <summary>
/// The intro Col plays as it opens, the Mac's score (IntroScore): light runs around the pill, the island swells with
/// Col's mark on the left and four bars that ring with the bells of a rising chime on the right, each bell sends a wave
/// out of it, then it settles back. It is drawn in the island's own window, frame by frame for its two and a half
/// seconds; then nothing of it is left, and nothing runs.
/// </summary>
internal partial class IslandWindow
{
    /// <summary>The width of each wing while the island swells: an item's own, as for a song's artwork.</summary>
    private const double IntroWing = 36;
    private IntroLayer? _introBack;
    private IntroLayer? _introFront;
    private double _introStart = -1;
    private bool _introSwelled;
    private bool _introTucked;
    private SoundPlayer? _chime;

    /// <summary>Seconds since the intro began, or a negative number when none plays.</summary>
    internal double IntroTime => _introStart < 0 ? -1 : Now - _introStart;

    /// <summary>The pill at rest and swollen, for the intro's drawing: its centre, and both sizes.</summary>
    internal (Point Center, Size Resting, Size Swollen) IntroGeometry
    {
        get
        {
            var (width, height) = _layout.Rest;
            var center = new Point(ActualWidth / 2, IslandLayout.Gap + height / 2);
            return (center, new Size(width, height), new Size(width + 2 * IntroWing, height));
        }
    }

    /// <summary>The intro holds the closed island: activities wait until it settles back.</summary>
    private bool IntroHoldsIsland => _introStart >= 0 && _introSwelled && !_introTucked;

    /// <summary>Plays the intro, with its chime unless <paramref name="sound"/> is false. Not while the island is open.</summary>
    public void PlayIntro(bool sound)
    {
        if (_introStart >= 0 || _machine.State == IslandState.Expanded) return;
        _introStart = Now;
        _introSwelled = _introTucked = false;
        var accent = TryFindResource("Win.Accent") is SolidColorBrush brush ? brush.Color : Color.FromRgb(0x60, 0xCD, 0xFF);
        _introBack = new IntroLayer(this, accent, back: true);
        _introFront = new IntroLayer(this, accent, back: false);
        Root.Children.Insert(0, _introBack);
        Root.Children.Add(_introFront);
        if (sound) PlayChime();
        StartRendering();
    }

    /// <summary>Ends the intro at once: the pointer came to the island, or something needs it.</summary>
    private void CutIntro()
    {
        if (_introStart < 0) return;
        _chime?.Stop();
        FinishIntro();
    }

    /// <summary>One frame of the intro: its moments come in turn, then it goes. True while it still plays.</summary>
    private bool IntroStep()
    {
        var time = IntroTime;
        if (time < 0) return false;
        if (!_introSwelled && time >= IntroScore.Swell)
        {
            _introSwelled = true;
            ShowIntroCompact();
        }
        if (!_introTucked && time >= IntroScore.Tuck) TuckIntro();
        if (time >= IntroScore.End)
        {
            FinishIntro();
            return false;
        }
        _introBack?.InvalidateVisual();
        _introFront?.InvalidateVisual();
        return true;
    }

    /// <summary>The island swells: Col's mark in the left wing, the bars in the right one.</summary>
    private void ShowIntroCompact()
    {
        var side = 18.0;
        var mark = new Image
        {
            Source = new BitmapImage(new Uri("pack://application:,,,/Assets/col-64.png")),
            Width = side,
            Height = side,
        };
        RenderOptions.SetBitmapScalingMode(mark, BitmapScalingMode.HighQuality);
        LeadingSlot.Content = mark;
        TrailingSlot.Content = new IntroBars(this, _introFront?.Accent ?? Colors.White) { Width = side, Height = side };
        LeadingSlot.Margin = new Thickness(CompactViews.WingPadding + 2, 0, 0, 0);
        TrailingSlot.Margin = new Thickness(0, 0, CompactViews.WingPadding + 2, 0);
        MiddleText.Text = "";
        var swollen = _layout.Target(IslandState.Collapsed, new Wings(IntroWing), 0, visibleAtRest: true, hasActivity: true);
        AnimateTo(swollen, IslandState.Collapsed);
    }

    /// <summary>The island settles back to what it shows now.</summary>
    private void TuckIntro()
    {
        _introTucked = true;
        _compactCleared = true;
        Update();
    }

    private void FinishIntro()
    {
        if (!_introTucked) TuckIntro();
        _introStart = -1;
        if (_introBack is not null) Root.Children.Remove(_introBack);
        if (_introFront is not null) Root.Children.Remove(_introFront);
        _introBack = _introFront = null;
        // The chime rings on a little after the picture; the player lets go once it has played.
        var chime = _chime;
        _chime = null;
        if (chime is not null)
        {
            var later = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            later.Tick += (_, _) =>
            {
                later.Stop();
                chime.Dispose();
            };
            later.Start();
        }
    }

    private void PlayChime()
    {
        try
        {
            var resource = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/intro.wav"));
            if (resource is null) return;
            using var stream = resource.Stream;
            var copy = new MemoryStream();
            stream.CopyTo(copy);
            copy.Position = 0;
            _chime = new SoundPlayer(copy);
            _chime.Load();
            _chime.Play();
        }
        catch (Exception error) when (error is IOException or InvalidOperationException or TimeoutException)
        {
            // No sound device, or none free: the intro plays without its chime.
            _chime = null;
        }
    }
}

/// <summary>
/// What the intro draws around the island: behind it a soft light and the waves, in front of it the line of light that
/// runs around the pill and the spark where its two ends meet.
/// </summary>
internal sealed class IntroLayer : FrameworkElement
{
    private readonly IslandWindow _island;
    private readonly bool _back;

    public IntroLayer(IslandWindow island, Color accent, bool back)
    {
        _island = island;
        _back = back;
        Accent = accent;
        IsHitTestVisible = false;
        Focusable = false;
    }

    public Color Accent { get; }

    protected override void OnRender(DrawingContext context)
    {
        var time = _island.IntroTime;
        if (time < 0) return;
        var (center, rest, swollen) = _island.IntroGeometry;
        if (_back) DrawBack(context, time, center, rest, swollen);
        else DrawFront(context, time, center, rest);
    }

    private static Color WithAlpha(Color color, double alpha) =>
        Color.FromArgb((byte)Math.Clamp(alpha * 255, 0, 255), color.R, color.G, color.B);

    private static Color Lighter(Color color, double amount) => Color.FromRgb(
        (byte)(color.R + (255 - color.R) * amount), (byte)(color.G + (255 - color.G) * amount), (byte)(color.B + (255 - color.B) * amount));

    private void DrawBack(DrawingContext context, double time, Point center, Size rest, Size swollen)
    {
        // The soft light under the island, swelling with the bells.
        var glow = Keyframes(time, [IntroScore.Swell + 0.05, 0.57, 0.70, 0.82, 0.92, 1.45, IntroScore.Tuck + 0.1], [0, 0.85, 0.55, 0.8, 0.85, 0.5, 0]);
        if (glow > 0.01)
        {
            var brush = new RadialGradientBrush(WithAlpha(Accent, 0.55 * glow), Colors.Transparent);
            context.DrawEllipse(brush, null, new Point(center.X, center.Y + 6), swollen.Width * 0.75, rest.Height * 1.9);
        }
        // A wave for each bell, leaving the island and growing out as it fades.
        var color = Lighter(Accent, 0.25);
        for (var index = 0; index < IntroScore.Bells.Length; index++)
        {
            if (IntroScore.WaveProgress(index, time) is not { } progress) continue;
            var eased = IntroScore.Ease(progress);
            var start = index == 0 ? rest : swollen;
            var width = start.Width + (swollen.Width - start.Width + 2 * IntroScore.WaveReachX) * eased;
            var height = start.Height + 2 * IntroScore.WaveReachY * eased;
            var opacity = 0.85 * IntroScore.Strengths[index] * IntroScore.WaveOpacity(progress);
            var pen = new Pen(new SolidColorBrush(WithAlpha(color, opacity)), 2.2 - 1.4 * eased);
            var box = new Rect(center.X - width / 2, center.Y - height / 2, width, height);
            context.DrawRoundedRectangle(null, pen, box, height / 2, height / 2);
        }
    }

    private void DrawFront(DrawingContext context, double time, Point center, Size rest)
    {
        // The line of light, from the top of the pill down both sides to the middle of its lower edge.
        if (time <= IntroScore.TraceEnd + 0.45)
        {
            var drawn = Math.Clamp((time - IntroScore.TraceStart) / (IntroScore.TraceEnd - IntroScore.TraceStart), 0, 1);
            // Gathering speed toward the meeting point.
            drawn = drawn * drawn * (1.6 - 0.6 * drawn);
            var fade = time <= IntroScore.TraceEnd ? 1 : Math.Max(0, 1 - (time - IntroScore.TraceEnd) / 0.45);
            if (drawn > 0 && fade > 0)
            {
                foreach (var side in new[] { -1.0, 1.0 })
                {
                    var (geometry, length) = HalfCapsule(center, rest, side);
                    var thickness = 1.6;
                    var pen = new Pen(new SolidColorBrush(WithAlpha(Colors.White, 0.95 * fade)), thickness)
                    {
                        StartLineCap = PenLineCap.Round,
                        EndLineCap = PenLineCap.Round,
                        DashCap = PenLineCap.Round,
                        DashStyle = new DashStyle([Math.Max(0.01, length * drawn / thickness), length * 2 / thickness], 0),
                    };
                    var halo = new Pen(new SolidColorBrush(WithAlpha(Accent, 0.45 * fade)), 5)
                    {
                        StartLineCap = PenLineCap.Round,
                        DashCap = PenLineCap.Round,
                        DashStyle = new DashStyle([Math.Max(0.01, length * drawn / 5), length * 2 / 5], 0),
                    };
                    context.DrawGeometry(null, halo, geometry);
                    context.DrawGeometry(null, pen, geometry);
                }
            }
        }
        // The spark where the two ends meet.
        var since = time - (IntroScore.TraceEnd - 0.02);
        if (since >= 0 && since <= 0.5)
        {
            var t = since / 0.5;
            var alpha = t < 0.18 ? t / 0.18 : 1 - (t - 0.18) / 0.82;
            var radius = 5 * (0.3 + 2.1 * (1 - Math.Pow(1 - t, 2)));
            var spark = new RadialGradientBrush(WithAlpha(Colors.White, alpha), WithAlpha(Accent, 0));
            context.DrawEllipse(spark, null, new Point(center.X, center.Y + rest.Height / 2), radius * 1.8, radius * 1.8);
        }
    }

    /// <summary>One half of the pill's outline, from the top middle around one end to the bottom middle, and its length.</summary>
    private static (Geometry Geometry, double Length) HalfCapsule(Point center, Size size, double side)
    {
        var radius = size.Height / 2;
        var straight = Math.Max(0, size.Width / 2 - radius);
        var top = center.Y - radius;
        var bottom = center.Y + radius;
        var end = center.X + side * straight;
        var figure = new PathFigure { StartPoint = new Point(center.X, top), IsClosed = false, IsFilled = false };
        figure.Segments.Add(new LineSegment(new Point(end, top), true));
        figure.Segments.Add(new ArcSegment(new Point(end, bottom), new Size(radius, radius), 0, false,
            side > 0 ? SweepDirection.Clockwise : SweepDirection.Counterclockwise, true));
        figure.Segments.Add(new LineSegment(new Point(center.X, bottom), true));
        var geometry = new PathGeometry([figure]);
        geometry.Freeze();
        return (geometry, straight * 2 + Math.PI * radius);
    }

    /// <summary>A value that moves straight between keyframes at the given times of the score.</summary>
    private static double Keyframes(double time, double[] times, double[] values)
    {
        if (time <= times[0]) return values[0];
        for (var index = 1; index < times.Length; index++)
        {
            if (time > times[index]) continue;
            var t = (time - times[index - 1]) / (times[index] - times[index - 1]);
            return values[index - 1] + (values[index] - values[index - 1]) * t;
        }
        return values[^1];
    }
}

/// <summary>The intro's four bars, ringing with the bells, in the right wing.</summary>
internal sealed class IntroBars : FrameworkElement
{
    private readonly IslandWindow _island;
    private readonly SolidColorBrush _brush;

    public IntroBars(IslandWindow island, Color accent)
    {
        _island = island;
        _brush = new SolidColorBrush(accent);
        _brush.Freeze();
        IsHitTestVisible = false;
        CompositionTarget.Rendering += OnFrame;
        Unloaded += (_, _) => CompositionTarget.Rendering -= OnFrame;
    }

    private void OnFrame(object? sender, EventArgs e)
    {
        if (_island.IntroTime < 0) CompositionTarget.Rendering -= OnFrame;
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext context)
    {
        var time = Math.Max(_island.IntroTime, 0);
        var gap = Width * 0.12;
        var bar = (Width - gap * 3) / 4;
        for (var index = 0; index < 4; index++)
        {
            var height = Math.Max(bar, Height * IntroScore.BarLevel(index, time));
            var box = new Rect(index * (bar + gap), (Height - height) / 2, bar, height);
            context.DrawRoundedRectangle(_brush, null, box, bar / 2, bar / 2);
        }
    }
}
