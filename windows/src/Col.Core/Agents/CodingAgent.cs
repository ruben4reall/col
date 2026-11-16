using System.Text.Json.Nodes;

namespace Col.Core;

/// <summary>
/// The coding agents Col follows through their own hooks. Each writes its events in its own shape; they all become the
/// same <see cref="HookEvent"/>, so the board and the island never need to know which agent sent one.
/// </summary>
public enum CodingAgent
{
    Claude,
    Codex,
    Gemini,
    Cursor,
    Copilot,
}

public static class CodingAgents
{
    /// <summary>The agent's name in hooks and in the API: written out, since colctl, compiled ahead of time, keeps no
    /// names of enum values.</summary>
    public static string Id(this CodingAgent agent) => agent switch
    {
        CodingAgent.Claude => "claude",
        CodingAgent.Codex => "codex",
        CodingAgent.Gemini => "gemini",
        CodingAgent.Cursor => "cursor",
        _ => "copilot",
    };

    public static string Name(this CodingAgent agent) => agent switch
    {
        CodingAgent.Claude => "Claude Code",
        CodingAgent.Codex => "Codex",
        CodingAgent.Gemini => "Gemini CLI",
        CodingAgent.Cursor => "Cursor",
        _ => "GitHub Copilot (VS Code)",
    };

    /// <summary>The file name of the agent's logo among the app's marks.</summary>
    public static string Mark(this CodingAgent agent) => agent switch
    {
        CodingAgent.Claude => "claude",
        CodingAgent.Codex => "codex",
        CodingAgent.Gemini => "gemini",
        CodingAgent.Cursor => "cursor",
        _ => "githubcopilot",
    };

    /// <summary>The agent's colour, close to its maker's own.</summary>
    public static Rgba Tint(this CodingAgent agent) => agent switch
    {
        CodingAgent.Claude => new Rgba(0.85, 0.47, 0.34),
        CodingAgent.Codex => new Rgba(0.42, 0.45, 0.5),
        CodingAgent.Gemini => new Rgba(0.26, 0.52, 0.96),
        CodingAgent.Cursor => new Rgba(0.55, 0.55, 0.6),
        _ => new Rgba(0.47, 0.36, 0.95),
    };

    /// <summary>Agents whose hooks can wait for an answer: their permission requests get Allow and Deny in the island.
    /// The others say they need the user, who answers in the agent itself.</summary>
    public static bool AnswersPermissions(this CodingAgent agent) => agent is CodingAgent.Claude or CodingAgent.Codex;

    /// <summary>False for an agent that never says a session is over: VS Code sends no event when a Copilot chat ends.</summary>
    public static bool EndsSessions(this CodingAgent agent) => agent != CodingAgent.Copilot;

    public static CodingAgent? FromId(string? id) => id switch
    {
        "claude" => CodingAgent.Claude,
        "codex" => CodingAgent.Codex,
        "gemini" => CodingAgent.Gemini,
        "cursor" => CodingAgent.Cursor,
        "copilot" => CodingAgent.Copilot,
        _ => null,
    };

    /// <summary>The agent behind a session, from the name the session keeps.</summary>
    public static CodingAgent? Named(string? name) =>
        Enum.GetValues<CodingAgent>().Cast<CodingAgent?>().FirstOrDefault(a => a!.Value.Name() == name);

    /// <summary>Turns one hook payload, as this agent wrote it, into an event. Null for events Col does not follow.</summary>
    public static HookEvent? EventFrom(this CodingAgent agent, JsonObject raw)
    {
        string? Text(string key) => raw[key] is JsonValue value && value.TryGetValue(out string? text) ? text : null;
        switch (agent)
        {
            case CodingAgent.Claude:
            case CodingAgent.Codex:
            {
                var session = Text("session_id");
                var name = Text("hook_event_name");
                if (session is null || name is null) return null;
                return new HookEvent(session, name)
                {
                    Cwd = Text("cwd"), ToolName = Text("tool_name"), ToolInput = raw["tool_input"] as JsonObject,
                    NotificationType = Text("notification_type"), Message = Text("message"), AgentName = Text("agent_name"),
                    Agent = Text("agent_name") is null ? agent : null,
                };
            }
            case CodingAgent.Gemini:
            {
                var events = new Dictionary<string, string>
                {
                    ["SessionStart"] = "SessionStart", ["SessionEnd"] = "SessionEnd", ["BeforeAgent"] = "UserPromptSubmit",
                    ["BeforeTool"] = "PreToolUse", ["AfterTool"] = "PostToolUse", ["AfterAgent"] = "Stop", ["Notification"] = "Notification",
                };
                var session = Text("session_id");
                var name = Text("hook_event_name") is { } raw1 && events.TryGetValue(raw1, out var mapped) ? mapped : null;
                if (session is null || name is null) return null;
                // Gemini asks for a tool's confirmation in the terminal and tells its hooks with a ToolPermission notice.
                var notice = Text("notification_type") == "ToolPermission" ? "permission_prompt" : Text("notification_type");
                return new HookEvent(session, name)
                {
                    Cwd = Text("cwd"), ToolName = Text("tool_name"), ToolInput = raw["tool_input"] as JsonObject,
                    NotificationType = notice, Message = Text("message"), Agent = agent,
                };
            }
            case CodingAgent.Cursor:
            {
                var session = Text("conversation_id");
                var name = Text("hook_event_name");
                if (session is null || name is null) return null;
                var roots = raw["workspace_roots"] as JsonArray;
                var cwd = roots?.FirstOrDefault() is JsonValue root && root.TryGetValue(out string? first) ? first : Text("cwd");
                var @event = new HookEvent(session, "") { Cwd = cwd, Agent = agent };
                return name switch
                {
                    "sessionStart" => @event with { Event = "SessionStart" },
                    "sessionEnd" => @event with { Event = "SessionEnd" },
                    "beforeSubmitPrompt" => @event with { Event = "UserPromptSubmit" },
                    "stop" => @event with { Event = "Stop" },
                    "postToolUse" => @event with { Event = "PostToolUse", ToolName = Text("tool_name"), ToolInput = raw["tool_input"] as JsonObject },
                    "afterShellExecution" => @event with
                    {
                        Event = "PostToolUse", ToolName = "Shell",
                        ToolInput = Text("command") is { } command ? new JsonObject { ["command"] = command } : null,
                    },
                    "afterFileEdit" => @event with
                    {
                        Event = "PostToolUse", ToolName = "Edit",
                        ToolInput = Text("file_path") is { } file ? new JsonObject { ["file_path"] = file } : null,
                    },
                    _ => null,
                };
            }
            default:
            {
                // VS Code's own hooks (the Local agent). The cwd is the workspace's first folder.
                var name = Text("hook_event_name");
                if (name is null) return null;
                var session = Text("session_id") ?? Text("transcript_path") ?? Text("cwd") ?? "vscode-copilot";
                return new HookEvent(session, name)
                {
                    Cwd = Text("cwd"), ToolName = Text("tool_name"), ToolInput = raw["tool_input"] as JsonObject,
                    Message = Text("message"), Agent = agent,
                };
            }
        }
    }
}
