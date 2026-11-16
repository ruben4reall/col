namespace Col.Core;

/// <summary>Something that happened to the island.</summary>
public enum IslandEvent
{
    PointerEntered,
    PointerExited,
    Pressed,
    /// <summary>Something needs the user, such as an agent asking for permission: the island opens by itself.</summary>
    Requested,
    Dismissed,
    /// <summary>The pointer has rested on the island, or on the strip at the top edge, long enough to make it peek.</summary>
    RestTimerFired,
    /// <summary>The pointer has rested on the peeking island long enough to open it.</summary>
    HoverTimerFired,
    /// <summary>The pointer left the open island and stayed away for the grace period.</summary>
    ExitTimerFired,
}

/// <summary>Work the machine asks its host to do. Timers live outside so the rules stay deterministic.</summary>
public enum IslandEffect
{
    StartRestTimer,
    CancelRestTimer,
    StartHoverTimer,
    CancelHoverTimer,
    StartExitTimer,
    CancelExitTimer,
}

/// <summary>
/// The rules that open and close the island.
/// <para>
/// A short rest on the island (or on the strip along the top edge) makes it peek; resting longer, or a click, opens
/// it. Once open it stays open while the pointer is over it, and closes shortly after the pointer leaves, so a pointer
/// that slips off the edge for an instant does not slam it shut. While a request waits for an answer, it stays open.
/// </para>
/// </summary>
public sealed class IslandMachine
{
    public IslandState State { get; private set; } = IslandState.Collapsed;
    public bool PointerInside { get; private set; }
    public bool OpensOnHover { get; set; } = true;
    /// <summary>Set while something waits for the user in the island: it does not close when the pointer leaves.</summary>
    public bool HeldOpen { get; private set; }

    /// <summary>The rest before the island peeks.</summary>
    public static readonly TimeSpan RestDelay = TimeSpan.FromMilliseconds(200);
    /// <summary>The rest on the peeking island before it opens by itself.</summary>
    public static readonly TimeSpan HoverDwell = TimeSpan.FromMilliseconds(450);
    /// <summary>Time the pointer may spend off the open island before it closes.</summary>
    public static readonly TimeSpan ExitGrace = TimeSpan.FromMilliseconds(320);

    public IReadOnlyList<IslandEffect> Handle(IslandEvent @event)
    {
        switch (@event)
        {
            case IslandEvent.PointerEntered:
                PointerInside = true;
                return State switch
                {
                    IslandState.Collapsed => [IslandEffect.StartRestTimer],
                    IslandState.Expanded => [IslandEffect.CancelExitTimer],
                    _ => [],
                };

            case IslandEvent.PointerExited:
                PointerInside = false;
                switch (State)
                {
                    case IslandState.Collapsed:
                        return [IslandEffect.CancelRestTimer];
                    case IslandState.Peek:
                        State = IslandState.Collapsed;
                        return [IslandEffect.CancelHoverTimer];
                    default:
                        return HeldOpen ? [] : [IslandEffect.StartExitTimer];
                }

            case IslandEvent.RestTimerFired:
                if (State != IslandState.Collapsed || !PointerInside) return [];
                State = IslandState.Peek;
                return OpensOnHover ? [IslandEffect.StartHoverTimer] : [];

            case IslandEvent.Pressed:
            case IslandEvent.Requested:
                if (State == IslandState.Expanded) return [IslandEffect.CancelExitTimer];
                State = IslandState.Expanded;
                return [IslandEffect.CancelRestTimer, IslandEffect.CancelHoverTimer];

            case IslandEvent.HoverTimerFired:
                if (State != IslandState.Peek || !PointerInside) return [];
                State = IslandState.Expanded;
                return [];

            case IslandEvent.ExitTimerFired:
                if (State != IslandState.Expanded || PointerInside || HeldOpen) return [];
                State = IslandState.Collapsed;
                return [];

            case IslandEvent.Dismissed:
                if (State == IslandState.Collapsed) return [];
                State = IslandState.Collapsed;
                return [IslandEffect.CancelRestTimer, IslandEffect.CancelHoverTimer, IslandEffect.CancelExitTimer];
        }
        return [];
    }

    /// <summary>Keeps the island open while a request waits, then lets it close as usual once answered.</summary>
    public IReadOnlyList<IslandEffect> Hold(bool held)
    {
        if (HeldOpen == held) return [];
        HeldOpen = held;
        if (!held && State == IslandState.Expanded && !PointerInside) return [IslandEffect.StartExitTimer];
        return held ? [IslandEffect.CancelExitTimer] : [];
    }
}
