// colctl: pushes live activities to Col, and connects coding agents to it.
//
// Speaks HTTP over Col's named pipe, which only the account running it can open, so it only reaches the Col of the
// user running it. The same commands and the same JSON as on the Mac.

using System.Globalization;
using System.IO.Pipes;
using System.Security.Principal;
using System.Text;
using System.Text.Json.Nodes;
using Col.Core;

const string Usage = """
    usage: colctl <command> [options]

      push <id> [--title T] [--subtitle S] [--symbol SF_SYMBOL] [--tint COLOR]
                [--progress 0..1 | N%] [--text T] [--priority ambient|standard|alert] [--ttl SECONDS]
                            show or update a live activity in the island
      done <id> [--text T]  mark an activity done: a check mark, then it leaves
      remove <id>           take an activity away
      list                  list the activities pushed by programs
      status                check that Col is running

      hooks install [--agent AGENT] [--settings PATH]
                            connect a coding agent to the island; AGENT is claude (default),
                            codex or all
      hooks uninstall [--agent AGENT] [--settings PATH]
      hooks status          show which agents are connected
      hook [--agent AGENT]  the hook itself: reads the agent's event on stdin
      agent <name> <working|waiting|done|idle|end> [--message M] [--session S]
                            report any other agent or script to the island

    Colours: white, green, orange, red, blue, purple, yellow, pink, teal, gray, or #RRGGBB.
    Example: colctl push build --title Build --symbol hammer.fill --tint orange --progress 40%
    """;

var arguments = args;
if (arguments.Length == 0)
{
    Console.WriteLine(Usage);
    return 0;
}

switch (arguments[0])
{
    case "push":
    {
        if (arguments.Length < 2 || arguments[1].StartsWith("--", StringComparison.Ordinal)) return Fail("push needs an id");
        var values = Options(arguments[2..]);
        if (values is null) return 1;
        var body = new JsonObject { ["id"] = arguments[1] };
        foreach (var key in new[] { "title", "subtitle", "symbol", "tint", "text", "priority" })
        {
            if (values.TryGetValue(key, out var value)) body[key] = value;
        }
        if (values.TryGetValue("progress", out var progress))
        {
            if (PercentOrFraction(progress) is not { } fraction) return Fail("--progress takes 0 to 1, or a percentage");
            body["progress"] = fraction;
        }
        if (values.TryGetValue("ttl", out var ttl))
        {
            if (!double.TryParse(ttl, NumberStyles.Float, CultureInfo.InvariantCulture, out var seconds)) return Fail("--ttl takes seconds");
            body["ttl"] = seconds;
        }
        return Run("POST", "/v1/activities", Encoding.UTF8.GetBytes(body.ToJsonString())) is null ? 1 : 0;
    }

    case "done":
    {
        if (arguments.Length < 2) return Fail("done needs an id");
        var values = Options(arguments[2..]);
        if (values is null) return 1;
        var query = values.TryGetValue("text", out var text) ? "?text=" + Uri.EscapeDataString(text) : "";
        return Run("POST", $"/v1/activities/{Uri.EscapeDataString(arguments[1])}/done{query}") is null ? 1 : 0;
    }

    case "remove":
        if (arguments.Length < 2) return Fail("remove needs an id");
        return Run("DELETE", $"/v1/activities/{Uri.EscapeDataString(arguments[1])}") is null ? 1 : 0;

    case "list":
    {
        if (Run("GET", "/v1/activities") is not { } data) return 1;
        var list = (JsonNode.Parse(data) as JsonObject)?["activities"] as JsonArray ?? new JsonArray();
        if (list.Count == 0) Console.WriteLine("No activities.");
        foreach (var item in list.OfType<JsonObject>())
        {
            var id = Text(item["id"]) ?? "";
            var title = Text(item["title"]) ?? "";
            var detail = item["progress"] is JsonValue p && p.TryGetValue(out double fraction)
                ? $"{(int)(fraction * 100)}%"
                : Text(item["text"]) ?? "";
            Console.WriteLine(string.Join("  ", new[] { id, title, detail }.Where(s => s.Length > 0)));
        }
        return 0;
    }

    case "status":
    {
        if (Run("GET", "/v1/status") is not { } data) return 1;
        var info = JsonNode.Parse(data) as JsonObject ?? new JsonObject();
        Console.WriteLine($"Col {Text(info["version"])} is running: {info["activities"]} activities, {info["agents"]} agent sessions.");
        return 0;
    }

    case "agent":
    {
        var rest = arguments[1..];
        if (rest.Length < 2) return Fail("agent needs a name and a state");
        var states = new Dictionary<string, string>
        {
            ["working"] = "Working", ["waiting"] = "Waiting", ["done"] = "Done", ["idle"] = "Idle", ["end"] = "End",
        };
        if (!states.TryGetValue(rest[1].ToLowerInvariant(), out var state)) return Fail("state is working, waiting, done, idle or end");
        // Anything after the options (Codex passes its event as a last argument) is ignored.
        var values = new Dictionary<string, string>();
        for (var index = 2; index + 1 < rest.Length && rest[index].StartsWith("--", StringComparison.Ordinal); index += 2)
            values[rest[index][2..]] = rest[index + 1];
        var @event = new JsonObject
        {
            ["hook_event_name"] = state,
            ["agent_name"] = rest[0],
            ["session_id"] = values.GetValueOrDefault("session") ?? rest[0].ToLowerInvariant(),
        };
        if (values.TryGetValue("message", out var message)) @event["message"] = message;
        // Agents call this from their own hooks: never fail loudly when Col is closed.
        Send("POST", "/v1/agents/events", Encoding.UTF8.GetBytes(@event.ToJsonString()), TimeSpan.FromSeconds(3));
        return 0;
    }

    case "hook":
    {
        var values = Options(arguments[1..], quiet: true) ?? new Dictionary<string, string>();
        // An unknown agent still must not break the agent calling it.
        if (CodingAgents.FromId(values.GetValueOrDefault("agent") ?? "claude") is not { } agent) return 0;
        return Hook(agent);
    }

    case "hooks":
    {
        var action = arguments.Length > 1 ? arguments[1] : "";
        var values = Options(arguments.Length > 2 ? arguments[2..] : []);
        if (values is null) return 1;
        var id = values.GetValueOrDefault("agent") ?? "claude";
        if (id != "all" && HooksInstaller.Named(id) is null) return Fail($"unknown agent {id}: claude, codex or all");
        IReadOnlyList<HookAgent> agents = id == "all" ? HooksInstaller.All : [HooksInstaller.Named(id)!];
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        switch (action)
        {
            case "install":
            case "uninstall":
            {
                var tool = Environment.ProcessPath;
                if (tool is null) return Fail("cannot find colctl's own file");
                var failed = false;
                var any = false;
                foreach (var agent in agents)
                {
                    // With --agent all, only agents present on this PC are connected.
                    if (id == "all" && action == "install" && !HooksInstaller.IsInstalled(agent, home)) continue;
                    any = true;
                    var path = agents.Count == 1 && values.TryGetValue("settings", out var custom) ? custom : agent.SettingsPath(home);
                    try
                    {
                        Console.WriteLine(HooksInstaller.Edit(agent, path, action == "install", tool));
                    }
                    catch (HooksException error)
                    {
                        Console.Error.WriteLine($"colctl: {error.Message}");
                        failed = true;
                    }
                }
                if (!any) Console.WriteLine("No coding agent found on this PC: install Claude Code or Codex first.");
                return failed ? 1 : 0;
            }
            case "status":
                foreach (var agent in HooksInstaller.All)
                {
                    var connected = HooksInstaller.IsConnected(agent.SettingsPath(home));
                    Console.WriteLine($"{agent.Name,-12} {(connected ? "connected" : "not connected")}");
                }
                return 0;
            default:
                return Fail("hooks takes install, uninstall or status");
        }
    }

    case "help" or "--help" or "-h" or "/?":
        Console.WriteLine(Usage);
        return 0;

    case "--version" or "version":
        Console.WriteLine($"colctl {Version()}");
        return 0;

    default:
        return Fail($"unknown command {arguments[0]}. Run `colctl help`.");
}

// The hook. Never gets in the agent's way: when Col is not running, or anything goes wrong, it answers what "carry
// on as usual" means for that agent and exits 0.
static int Hook(CodingAgent agent)
{
    byte[] input;
    try
    {
        using var stdin = Console.OpenStandardInput();
        using var buffer = new MemoryStream();
        stdin.CopyTo(buffer);
        input = HookRelay.Clean(buffer.ToArray());
    }
    catch (IOException)
    {
        input = [];
    }
    var name = HookRelay.EventName(input);
    var neutral = HookRelay.Neutral(agent, name);
    int CarryOn()
    {
        if (neutral is not null) Write(neutral);
        return 0;
    }
    if (!HookRelay.IsEvent(input)) return CarryOn();
    var waits = HookRelay.Waits(agent, name);
    var reply = Send("POST", $"/v1/agents/events?agent={agent.Id()}", input, HookRelay.AnswerTimeout(waits));
    if (reply is not { Status: 200 } answer || !waits) return CarryOn();
    if (HookRelay.PermissionOutput(HookRelay.DecisionFrom(answer.Body)) is not { } output) return CarryOn();
    // Claude Code and Codex read the same answer.
    Write(output);
    return 0;
}

static void Write(string text)
{
    using var stdout = Console.OpenStandardOutput();
    var bytes = Encoding.UTF8.GetBytes(text);
    stdout.Write(bytes, 0, bytes.Length);
    stdout.Flush();
}

// The pipe of this user's Col.
static string PipeName()
{
    using var identity = WindowsIdentity.GetCurrent();
    return Ipc.PipeName(identity.User?.Value ?? "unknown", Environment.GetEnvironmentVariable("COL_PIPE"));
}

// Sends one request and returns the status and body; null when Col is not running or did not answer in time. Waits
// for the pipe only briefly, so a hook never holds its agent when Col is closed.
static (int Status, byte[] Body)? Send(string method, string target, byte[]? body, TimeSpan answerTimeout)
{
    try
    {
        using var pipe = new NamedPipeClientStream(".", PipeName(), PipeDirection.InOut, PipeOptions.Asynchronous);
        pipe.Connect((int)Ipc.ConnectTimeout.TotalMilliseconds);
        // Only a pipe made by this same account is Col's: anyone else's could be waiting under its name.
        if (!OwnedByMe(pipe)) return null;
        using var cancellation = new CancellationTokenSource(answerTimeout);
        var request = HttpWire.FormatRequest(method, target, body);
        pipe.WriteAsync(request, cancellation.Token).AsTask().GetAwaiter().GetResult();
        pipe.Flush();
        return HttpWire.ReadResponseAsync(pipe, cancellation.Token).GetAwaiter().GetResult();
    }
    catch (Exception)
    {
        return null;
    }
}

// Whether the pipe's owner is the account running colctl, from an ordinary or an administrator's terminal alike.
static bool OwnedByMe(NamedPipeClientStream pipe)
{
    var owner = pipe.GetAccessControl().GetOwner(typeof(SecurityIdentifier));
    using var me = WindowsIdentity.GetCurrent();
    return owner is not null && (owner.Equals(me.User) || owner.Equals(me.Owner));
}

static byte[]? Run(string method, string target, byte[]? body = null)
{
    var reply = Send(method, target, body, TimeSpan.FromSeconds(5));
    if (reply is not { } answer)
    {
        Fail("Col is not running");
        return null;
    }
    if (answer.Status != 200)
    {
        string? reason = null;
        try { reason = Text((JsonNode.Parse(answer.Body) as JsonObject)?["error"]); }
        catch (Exception) { /* no reason given */ }
        Fail(reason ?? $"Col answered {answer.Status}");
        return null;
    }
    return answer.Body;
}

static Dictionary<string, string>? Options(string[] arguments, bool quiet = false)
{
    var result = new Dictionary<string, string>();
    for (var index = 0; index < arguments.Length; index++)
    {
        var argument = arguments[index];
        if (!argument.StartsWith("--", StringComparison.Ordinal))
        {
            if (quiet) continue;
            Fail($"unexpected argument {argument}");
            return null;
        }
        if (index + 1 >= arguments.Length)
        {
            if (quiet) continue;
            Fail($"{argument} needs a value");
            return null;
        }
        result[argument[2..]] = arguments[++index];
    }
    return result;
}

static double? PercentOrFraction(string value)
{
    if (value.EndsWith('%'))
        return double.TryParse(value[..^1], NumberStyles.Float, CultureInfo.InvariantCulture, out var percent) ? percent / 100 : null;
    if (!double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var number)) return null;
    return number > 1 ? number / 100 : number;
}

static string? Text(JsonNode? node) => node is JsonValue value && value.TryGetValue(out string? text) ? text : null;

static string Version() =>
    System.Reflection.CustomAttributeExtensions.GetCustomAttribute<System.Reflection.AssemblyInformationalVersionAttribute>(
        typeof(HookRelay).Assembly)?.InformationalVersion ?? "3.1.0";

static int Fail(string message)
{
    Console.Error.WriteLine($"colctl: {message}");
    return 1;
}
