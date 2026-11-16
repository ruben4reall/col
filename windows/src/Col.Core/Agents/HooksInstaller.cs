using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Col.Core;

/// <summary>One event an agent's hooks follow: whether it takes a tool matcher, and its timeout in seconds.</summary>
public sealed record HookEventSpec(string Name, bool Matcher, int Timeout);

/// <summary>A coding agent Col connects to on Windows, and where it keeps its hooks.</summary>
public sealed record HookAgent(CodingAgent Agent, string Folder, string FileName, IReadOnlyList<HookEventSpec> Events)
{
    public string Id => Agent.Id();
    public string Name => Agent.Name();

    /// <summary>The settings file under a home folder: %USERPROFILE%\.claude\settings.json for Claude Code.</summary>
    public string SettingsPath(string home) => Path.Combine(home, Folder, FileName);
}

public sealed class HooksException(string message) : Exception(message);

/// <summary>
/// Adds Col's hooks to an agent's settings, or takes them away, keeping everything else as it was and a copy of the
/// file beside it. The same rules as the Mac's <c>colctl hooks</c>.
/// </summary>
public static partial class HooksInstaller
{
    public static readonly HookAgent Claude = new(CodingAgent.Claude, ".claude", "settings.json",
    [
        new("SessionStart", false, 5), new("UserPromptSubmit", false, 5), new("PreToolUse", true, 5),
        new("PostToolUse", true, 5), new("PermissionRequest", true, 120), new("Notification", false, 5),
        new("Stop", false, 5), new("SessionEnd", false, 2),
    ]);

    public static readonly HookAgent Codex = new(CodingAgent.Codex, ".codex", "hooks.json",
    [
        new("SessionStart", false, 5), new("UserPromptSubmit", false, 5), new("PreToolUse", false, 5),
        new("PostToolUse", false, 5), new("PermissionRequest", false, 120), new("Stop", false, 5), new("SessionEnd", false, 2),
    ]);

    public static readonly IReadOnlyList<HookAgent> All = [Claude, Codex];

    public static HookAgent? Named(string id) => All.FirstOrDefault(a => a.Id == id);

    /// <summary>
    /// The command a hook runs: colctl by its full path, written with forward slashes and in double quotes, which
    /// Git Bash and cmd.exe both read the same way, whichever shell the agent runs its hooks in.
    /// </summary>
    public static string Command(HookAgent agent, string colctlPath)
    {
        var path = colctlPath.Replace('\\', '/');
        return agent.Agent == CodingAgent.Claude ? $"\"{path}\" hook" : $"\"{path}\" hook --agent {agent.Id}";
    }

    [GeneratedRegex("""colctl(\.exe)?"?\s+hook(\s|$)""", RegexOptions.IgnoreCase)]
    private static partial Regex ColCommand();

    /// <summary>Whether a hook's command is Col's.</summary>
    public static bool CallsCol(string? command) => command is not null && ColCommand().IsMatch(command);

    /// <summary>True for an entry Col wrote: a matcher group holding Col's command.</summary>
    public static bool IsColHook(JsonNode? entry)
    {
        if (entry is not JsonObject group) return false;
        if (CallsCol(Text(group["command"]))) return true;
        return group["hooks"] is JsonArray hooks && hooks.Any(h => h is JsonObject hook && CallsCol(Text(hook["command"])));
    }

    private static string? Text(JsonNode? node) => node is JsonValue value && value.TryGetValue(out string? text) ? text : null;

    private static JsonObject Entry(HookAgent agent, HookEventSpec spec, string colctlPath)
    {
        var group = new JsonObject();
        if (spec.Matcher) group["matcher"] = "*";
        group["hooks"] = new JsonArray(new JsonObject
        {
            ["type"] = "command",
            ["command"] = Command(agent, colctlPath),
            ["timeout"] = spec.Timeout,
        });
        return group;
    }

    private static readonly JsonWriterOptions Pretty = new()
    {
        Indented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    /// <summary>
    /// Adds or removes Col's hooks in an agent's settings, keeping every other hook and setting, in their order, and a
    /// copy of the file as <c>settings.json.col-backup</c>. A file that is not valid JSON is left untouched.
    /// Returns what happened, in a sentence.
    /// </summary>
    public static string Edit(HookAgent agent, string path, bool install, string colctlPath)
    {
        JsonObject settings;
        var original = File.Exists(path) ? File.ReadAllBytes(path) : null;
        var text = original is null ? ReadOnlySpan<byte>.Empty : WithoutBom(original);
        if (!IsBlank(text))
        {
            JsonNode? parsed;
            try { parsed = JsonNode.Parse(text); }
            catch (JsonException) { throw new HooksException($"{path} is not valid JSON; left untouched"); }
            settings = parsed as JsonObject ?? throw new HooksException($"{path} is not a JSON object; left untouched");
            if (settings["hooks"] is { } existing && existing is not JsonObject)
                throw new HooksException($"the hooks in {path} are not a JSON object; left untouched");
            BackUp(original!, path);
        }
        else if (!install)
        {
            return $"{agent.Name}: nothing to remove.";
        }
        else
        {
            settings = new JsonObject();
        }

        var hooks = settings["hooks"] as JsonObject ?? new JsonObject();
        foreach (var spec in agent.Events)
        {
            var kept = new JsonArray();
            if (hooks[spec.Name] is JsonArray groups)
            {
                foreach (var group in groups.Where(g => !IsColHook(g))) kept.Add((JsonNode?)group?.DeepClone());
            }
            else if (hooks[spec.Name] is { } other)
            {
                // Something Col does not understand: kept as it is, and Col's hook goes beside it only if it can.
                if (install) throw new HooksException($"the {spec.Name} hooks in {path} are not a list; left untouched");
                continue;
            }
            if (install) kept.Add((JsonNode)Entry(agent, spec, colctlPath));
            if (kept.Count == 0) hooks.Remove(spec.Name);
            else hooks[spec.Name] = kept;
        }
        if (hooks.Count == 0) settings.Remove("hooks");
        else if (hooks.Parent is null) settings["hooks"] = hooks;

        Write(settings, path);
        return install
            ? $"{agent.Name}: hooks installed in {path}. New sessions report to Col." +
              (agent.Agent == CodingAgent.Codex ? " Codex asks you to review new hooks once: run /hooks in Codex and trust Col's." : "")
            : $"{agent.Name}: Col's hooks removed from {path}.";
    }

    /// <summary>Whether an agent's settings call Col.</summary>
    public static bool IsConnected(string path)
    {
        try
        {
            if (!File.Exists(path)) return false;
            var parsed = JsonNode.Parse(WithoutBom(File.ReadAllBytes(path))) as JsonObject;
            return parsed?["hooks"] is JsonObject hooks &&
                   hooks.Any(pair => pair.Value is JsonArray groups && groups.Any(IsColHook));
        }
        catch (Exception)
        {
            return false;
        }
    }

    /// <summary>Whether the agent is on this PC: its folder exists in the home folder.</summary>
    public static bool IsInstalled(HookAgent agent, string home) => Directory.Exists(Path.Combine(home, agent.Folder));

    private static void Write(JsonObject settings, string path)
    {
        try
        {
            var folder = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(folder)) Directory.CreateDirectory(folder);
            using var buffer = new MemoryStream();
            using (var writer = new Utf8JsonWriter(buffer, Pretty)) settings.WriteTo(writer);
            buffer.WriteByte((byte)'\n');
            // Written whole under another name, then put in place, so the agent never reads half a file.
            var partial = path + ".col-partial";
            File.WriteAllBytes(partial, buffer.ToArray());
            File.Move(partial, path, overwrite: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new HooksException($"could not write {path}: {error.Message}");
        }
    }

    /// <summary>Keeps a copy of an agent's settings beside them, as they were before this change.</summary>
    private static void BackUp(byte[] data, string path)
    {
        try { File.WriteAllBytes(path + ".col-backup", data); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { /* The edit goes on: the copy is a courtesy. */ }
    }

    private static ReadOnlySpan<byte> WithoutBom(byte[] data) =>
        data.AsSpan().StartsWith(Encoding.UTF8.Preamble) ? data.AsSpan(3) : data;

    private static bool IsBlank(ReadOnlySpan<byte> data)
    {
        foreach (var b in data)
        {
            if (b is not ((byte)' ' or (byte)'\t' or (byte)'\r' or (byte)'\n')) return false;
        }
        return true;
    }
}
