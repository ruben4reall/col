using System.Text.Json.Nodes;

namespace Col.Core;

/// <summary>
/// States the island can be put in with fake data, so screenshots are the same every time: <c>Col.exe --demo music</c>.
/// Nothing real is read in a demo (no media, no clipboard, no agents), and nothing is written.
/// </summary>
public enum DemoState
{
    Collapsed,
    Peek,
    Music,
    Lyrics,
    AgentPermission,
    Agents,
    Volume,
    Battery,
    Timer,
    Tools,
    Settings,
}

public static class Demo
{
    public static string Id(this DemoState state) => state switch
    {
        DemoState.AgentPermission => "agent-permission",
        _ => state.ToString().ToLowerInvariant(),
    };

    public static DemoState? Parse(string? text) =>
        Enum.GetValues<DemoState>().Cast<DemoState?>().FirstOrDefault(s => s!.Value.Id() == text?.Trim().ToLowerInvariant());

    /// <summary>The demo states, as the command line names them.</summary>
    public static IReadOnlyList<string> Names => Enum.GetValues<DemoState>().Select(s => s.Id()).ToList();

    /// <summary>A song made up for the demos, so no one's work is shown.</summary>
    public static NowPlaying Track(DateTimeOffset now, double position = 71) => new()
    {
        IsPlaying = true,
        Title = "Midnight Pass",
        Artist = "The Harbour Lights",
        Album = "Coastline",
        Duration = 214,
        Elapsed = position,
        Reported = now,
        Rate = 1,
        Source = "Demo",
    };

    /// <summary>Its words, written for the demo.</summary>
    public const string TrackLyrics = """
        [00:52.00]Streetlights hum along the bay
        [00:56.50]Every road runs out to sea
        [01:01.00]I kept the map you threw away
        [01:05.50]It only ever pointed here
        [01:10.00]We climb the pass at midnight
        [01:14.50]With the city at our backs
        [01:19.00]Two small lights on the mountain
        [01:23.50]Waiting for the dawn to crack
        [01:28.00]Hold on, hold on
        [01:32.50]The summit's just a breath away
        """;

    /// <summary>A permission request from Claude Code, as its hook writes it.</summary>
    public static JsonObject PermissionRequest() => new()
    {
        ["session_id"] = "demo-session",
        ["hook_event_name"] = "PermissionRequest",
        ["cwd"] = @"C:\Users\demo\code\col",
        ["tool_name"] = "Bash",
        ["tool_input"] = new JsonObject
        {
            ["command"] = "git push origin main",
            ["description"] = "Push the branch",
        },
    };

    /// <summary>Two agents at work, for the Live page.</summary>
    public static IReadOnlyList<HookEvent> WorkingAgents() =>
    [
        new HookEvent("demo-claude", "PreToolUse")
        {
            Cwd = @"C:\Users\demo\code\col", ToolName = "Bash",
            ToolInput = new JsonObject { ["command"] = "dotnet test windows\\Col.sln" }, Agent = CodingAgent.Claude,
        },
        new HookEvent("demo-codex", "PreToolUse")
        {
            Cwd = @"C:\Users\demo\code\site", ToolName = "Edit",
            ToolInput = new JsonObject { ["file_path"] = @"C:\Users\demo\code\site\index.html" }, Agent = CodingAgent.Codex,
        },
    ];

    /// <summary>A few copies for the clipboard history: nothing of the user's.</summary>
    public static IReadOnlyList<string> Copies =>
    [
        "colctl push build --title Build --progress 40%",
        "https://github.com/ruben4reall/col",
        "Meeting moved to 15:30, same room.",
        "winget install --id Git.Git",
    ];
}
