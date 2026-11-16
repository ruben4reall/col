using System.Text.Json;
using System.Text.Json.Serialization;

namespace Col.Core;

/// <summary>
/// Col's settings, kept in %LOCALAPPDATA%\Col\settings.json. Launch at login is not here: Windows keeps it, in the
/// user's Run key, and Col reads it from there.
/// </summary>
public sealed class ColSettings
{
    public int Version { get; set; } = 1;
    /// <summary>The monitor the island lives on: "primary", or a monitor's device name such as \\.\DISPLAY2.</summary>
    public string Monitor { get; set; } = "primary";
    /// <summary>False (the default): the island only shows when something happens, and comes out on hover at the top
    /// edge. True: a small pill stays at the top of the screen.</summary>
    public bool VisibleAtRest { get; set; }
    public IslandSize Size { get; set; } = IslandSize.Standard;
    /// <summary>Resting on the island opens it; off, it opens on a click only.</summary>
    public bool OpenOnHover { get; set; } = true;
    public bool NowPlaying { get; set; } = true;
    /// <summary>Synced lyrics from LRCLIB, beside the player.</summary>
    public bool Lyrics { get; set; } = true;
    /// <summary>The line being sung, in the closed island.</summary>
    public bool LyricLineClosed { get; set; }
    public bool VolumeDisplay { get; set; } = true;
    public bool BatteryDisplay { get; set; } = true;
    public bool ClipboardHistory { get; set; } = true;

    public ColSettings Copy() => (ColSettings)MemberwiseClone();

    public static ColSettings Load(string path)
    {
        try
        {
            if (!File.Exists(path)) return new ColSettings();
            return JsonSerializer.Deserialize(File.ReadAllBytes(path), SettingsJson.Default.ColSettings) ?? new ColSettings();
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or NotSupportedException)
        {
            return new ColSettings();
        }
    }

    public void Save(string path)
    {
        try
        {
            var folder = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(folder)) Directory.CreateDirectory(folder);
            var partial = path + ".partial";
            File.WriteAllBytes(partial, JsonSerializer.SerializeToUtf8Bytes(this, SettingsJson.Default.ColSettings));
            File.Move(partial, path, overwrite: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // Kept in memory for this run.
        }
    }
}

[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    UseStringEnumConverter = true, ReadCommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true)]
[JsonSerializable(typeof(ColSettings))]
internal sealed partial class SettingsJson : JsonSerializerContext;
