using System.Text.Json.Nodes;

namespace Col.Core;

/// <summary>Where each agent keeps its hooks and how it reads their answers.</summary>
public enum HookFormat
{
    /// <summary>Claude Code and Codex: hooks under "hooks", by event, in matcher groups.</summary>
    Claude,
    Gemini,
    Cursor,
    VSCode,
}

/// <summary>
/// What <c>colctl hook</c> answers the agent that called it. It never gets in the agent's way: when Col is not running,
/// or anything goes wrong, it answers what "carry on as usual" means for that agent and exits 0.
/// </summary>
public static class HookRelay
{
    public static HookFormat Format(this CodingAgent agent) => agent switch
    {
        CodingAgent.Gemini => HookFormat.Gemini,
        CodingAgent.Cursor => HookFormat.Cursor,
        CodingAgent.Copilot => HookFormat.VSCode,
        _ => HookFormat.Claude,
    };

    /// <summary>
    /// What the agent wrote on stdin, without what some writers add around JSON: a UTF-8 byte order mark before or
    /// after it (Windows PowerShell's pipes add one when they close), line breaks, spaces and NULs.
    /// </summary>
    public static byte[] Clean(ReadOnlySpan<byte> input)
    {
        ReadOnlySpan<byte> bom = [0xEF, 0xBB, 0xBF];
        var changed = true;
        while (changed)
        {
            changed = false;
            if (input.StartsWith(bom)) { input = input[3..]; changed = true; }
            if (input.EndsWith(bom)) { input = input[..^3]; changed = true; }
            while (input.Length > 0 && input[0] is (byte)' ' or (byte)'\t' or (byte)'\r' or (byte)'\n' or 0) { input = input[1..]; changed = true; }
            while (input.Length > 0 && input[^1] is (byte)' ' or (byte)'\t' or (byte)'\r' or (byte)'\n' or 0) { input = input[..^1]; changed = true; }
        }
        return input.ToArray();
    }

    /// <summary>The event's name, read from what the agent wrote on stdin; empty when it is not a JSON object.</summary>
    public static string EventName(ReadOnlySpan<byte> input)
    {
        try
        {
            return JsonNode.Parse(input) is JsonObject json && json["hook_event_name"] is JsonValue value &&
                   value.TryGetValue(out string? name) ? name : "";
        }
        catch (Exception)
        {
            return "";
        }
    }

    /// <summary>Whether the input is a JSON object at all: anything else is not forwarded.</summary>
    public static bool IsEvent(ReadOnlySpan<byte> input)
    {
        try { return JsonNode.Parse(input) is JsonObject json && json.Count > 0; }
        catch (Exception) { return false; }
    }

    /// <summary>The answer that changes nothing: Gemini CLI and Cursor read a JSON answer from every hook, and Cursor's
    /// prompt hook must let the prompt through. Null when the agent reads nothing.</summary>
    public static string? Neutral(CodingAgent agent, string eventName) => agent.Format() switch
    {
        HookFormat.Gemini => "{}",
        HookFormat.Cursor => eventName == "beforeSubmitPrompt" ? """{"continue":true}""" : "{}",
        HookFormat.VSCode => eventName == "PreToolUse" ? "{}" : null,
        _ => null,
    };

    /// <summary>Whether this event waits for the user's answer in the island.</summary>
    public static bool Waits(CodingAgent agent, string eventName) => agent.AnswersPermissions() && eventName == "PermissionRequest";

    /// <summary>How long the hook waits for Col's answer: a permission request waits for the user (Col itself gives up
    /// after 90 seconds), anything else only for the app to take it in.</summary>
    public static TimeSpan AnswerTimeout(bool waits) => waits ? TimeSpan.FromSeconds(110) : TimeSpan.FromSeconds(3);

    /// <summary>
    /// The hook's output for Col's answer to a permission request, exactly as Claude Code and Codex read it; null for
    /// anything but allow or deny, so the agent asks in the terminal as usual.
    /// </summary>
    public static string? PermissionOutput(string? decision)
    {
        if (decision is not ("allow" or "deny")) return null;
        var verdict = new JsonObject { ["behavior"] = decision };
        if (decision == "deny") verdict["message"] = "Denied from Col.";
        var output = new JsonObject
        {
            ["hookSpecificOutput"] = new JsonObject { ["hookEventName"] = "PermissionRequest", ["decision"] = verdict },
        };
        return output.ToJsonString();
    }

    /// <summary>The decision in Col's answer to <c>POST /v1/agents/events</c>, or null.</summary>
    public static string? DecisionFrom(ReadOnlySpan<byte> body)
    {
        try
        {
            return JsonNode.Parse(body) is JsonObject json && json["decision"] is JsonValue value &&
                   value.TryGetValue(out string? decision) ? decision : null;
        }
        catch (Exception)
        {
            return null;
        }
    }

    public static string Name(this Decision decision) => decision switch
    {
        Decision.Allow => "allow",
        Decision.Deny => "deny",
        _ => "ask",
    };
}
