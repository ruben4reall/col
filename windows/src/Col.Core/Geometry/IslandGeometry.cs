namespace Col.Core;

public enum IslandState
{
    /// <summary>At rest: a small pill, or nothing at all when the island only shows when something happens.</summary>
    Collapsed,
    /// <summary>The pointer rests on the island: it swells slightly to say it is there.</summary>
    Peek,
    /// <summary>Open, showing its content.</summary>
    Expanded,
}

/// <summary>How big the island is, closed and open.</summary>
public enum IslandSize
{
    Compact,
    Standard,
    Large,
}

/// <summary>
/// How far the closed island reaches on each side of its middle to show a live activity: the artwork on the left and
/// the equalizer on the right, say.
/// </summary>
public readonly record struct Wings(double Leading, double Trailing)
{
    public static readonly Wings None = new(0, 0);

    public Wings(double both) : this(both, both) { }

    public bool IsEmpty => Leading <= 0 && Trailing <= 0;

    /// <summary>Each side kept between zero and the widest a wing may grow.</summary>
    public Wings Clamped(double maximum) =>
        new(Math.Clamp(Leading, 0, maximum), Math.Clamp(Trailing, 0, maximum));
}

/// <summary>A rectangle in device-independent pixels, top-left origin.</summary>
public readonly record struct Box(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
    public double CenterX => X + Width / 2;
}

/// <summary>
/// The island's outline: a capsule floating below the top edge of the screen, rounded on all four corners, like the
/// iPhone's Dynamic Island. Windows has no notch, so the island never hangs from the edge.
/// </summary>
public readonly record struct IslandShape(double Width, double Height, double CornerRadius, double Opacity = 1);

/// <summary>
/// Every size the island takes on one screen. The window is the canvas: the largest area the island ever covers, with
/// room for its shadow. It never moves or resizes while the island animates; the transparent pixels around the island
/// let clicks through to the windows below.
/// </summary>
public sealed class IslandLayout
{
    /// <summary>Distance between the top edge of the screen and the island.</summary>
    public const double Gap = 8;
    /// <summary>Widest a wing of the closed island may grow, so a long title never covers half the screen.</summary>
    public const double MaximumWing = 132;
    /// <summary>Widest the middle of the closed island grows, for the line of a song being sung.</summary>
    public const double MaximumMiddle = 300;
    /// <summary>Room around the open island for its shadow.</summary>
    public const double ShadowMargin = 28;
    /// <summary>How much the pill swells when the pointer rests on it.</summary>
    public const double PeekGrowth = 16;

    public IslandSize Size { get; }

    public IslandLayout(IslandSize size = IslandSize.Standard) => Size = size;

    /// <summary>The pill at rest.</summary>
    public (double Width, double Height) Rest => Size switch
    {
        IslandSize.Compact => (112, 28),
        IslandSize.Large => (136, 36),
        _ => (124, 32),
    };

    /// <summary>The open island. Standard is 480 by 200, as on the Mac scaled for a desktop.</summary>
    public (double Width, double Height) Open => Size switch
    {
        IslandSize.Compact => (440, 184),
        IslandSize.Large => (540, 224),
        _ => (480, 200),
    };

    public double OpenCornerRadius => Size switch
    {
        IslandSize.Compact => 30,
        IslandSize.Large => 34,
        _ => 32,
    };

    /// <summary>
    /// The outline for a state. <paramref name="wings"/> widens the closed island on both sides to show a live
    /// activity, <paramref name="middle"/> widens its middle for a line of text.
    /// </summary>
    public IslandShape Shape(IslandState state, Wings wings = default, double middle = 0)
    {
        var (restWidth, restHeight) = Rest;
        wings = wings.Clamped(MaximumWing);
        var body = Math.Max(restWidth, Math.Min(middle, MaximumMiddle));
        switch (state)
        {
            case IslandState.Expanded:
                var (openWidth, openHeight) = Open;
                return new IslandShape(openWidth, openHeight, OpenCornerRadius);
            case IslandState.Peek:
                var height = restHeight + 4;
                return new IslandShape(body + wings.Leading + wings.Trailing + PeekGrowth, height, height / 2);
            default:
                return new IslandShape(body + wings.Leading + wings.Trailing, restHeight, restHeight / 2);
        }
    }

    /// <summary>
    /// What the island looks like for a state, whether or not it shows at rest. Closed with nothing to show, an island
    /// that only appears when something happens shrinks into a smaller, transparent pill, which is where it grows from
    /// when it comes out.
    /// </summary>
    public IslandShape Target(IslandState state, Wings wings, double middle, bool visibleAtRest, bool hasActivity)
    {
        var shape = Shape(state, wings, middle);
        if (state != IslandState.Collapsed || hasActivity || visibleAtRest) return shape;
        var (restWidth, restHeight) = Rest;
        var hidden = restHeight * 0.5;
        return new IslandShape(restWidth * 0.6, hidden, hidden / 2, Opacity: 0);
    }

    /// <summary>Size of the window: the open island and its shadow, or the widest closed island, whichever is wider.</summary>
    public (double Width, double Height) Canvas
    {
        get
        {
            var open = Shape(IslandState.Expanded);
            var widest = Shape(IslandState.Peek, new Wings(MaximumWing), MaximumMiddle);
            return (Math.Max(open.Width, widest.Width) + ShadowMargin * 2, Gap + open.Height + ShadowMargin);
        }
    }

    /// <summary>Bounding box of a shape in the canvas: centred, <see cref="Gap"/> below the top.</summary>
    public Box Frame(IslandShape shape) => new((Canvas.Width - shape.Width) / 2, Gap, shape.Width, shape.Height);

    /// <summary>
    /// The row of pixels along the top edge of a monitor where a resting pointer wakes the island, in physical pixels:
    /// one pixel high and as wide as the pill above which it sits. It is watched, never covered: no window lies there,
    /// so a click on it goes to the window below, a maximised browser's tabs say.
    /// </summary>
    public EdgeZone WakeZone((int Left, int Top, int Right, int Bottom) monitor, double scale)
    {
        var width = Math.Max(1, (int)Math.Round(Rest.Width * scale));
        var left = monitor.Left + (monitor.Right - monitor.Left - width) / 2;
        return new EdgeZone(left, left + width, monitor.Top);
    }

    /// <summary>
    /// Where the window goes on a monitor, in physical pixels: centred at the top of the monitor's full area (not the
    /// work area, which can start below a taskbar placed at the top).
    /// </summary>
    public static (int X, int Y, int Width, int Height) Placement(
        (int Left, int Top, int Right, int Bottom) monitor, double scale, (double Width, double Height) canvas)
    {
        var width = (int)Math.Ceiling(canvas.Width * scale);
        var height = (int)Math.Ceiling(canvas.Height * scale);
        var x = monitor.Left + (monitor.Right - monitor.Left - width) / 2;
        return (x, monitor.Top, width, height);
    }
}

/// <summary>The pixels at the top edge of a monitor that wake the island, in physical pixels: [Left, Right) on row Top.</summary>
public sealed record EdgeZone(int Left, int Right, int Top)
{
    /// <summary>Whether the pointer rests in the zone: on the monitor's top row, within the pill's width, and with no
    /// button held (dragging a window to the top does not wake the island).</summary>
    public bool Contains(int x, int y, bool buttonHeld) => !buttonHeld && y == Top && x >= Left && x < Right;
}

/// <summary>
/// Where the pointer is for the island: on the top edge's wake zone, or on the island itself. Between the two lie a few
/// pixels that belong to the windows below; crossing them is not leaving, so a leave only counts once it has lasted a
/// moment (<see cref="LeaveGrace"/>).
/// </summary>
public sealed class PointerPresence
{
    public static readonly TimeSpan LeaveGrace = TimeSpan.FromMilliseconds(120);

    public bool AtEdge { get; private set; }
    public bool OverIsland { get; private set; }
    /// <summary>What the island's rules were last told.</summary>
    public bool Inside { get; private set; }
    public bool LeavePending { get; private set; }

    public enum Change { None, Entered, LeaveStarted, LeaveCancelled }

    public Change Update(bool? atEdge = null, bool? overIsland = null)
    {
        AtEdge = atEdge ?? AtEdge;
        OverIsland = overIsland ?? OverIsland;
        var here = AtEdge || OverIsland;
        if (here)
        {
            var cancelled = LeavePending;
            LeavePending = false;
            if (!Inside)
            {
                Inside = true;
                return Change.Entered;
            }
            return cancelled ? Change.LeaveCancelled : Change.None;
        }
        if (!Inside || LeavePending) return Change.None;
        LeavePending = true;
        return Change.LeaveStarted;
    }

    /// <summary>The grace has passed: true when the pointer has really left, and the island's rules are told.</summary>
    public bool LeaveGraceEnded()
    {
        if (!LeavePending) return false;
        LeavePending = false;
        if (AtEdge || OverIsland) return false;
        Inside = false;
        return true;
    }
}

/// <summary>Whether the island shows at all on a monitor, given what runs there.</summary>
public static class IslandPresence
{
    /// <summary>
    /// The island steps aside under a full-screen app (a video, a game, a presentation) unless something needs the
    /// user, such as an agent asking for permission.
    /// </summary>
    public static bool IsShown(bool fullScreenAppInFront, bool hasAlert) => !fullScreenAppInFront || hasAlert;
}
