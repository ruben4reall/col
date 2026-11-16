using System.Text.Json.Nodes;
using Col.Core;

namespace Col.Tests;

public sealed class HooksInstallerTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), "col-hooks-" + Guid.NewGuid().ToString("N"));
    private const string Colctl = @"C:\Users\Jane Doe\AppData\Local\Programs\Col\colctl.exe";

    public HooksInstallerTests() => Directory.CreateDirectory(_folder);

    public void Dispose() => Directory.Delete(_folder, recursive: true);

    private string Settings => Path.Combine(_folder, ".claude", "settings.json");

    private JsonObject Read() => (JsonObject)JsonNode.Parse(File.ReadAllText(Settings))!;

    [Fact]
    public void TheCommandWorksInGitBashAndCmdAlike()
    {
        Assert.Equal("\"C:/Users/Jane Doe/AppData/Local/Programs/Col/colctl.exe\" hook", HooksInstaller.Command(HooksInstaller.Claude, Colctl));
        Assert.Equal("\"C:/Users/Jane Doe/AppData/Local/Programs/Col/colctl.exe\" hook --agent codex", HooksInstaller.Command(HooksInstaller.Codex, Colctl));
        Assert.True(HooksInstaller.CallsCol(HooksInstaller.Command(HooksInstaller.Claude, Colctl)));
        Assert.True(HooksInstaller.CallsCol("colctl hook --agent codex"));
        Assert.True(HooksInstaller.CallsCol("\"$HOME/.local/bin/colctl\" hook"));
        Assert.False(HooksInstaller.CallsCol("colctl hooks status"));
        Assert.False(HooksInstaller.CallsCol("my-linter --fix"));
    }

    [Fact]
    public void InstallsIntoANewFile()
    {
        var message = HooksInstaller.Edit(HooksInstaller.Claude, Settings, install: true, Colctl);
        Assert.Contains("hooks installed", message);
        var hooks = (JsonObject)Read()["hooks"]!;
        Assert.Equal(HooksInstaller.Claude.Events.Select(e => e.Name).Order(), hooks.Select(p => p.Key).Order());
        var permission = (JsonObject)hooks["PermissionRequest"]![0]!;
        Assert.Equal("*", (string?)permission["matcher"]);
        var hook = (JsonObject)permission["hooks"]![0]!;
        Assert.Equal("command", (string?)hook["type"]);
        Assert.Equal(120, (int)hook["timeout"]!);
        Assert.Null(((JsonObject)hooks["Stop"]![0]!)["matcher"]);
        Assert.True(HooksInstaller.IsConnected(Settings));
        Assert.False(File.Exists(Settings + ".col-backup"));
    }

    [Fact]
    public void KeepsTheUsersSettingsAndHooksAndABackup()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Settings)!);
        var original = """
            {
              "model": "opus",
              "permissions": { "allow": ["Bash(git status)"] },
              "hooks": {
                "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "my-guard.exe" } ] } ],
                "Stop": [ { "hooks": [ { "type": "command", "command": "\"C:/old/colctl.exe\" hook" } ] } ]
              }
            }
            """;
        File.WriteAllText(Settings, original);
        HooksInstaller.Edit(HooksInstaller.Claude, Settings, install: true, Colctl);
        var settings = Read();
        Assert.Equal("opus", (string?)settings["model"]);
        Assert.Equal("Bash(git status)", (string?)settings["permissions"]!["allow"]![0]);
        // The user's own hook stays first; Col's comes after it.
        var pre = (JsonArray)settings["hooks"]!["PreToolUse"]!;
        Assert.Equal(2, pre.Count);
        Assert.Equal("my-guard.exe", (string?)pre[0]!["hooks"]![0]!["command"]);
        // An older Col hook is replaced, never doubled.
        var stop = (JsonArray)settings["hooks"]!["Stop"]!;
        Assert.Single(stop);
        Assert.Contains("Programs/Col/colctl.exe", (string?)stop[0]!["hooks"]![0]!["command"]);
        Assert.Equal(original, File.ReadAllText(Settings + ".col-backup"));
        // The keys keep their order.
        Assert.Equal(["model", "permissions", "hooks"], settings.Select(p => p.Key).ToArray());

        // Installing twice changes nothing.
        var once = File.ReadAllText(Settings);
        HooksInstaller.Edit(HooksInstaller.Claude, Settings, install: true, Colctl);
        Assert.Equal(once, File.ReadAllText(Settings));

        // Uninstalling leaves only the user's.
        HooksInstaller.Edit(HooksInstaller.Claude, Settings, install: false, Colctl);
        settings = Read();
        Assert.False(HooksInstaller.IsConnected(Settings));
        var hooks = (JsonObject)settings["hooks"]!;
        Assert.Equal(["PreToolUse"], hooks.Select(p => p.Key).ToArray());
        Assert.Equal("opus", (string?)settings["model"]);
    }

    [Fact]
    public void UninstallingEverythingRemovesTheHooksKey()
    {
        HooksInstaller.Edit(HooksInstaller.Claude, Settings, install: true, Colctl);
        HooksInstaller.Edit(HooksInstaller.Claude, Settings, install: false, Colctl);
        Assert.Null(Read()["hooks"]);
        Assert.Contains("nothing to remove", HooksInstaller.Edit(HooksInstaller.Codex, Path.Combine(_folder, "none.json"), install: false, Colctl));
    }

    [Fact]
    public void AFileThatIsNotJsonIsLeftUntouched()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Settings)!);
        File.WriteAllText(Settings, "{ \"model\": \"opus\", // a comment\n }");
        var error = Assert.Throws<HooksException>(() => HooksInstaller.Edit(HooksInstaller.Claude, Settings, install: true, Colctl));
        Assert.Contains("left untouched", error.Message);
        Assert.Equal("{ \"model\": \"opus\", // a comment\n }", File.ReadAllText(Settings));
        Assert.False(File.Exists(Settings + ".col-backup"));
    }

    [Fact]
    public void ABomFromNotepadIsRead()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Settings)!);
        File.WriteAllText(Settings, "{\"model\":\"opus\"}", new System.Text.UTF8Encoding(encoderShouldEmitUTF8Identifier: true));
        HooksInstaller.Edit(HooksInstaller.Claude, Settings, install: true, Colctl);
        Assert.Equal("opus", (string?)Read()["model"]);
    }

    [Fact]
    public void CodexHooksGoToItsOwnFileWithoutMatchers()
    {
        var path = HooksInstaller.Codex.SettingsPath(_folder);
        Assert.EndsWith(Path.Combine(".codex", "hooks.json"), path);
        var message = HooksInstaller.Edit(HooksInstaller.Codex, path, install: true, Colctl);
        Assert.Contains("/hooks", message);
        var hooks = (JsonObject)JsonNode.Parse(File.ReadAllText(path))!["hooks"]!;
        Assert.All(hooks, pair => Assert.Null(pair.Value![0]!["matcher"]));
        Assert.EndsWith("hook --agent codex", (string?)hooks["Stop"]![0]!["hooks"]![0]!["command"]);
    }

    [Fact]
    public void OnlyAgentsOnThisPcAreConnectedWithAll()
    {
        Assert.False(HooksInstaller.IsInstalled(HooksInstaller.Codex, _folder));
        Directory.CreateDirectory(Path.Combine(_folder, ".codex"));
        Assert.True(HooksInstaller.IsInstalled(HooksInstaller.Codex, _folder));
        Assert.Equal(HooksInstaller.Codex, HooksInstaller.Named("codex"));
        Assert.Null(HooksInstaller.Named("gemini"));
    }
}
