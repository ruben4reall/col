using System.Text.Json.Nodes;

namespace Col.Core;

/// <summary>
/// The routes of the local API, the same as on the Mac:
/// <code>
///     GET    /v1/status
///     GET    /v1/activities
///     POST   /v1/activities                 body: an activity
///     POST   /v1/activities/&lt;id&gt;/done       ?text=Done
///     DELETE /v1/activities/&lt;id&gt;
///     POST   /v1/agents/events?agent=codex  body: a hook event as the agent wrote it; answers {"decision": allow|deny|ask}
/// </code>
/// and one of Windows' own, which a second copy of Col uses to hand a <c>col://</c> link to the one running:
/// <code>
///     POST   /v1/open?url=col://settings
/// </code>
/// </summary>
public sealed class ControlApi(CustomActivities custom, AgentCenter agents, string version, TimeProvider? time = null)
{
    private readonly TimeProvider _time = time ?? TimeProvider.System;

    /// <summary>Opens a <c>col://</c> link in the app; false when the link means nothing to it.</summary>
    public Func<string, bool>? OpenLink { get; set; }

    public async Task<HttpResponse> HandleAsync(HttpRequest request)
    {
        var parts = request.Path.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0 || parts[0] != "v1") return HttpResponse.Error("not found", 404);
        var route = parts[1..];
        // The id of /v1/activities/<id>[/done].
        var id = route.Length >= 2 && route[0] == "activities" ? route[1] : "";
        var now = _time.GetUtcNow();

        switch (request.Method, route.Length)
        {
            case ("GET", 1) when route[0] == "status":
                return HttpResponse.Json(new JsonObject
                {
                    ["app"] = "Col",
                    ["version"] = version,
                    ["activities"] = custom.Entries.Count,
                    ["agents"] = agents.Sessions.Count,
                });

            case ("GET", 1) when route[0] == "activities":
            {
                var list = new JsonArray();
                foreach (var entry in custom.Entries)
                {
                    var item = new JsonObject { ["id"] = entry.Id, ["finished"] = entry.Finished };
                    if (entry.Request.Title is { } title) item["title"] = title;
                    if (entry.Request.Progress is { } progress) item["progress"] = progress;
                    if (entry.Request.Text is { } text) item["text"] = text;
                    list.Add((JsonNode)item);
                }
                return HttpResponse.Json(new JsonObject { ["activities"] = list });
            }

            case ("POST", 1) when route[0] == "activities":
            {
                ActivityRequest? payload;
                try { payload = ActivityRequest.FromJson(request.Body)?.Validated(); }
                catch (ActivityRequest.InvalidException) { payload = null; }
                if (payload is null) return HttpResponse.Error("expected an activity with an id", 400);
                custom.Upsert(payload, now);
                return HttpResponse.Json(new JsonObject { ["id"] = payload.Id });
            }

            case ("POST", 3) when route[0] == "activities" && route[2] == "done" && id.Length > 0:
                if (custom.Finish(id, request.Query.GetValueOrDefault("text"), now) is null)
                    return HttpResponse.Error("no such activity", 404);
                return HttpResponse.Json(new JsonObject { ["id"] = id });

            case ("DELETE", 2) when route[0] == "activities" && id.Length > 0:
                custom.Remove(id);
                return HttpResponse.Json(new JsonObject { ["id"] = id });

            case ("POST", 2) when route[0] == "agents" && route[1] == "events":
            {
                var agent = CodingAgents.FromId(request.Query.GetValueOrDefault("agent") ?? "claude");
                JsonObject? raw = null;
                try { raw = JsonNode.Parse(request.Body) as JsonObject; }
                catch (Exception) { /* answered below */ }
                if (agent is null || raw is null) return HttpResponse.Error("expected a hook event", 400);
                // Events an agent sends that Col does not follow are simply acknowledged.
                if (agent.Value.EventFrom(raw) is not { } @event) return Decided(Decision.Ask);
                var decision = await agents.Receive(@event).ConfigureAwait(false);
                return Decided(decision);
            }

            case ("POST", 1) when route[0] == "open":
            {
                var url = request.Query.GetValueOrDefault("url") ?? "";
                if (!url.StartsWith("col://", StringComparison.OrdinalIgnoreCase) || OpenLink is null || !OpenLink(url))
                    return HttpResponse.Error("expected a col:// link", 400);
                return HttpResponse.Json(new JsonObject { ["url"] = url });
            }
        }
        return HttpResponse.Error("not found", 404);
    }

    private static HttpResponse Decided(Decision decision) => HttpResponse.Json(new JsonObject { ["decision"] = decision.Name() });
}

/// <summary>Where the local API listens on Windows.</summary>
public static class Ipc
{
    /// <summary>
    /// The named pipe of a user's Col: <c>\\.\pipe\col-&lt;SID&gt;</c>. Named pipes are shared by every session of
    /// the PC; the account's security identifier keeps each user's apart. <c>COL_PIPE</c> moves it, so a development
    /// build can run beside the installed Col.
    /// </summary>
    public static string PipeName(string userSid, string? overrideName = null) =>
        !string.IsNullOrWhiteSpace(overrideName) ? overrideName.Trim() : "col-" + userSid;

    /// <summary>How long a client waits for the pipe: when Col is not running, a hook gives up this soon, so the agent
    /// is never held.</summary>
    public static readonly TimeSpan ConnectTimeout = TimeSpan.FromMilliseconds(300);
}
