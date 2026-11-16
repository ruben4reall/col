using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Col.Core;

/// <summary>
/// A coding agent's hook event, in the shape Claude Code and Codex write on a hook's stdin. Other agents' events are
/// translated into it by <see cref="CodingAgents.EventFrom"/>.
/// </summary>
public sealed record HookEvent(string SessionId, string Event)
{
    public string? Cwd { get; init; }
    public string? ToolName { get; init; }
    public JsonObject? ToolInput { get; init; }
    public string? NotificationType { get; init; }
    public string? Message { get; init; }
    /// <summary>Set by agents without hooks, through <c>colctl agent</c>: their name stands for the project.</summary>
    public string? AgentName { get; init; }
    /// <summary>The agent whose hooks sent the event. Not part of the payload: the hook says it in the request.</summary>
    public CodingAgent? Agent { get; init; }

    /// <summary>The project, named after the folder the session runs in.</summary>
    public string Project
    {
        get
        {
            if (!string.IsNullOrEmpty(AgentName)) return AgentName;
            if (string.IsNullOrEmpty(Cwd)) return Agent?.Name() ?? "Agent";
            return PathNames.Last(Cwd);
        }
    }

    /// <summary>Tool names across agents, shown the way people read them.</summary>
    internal static readonly Dictionary<string, string> ToolLabels = new(StringComparer.Ordinal)
    {
        ["run_shell_command"] = "Shell", ["shell"] = "Shell", ["write_file"] = "Write", ["replace"] = "Edit",
        ["read_file"] = "Read", ["read_many_files"] = "Read", ["web_fetch"] = "Fetch", ["google_web_search"] = "Search",
        ["search_file_content"] = "Grep", ["list_directory"] = "List", ["apply_patch"] = "Patch",
    };

    /// <summary>The tools that run a shell command. PowerShell is Claude Code's shell tool on Windows.</summary>
    internal static readonly HashSet<string> ShellTools = new(StringComparer.Ordinal)
    {
        "Bash", "Shell", "run_shell_command", "shell", "PowerShell",
    };

    /// <summary>The tool's name, the way people read it.</summary>
    public string? ToolLabel => ToolName is null ? null : ToolLabels.GetValueOrDefault(ToolName, ToolName);

    private string? Input(string key) =>
        ToolInput?[key] is JsonValue value && value.TryGetValue(out string? text) ? text : null;

    private string? File(string key) => Input(key) is { } path ? PathNames.Last(path) : null;

    private string? FirstLine(string key) => Input(key) is { } text ? text.Split('\n')[0] : null;

    /// <summary>A short line saying what the tool is about to do: the command for a shell, the file for edits.</summary>
    public string? ToolSummary
    {
        get
        {
            if (ToolName is null) return null;
            string? detail = ToolName switch
            {
                _ when ShellTools.Contains(ToolName) => Input("description") ?? FirstLine("command"),
                "Edit" or "Write" or "Read" or "NotebookEdit" or "MultiEdit" => File("file_path") ?? File("notebook_path"),
                "Grep" or "Glob" => Input("pattern"),
                "WebFetch" or "web_fetch" => (Input("url") is { } url && Uri.TryCreate(url, UriKind.Absolute, out var uri) ? uri.Host : null) ?? Input("prompt"),
                "WebSearch" or "google_web_search" => Input("query"),
                "Agent" or "Task" => Input("description"),
                // Other agents' tools: the first argument that reads like a target.
                _ => FirstLine("command") ?? File("file_path") ?? File("absolute_path") ?? File("path") ?? Input("pattern") ?? Input("query"),
            };
            var label = ToolLabel ?? ToolName;
            if (string.IsNullOrEmpty(detail)) return label;
            return $"{label} · {Prefix(detail, 70)}";
        }
    }

    /// <summary>
    /// What a permission request is for, in a line, never in the agent's own words. The description an agent gives a
    /// shell command is its own claim about it and can say anything, so a request names the command itself.
    /// </summary>
    public string? RequestSummary
    {
        get
        {
            if (ToolName is null || !ShellTools.Contains(ToolName)) return ToolSummary;
            var label = ToolLabel ?? ToolName;
            var line = Input("command")?.Split('\n').FirstOrDefault(l => !string.IsNullOrWhiteSpace(l));
            if (line is null) return label;
            return $"{label} · {Prefix(line.Trim(' ', '\t'), 70)}";
        }
    }

    /// <summary>
    /// What a permission request approves, whole: the command for a shell, the file for the tools that read or change
    /// one, the address for a fetch. Any other tool (one from an MCP server, say), or a known one whose input has
    /// another shape, gives every argument it was given, so nothing a request carries stays off the card.
    /// </summary>
    public string? ToolDetail
    {
        get
        {
            if (ToolInput is null || ToolInput.Count == 0) return null;
            foreach (var key in TargetKeys)
            {
                if (Input(key) is { } value) return value;
            }
            return Arguments(ToolInput);
        }
    }

    /// <summary>The argument that names what a known tool acts on. Its others only say how: a timeout, a range of lines.</summary>
    private string[] TargetKeys
    {
        get
        {
            if (ToolName is null) return [];
            if (ShellTools.Contains(ToolName)) return ["command"];
            return ToolName switch
            {
                "Edit" or "MultiEdit" or "Write" or "Read" or "write_file" or "replace" or "read_file" => ["file_path", "absolute_path"],
                "NotebookEdit" => ["notebook_path"],
                "WebFetch" or "web_fetch" => ["url"],
                _ => [],
            };
        }
    }

    /// <summary>Every argument, a line each, in the order of their names: text as it is, anything else as JSON.</summary>
    internal static string Arguments(JsonObject input) =>
        string.Join("\n", input.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => $"{p.Key}: {Shown(p.Value)}"));

    private static readonly JsonWriterOptions CompactWriter = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    /// <summary>A value written out in full: text as it is, anything else as compact JSON with its keys in order.</summary>
    internal static string Shown(JsonNode? value)
    {
        if (value is JsonValue text && text.TryGetValue(out string? s)) return s;
        using var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer, CompactWriter)) WriteSorted(writer, value);
        return Encoding.UTF8.GetString(buffer.ToArray());
    }

    private static void WriteSorted(Utf8JsonWriter writer, JsonNode? node)
    {
        switch (node)
        {
            case null:
                writer.WriteNullValue();
                break;
            case JsonObject obj:
                writer.WriteStartObject();
                foreach (var pair in obj.OrderBy(p => p.Key, StringComparer.Ordinal))
                {
                    writer.WritePropertyName(pair.Key);
                    WriteSorted(writer, pair.Value);
                }
                writer.WriteEndObject();
                break;
            case JsonArray array:
                writer.WriteStartArray();
                foreach (var item in array) WriteSorted(writer, item);
                writer.WriteEndArray();
                break;
            default:
                node.WriteTo(writer);
                break;
        }
    }

    private static string Prefix(string text, int length)
    {
        if (text.Length <= length) return text;
        // Never cut a surrogate pair in two.
        var cut = char.IsHighSurrogate(text[length - 1]) ? length - 1 : length;
        return text[..cut];
    }
}

/// <summary>The last name of a path, whichever separator the agent wrote it with.</summary>
public static class PathNames
{
    public static string Last(string path)
    {
        var trimmed = path.TrimEnd('/', '\\');
        if (trimmed.Length == 0) return path;
        var index = trimmed.LastIndexOfAny(['/', '\\']);
        return index < 0 ? trimmed : trimmed[(index + 1)..];
    }
}
