using Col.Native;
using Microsoft.Win32;
using Windows.UI.ViewManagement;

namespace Col.Services;

/// <summary>The battery, read when Windows says the power status changed (WM_POWERBROADCAST).</summary>
internal readonly record struct PowerState(bool HasBattery, int Percent, bool Charging, bool PluggedIn)
{
    public static PowerState Read()
    {
        if (!Win32.GetSystemPowerStatus(out var status)) return default;
        // BatteryFlag 128: no system battery; 255: unknown.
        var hasBattery = status.BatteryFlag != 128 && status.BatteryFlag != 255 && status.BatteryLifePercent <= 100;
        var plugged = status.ACLineStatus == 1;
        var charging = (status.BatteryFlag & 8) != 0 || (plugged && status.BatteryLifePercent < 100);
        return new PowerState(hasBattery, hasBattery ? status.BatteryLifePercent : 0, charging, plugged);
    }
}

/// <summary>Keeps the PC and its screen awake while on, the way a video player does.</summary>
internal static class KeepAwake
{
    public static bool IsOn { get; private set; }

    /// <summary>Called on the interface's thread, which lives as long as Col: the request lasts until it is turned off.</summary>
    public static void Set(bool on)
    {
        IsOn = on;
        Win32.SetThreadExecutionState(on
            ? Win32.ExecutionState.Continuous | Win32.ExecutionState.SystemRequired | Win32.ExecutionState.DisplayRequired
            : Win32.ExecutionState.Continuous);
    }
}

/// <summary>Launch at login: Col's line in the user's Run key, the one Task Manager's Startup apps lists.</summary>
internal static class StartupRegistration
{
    private const string Key = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string Name = "Col";

    public static bool IsOn
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(Key);
                return key?.GetValue(Name) is string value && value.Length > 0;
            }
            catch (Exception)
            {
                return false;
            }
        }
    }

    public static void Set(bool on)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(Key, writable: true);
            if (on) key.SetValue(Name, $"\"{AppPaths.Executable}\" --background");
            else key.DeleteValue(Name, throwOnMissingValue: false);
        }
        catch (Exception error)
        {
            Log.Write("startup: " + error.Message);
        }
    }
}

/// <summary>Whether the island animates: off when Windows' animation effects are off.</summary>
internal static class Motion
{
    private static bool? _enabled;

    public static bool Enabled => _enabled ??= SystemTheme.AnimationsOn;

    /// <summary>Read again after Windows says its settings changed.</summary>
    public static void Refresh() => _enabled = null;
}

/// <summary>Light or dark, and the accent colour chosen in Windows' Settings, Personalisation.</summary>
internal static class SystemTheme
{
    public static bool AppsAreDark
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
                return key?.GetValue("AppsUseLightTheme") is int light && light == 0;
            }
            catch (Exception)
            {
                return false;
            }
        }
    }

    /// <summary>Whether Windows plays its animations (Settings, Accessibility, Visual effects).</summary>
    public static bool AnimationsOn =>
        !Win32.SystemParametersInfo(Win32.SPI_GETCLIENTAREAANIMATION, 0, out var on, 0) || on != 0;

    private static UISettings? _settings;

    /// <summary>The accent in the shade Windows uses for it on a dark or a light surface.</summary>
    public static System.Windows.Media.Color Accent(bool dark)
    {
        try
        {
            _settings ??= new UISettings();
            var color = _settings.GetColorValue(dark ? UIColorType.AccentLight2 : UIColorType.AccentDark1);
            return System.Windows.Media.Color.FromArgb(255, color.R, color.G, color.B);
        }
        catch (Exception)
        {
            return dark ? System.Windows.Media.Color.FromRgb(0x99, 0xEB, 0xFF) : System.Windows.Media.Color.FromRgb(0x00, 0x5F, 0xB8);
        }
    }
}
