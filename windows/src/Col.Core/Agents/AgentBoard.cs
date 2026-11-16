using System.Globalization;

namespace Col.Core;

public enum AgentStateKind
{
    Idle,
    Working,
    /// <summary>Waiting for the user: a permission, or an answer.</summary>
    Waiting,
    Done,
}

public readonly record struct AgentState(AgentStateKind Kind, string? Detail = null)
{
    public static readonly AgentState Idle = new(AgentStateKind.Idle);
    public static readonly AgentState Done = new(AgentStateKind.Done);
    public static AgentState Working(string? detail) => new(AgentStateKind.Working, detail);
    public static AgentState Waiting(string? detail) => new(AgentStateKind.Waiting, detail);
}

/// <summary>One coding agent session, followed through its hooks.</summary>
public sealed record AgentSession(string Id, string Project, string? Agent, AgentState State, DateTimeOffset Since, DateTimeOffset Updated);

/// <summary>Every agent session and what each is doing.</summary>
public sealed class AgentBoard
{
    private readonly Dictionary<string, AgentSession> _sessions = new(StringComparer.Ordinal);

    public IReadOnlyDictionary<string, AgentSession> Sessions => _sessions;

    private static readonly HashSet<string> WaitingNotices = new(StringComparer.Ordinal)
    {
        "permission_prompt", "idle_prompt", "agent_needs_input", "elicitation_dialog",
    };

    public void Apply(HookEvent @event, DateTimeOffset now)
    {
        var session = _sessions.GetValueOrDefault(@event.SessionId)
            ?? new AgentSession(@event.SessionId, @event.Project, null, AgentState.Idle, now, now);
        session = session with { Project = @event.Project };
        if (@event.Agent is { } agent) session = session with { Agent = agent.Name() };
        var previous = session.State;
        var state = previous;
        switch (@event.Event)
        {
            case "SessionStart":
                state = AgentState.Idle;
                break;
            case "UserPromptSubmit":
                // Never the prompt itself: the island can be on a shared screen.
                state = AgentState.Working(null);
                break;
            case "PreToolUse" or "PostToolUse" or "PostToolUseFailure" or "SubagentStart":
                state = AgentState.Working(@event.ToolSummary ?? (previous.Kind == AgentStateKind.Working ? previous.Detail : null));
                break;
            case "PermissionRequest":
                state = AgentState.Waiting(@event.RequestSummary);
                break;
            case "Notification":
                if (WaitingNotices.Contains(@event.NotificationType ?? ""))
                {
                    // A permission prompt already shown with its details keeps them.
                    if (previous.Kind == AgentStateKind.Waiting && @event.NotificationType == "permission_prompt") break;
                    state = AgentState.Waiting(@event.Message);
                }
                break;
            case "Stop":
                state = AgentState.Done;
                break;
            case "SessionEnd" or "End":
                _sessions.Remove(@event.SessionId);
                return;
            // Generic states, from `colctl agent` for agents without hooks.
            case "Working":
                state = AgentState.Working(@event.Message);
                break;
            case "Waiting":
                state = AgentState.Waiting(@event.Message);
                break;
            case "Done":
                state = AgentState.Done;
                break;
            case "Idle":
                state = AgentState.Idle;
                break;
        }
        _sessions[@event.SessionId] = session with
        {
            State = state,
            Since = previous.Kind == state.Kind && _sessions.ContainsKey(@event.SessionId) ? session.Since : now,
            Updated = now,
        };
    }

    /// <summary>Sessions that finished long enough ago go quiet.</summary>
    public void Settle(DateTimeOffset now, double afterSeconds = 6)
    {
        foreach (var session in _sessions.Values.ToList())
        {
            if (session.State.Kind != AgentStateKind.Done || (now - session.Updated).TotalSeconds < afterSeconds) continue;
            if (CodingAgents.Named(session.Agent) is { } agent && !agent.EndsSessions())
                _sessions.Remove(session.Id); // No end will ever come for this session: it leaves with its Done.
            else
                _sessions[session.Id] = session with { State = AgentState.Idle };
        }
    }

    public void Forget(string id) => _sessions.Remove(id);

    /// <summary>Sessions, the ones that need the user first, then the busy ones, then by recency.</summary>
    public IReadOnlyList<AgentSession> Ordered => _sessions.Values
        .OrderByDescending(s => Rank(s.State.Kind)).ThenByDescending(s => s.Updated).ThenByDescending(s => s.Id, StringComparer.Ordinal)
        .ToList();

    private static int Rank(AgentStateKind kind) => kind switch
    {
        AgentStateKind.Waiting => 3,
        AgentStateKind.Working => 2,
        AgentStateKind.Done => 1,
        _ => 0,
    };

    /// <summary>
    /// What the closed island shows for all agents together, or null when none is doing anything worth showing: the
    /// logo of the agent at the top, which hops as it starts to wait for the user, and beside it what it does.
    /// </summary>
    public Activity? Activity(DateTimeOffset now, Rgba tint)
    {
        var active = Ordered.Where(s => s.State.Kind != AgentStateKind.Idle).ToList();
        if (active.Count == 0) return null;
        var top = active[0];
        var waiting = top.State.Kind == AgentStateKind.Waiting;
        var leading = CompactItem.AgentLogo(top.Agent ?? top.Project, waiting ? top.Since : null);
        return top.State.Kind switch
        {
            AgentStateKind.Waiting => new Activity("agents", ActivityPriority.Alert,
                new CompactPresentation(leading, CompactItem.Symbol("hand", Rgba.Orange)), top.Updated),
            AgentStateKind.Working => new Activity("agents", ActivityPriority.Standard,
                new CompactPresentation(leading, active.Count > 1
                    ? CompactItem.Label(active.Count.ToString(CultureInfo.InvariantCulture), tint)
                    : CompactItem.Spinner(tint)), top.Since),
            _ => new Activity("agents", ActivityPriority.Transient,
                new CompactPresentation(leading, CompactItem.Symbol("check", Rgba.Green)), top.Updated, top.Updated.AddSeconds(4)),
        };
    }
}
