using System.Text.Json.Nodes;

namespace Col.Core;

public enum Decision
{
    Allow,
    Deny,
    /// <summary>Let the agent ask in the terminal, as if Col were not there.</summary>
    Ask,
}

/// <summary>A permission request waiting for the user in the island.</summary>
public sealed record PendingRequest(
    string Id,
    string SessionId,
    string Project,
    string? Agent,
    /// <summary>The tool, as people read its name.</summary>
    string Tool,
    /// <summary>What it is for, in a line: the command's first line for a shell, never the agent's description of it.</summary>
    string Summary,
    /// <summary>What Allow would approve, whole, as the card shows it.</summary>
    RequestDetail? Detail,
    DateTimeOffset Received,
    string? ToolName,
    JsonObject? ToolInput);

/// <summary>
/// Follows the coding agents that report through their hooks, and holds their permission requests until the user
/// answers from the island. Safe to use from any thread: the local API calls it from its own threads, the island from
/// the interface's.
/// </summary>
public sealed class AgentCenter
{
    private readonly object _lock = new();
    private readonly TimeProvider _time;
    private readonly AgentBoard _board = new();
    private readonly Dictionary<string, PendingRequest> _pending = new(StringComparer.Ordinal);
    private readonly Dictionary<string, TaskCompletionSource<Decision>> _responders = new(StringComparer.Ordinal);
    private readonly Dictionary<string, ITimer> _timeouts = new(StringComparer.Ordinal);
    private ITimer? _settleTimer;

    /// <summary>How long a permission request waits for the island before falling back to the terminal.</summary>
    public TimeSpan AnswerWindow { get; init; } = TimeSpan.FromSeconds(90);

    /// <summary>Raised after any change, on the thread that made it.</summary>
    public event Action? Changed;
    /// <summary>Raised when a request arrives, so the island can open and show it.</summary>
    public event Action<PendingRequest>? RequestArrived;

    public AgentCenter(TimeProvider? time = null) => _time = time ?? TimeProvider.System;

    public IReadOnlyList<AgentSession> Sessions
    {
        get { lock (_lock) return _board.Ordered; }
    }

    /// <summary>The requests waiting, oldest first.</summary>
    public IReadOnlyList<PendingRequest> Pending
    {
        get { lock (_lock) return _pending.Values.OrderBy(r => r.Received).ThenBy(r => r.Id, StringComparer.Ordinal).ToList(); }
    }

    public Activity? Activity(Rgba tint)
    {
        lock (_lock) return _board.Activity(_time.GetUtcNow(), tint);
    }

    /// <summary>Takes in an event. The answer comes at once, except for a permission request of an agent that waits
    /// for one: it comes when the user answers, or as Ask once the answer window has passed.</summary>
    public Task<Decision> Receive(HookEvent @event)
    {
        var now = _time.GetUtcNow();
        PendingRequest? arrived = null;
        Task<Decision> answer;
        var toResolve = new List<(TaskCompletionSource<Decision>, Decision)>();
        lock (_lock)
        {
            _board.Apply(@event, now);
            // Only agents whose hooks wait for an answer get the buttons; the others show they are waiting for the user.
            if (@event.Event == "PermissionRequest" && (@event.Agent?.AnswersPermissions() ?? true))
            {
                var id = Guid.NewGuid().ToString();
                arrived = new PendingRequest(
                    id, @event.SessionId, @event.Project, @event.Agent?.Name(), @event.ToolLabel ?? "",
                    @event.RequestSummary ?? "", @event.ToolDetail is { } detail ? new RequestDetail(detail) : null, now,
                    @event.ToolName, @event.ToolInput);
                _pending[id] = arrived;
                var source = new TaskCompletionSource<Decision>(TaskCreationOptions.RunContinuationsAsynchronously);
                _responders[id] = source;
                _timeouts[id] = _time.CreateTimer(_ => Decide(id, Decision.Ask, fromUser: false), null, AnswerWindow, Timeout.InfiniteTimeSpan);
                answer = source.Task;
            }
            else
            {
                answer = Task.FromResult(Decision.Ask);
                if (@event.Event is "Stop" or "SessionEnd" or "UserPromptSubmit")
                {
                    // The session moved on: a request it left behind was answered elsewhere.
                    foreach (var request in _pending.Values.Where(r => r.SessionId == @event.SessionId).ToList())
                        toResolve.Add((Take(request.Id)!, Decision.Ask));
                }
                else if (@event.Event is "PostToolUse" or "PostToolUseFailure")
                {
                    // A tool that ran was allowed, in the island or in the terminal: its request, and only its, is over.
                    var match = _pending.Values
                        .Where(r => r.SessionId == @event.SessionId && r.ToolName == @event.ToolName && JsonNode.DeepEquals(r.ToolInput, @event.ToolInput))
                        .OrderBy(r => r.Received).FirstOrDefault();
                    if (match is not null) toResolve.Add((Take(match.Id)!, Decision.Ask));
                }
            }
            ScheduleSettle();
        }
        foreach (var (source, decision) in toResolve) source.TrySetResult(decision);
        if (arrived is not null) RequestArrived?.Invoke(arrived);
        Changed?.Invoke();
        return answer;
    }

    /// <summary>The user's answer from the island. Allow approves only what the island could show whole; anything longer
    /// is answered in the terminal.</summary>
    public void Decide(string requestId, Decision decision) => Decide(requestId, decision, fromUser: true);

    private void Decide(string requestId, Decision decision, bool fromUser)
    {
        TaskCompletionSource<Decision>? source;
        lock (_lock)
        {
            if (!_pending.TryGetValue(requestId, out var request)) return;
            if (decision == Decision.Allow && !CanAllow(request)) decision = Decision.Ask;
            source = Take(requestId);
            if (fromUser && decision != Decision.Ask)
                _board.Apply(new HookEvent(request.SessionId, "PreToolUse"), _time.GetUtcNow());
        }
        source?.TrySetResult(decision);
        Changed?.Invoke();
    }

    /// <summary>Whether the island may allow a request: what it approves fits the card, so it was seen whole. A request
    /// with input the card does not show is never allowed from it; only one that carries none is.</summary>
    public static bool CanAllow(PendingRequest request) =>
        request.Detail is { } detail ? detail.FitsCard : request.ToolInput is null || request.ToolInput.Count == 0;

    /// <summary>Removes a request and returns its responder. Call with the lock held.</summary>
    private TaskCompletionSource<Decision>? Take(string requestId)
    {
        _pending.Remove(requestId);
        if (_timeouts.Remove(requestId, out var timer)) timer.Dispose();
        return _responders.Remove(requestId, out var source) ? source : null;
    }

    /// <summary>Finished sessions go quiet after a few seconds; one timer for all of them. Call with the lock held.</summary>
    private void ScheduleSettle()
    {
        _settleTimer?.Dispose();
        _settleTimer = null;
        if (!_board.Sessions.Values.Any(s => s.State.Kind == AgentStateKind.Done)) return;
        _settleTimer = _time.CreateTimer(_ =>
        {
            lock (_lock) _board.Settle(_time.GetUtcNow());
            Changed?.Invoke();
        }, null, TimeSpan.FromSeconds(6.2), Timeout.InfiniteTimeSpan);
    }
}
