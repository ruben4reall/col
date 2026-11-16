using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Col.Localization;
using Col.Native;
using Col.Services;

namespace Col.Theme;

/// <summary>
/// The colours of the settings window, Windows 11's own for light and dark, with the user's accent colour; and its
/// Mica backdrop and dark title bar when Windows can draw them.
/// </summary>
internal static class ThemeManager
{
    public static bool IsDark { get; private set; }

    /// <summary>Whether Windows draws Mica behind windows: Windows 11 2022 update and later.</summary>
    public static bool SupportsMica => Environment.OSVersion.Version.Build >= 22621;

    public static void Apply(bool? dark = null)
    {
        IsDark = dark ?? SystemTheme.AppsAreDark;
        var resources = Application.Current.Resources;
        void Set(string key, uint argb) => resources[key] = Frozen(Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb));
        if (IsDark)
        {
            Set("Win.Background", 0xFF202020);
            Set("Win.Text", 0xFFFFFFFF);
            Set("Win.Text.Secondary", 0xC5FFFFFF);
            Set("Win.Text.Tertiary", 0x87FFFFFF);
            Set("Win.Card", SupportsMica ? 0x0DFFFFFF : 0xFF2B2B2B);
            Set("Win.Card.Stroke", 0x19000000);
            Set("Win.Control", 0x0FFFFFFF);
            Set("Win.Control.Hover", 0x15FFFFFF);
            Set("Win.Control.Stroke", 0x12FFFFFF);
            Set("Win.Control.StrokeStrong", 0x8BFFFFFF);
            Set("Win.Nav.Hover", 0x0FFFFFFF);
            Set("Win.Nav.Selected", 0x0FFFFFFF);
            Set("Win.OnAccent", 0xFF000000);
            Set("Win.Divider", 0x15FFFFFF);
            Set("Win.Success", 0xFF6CCB5F);
            Set("Win.Caution", 0xFFFCE100);
            Set("Win.Badge", 0x26FFFFFF);
        }
        else
        {
            Set("Win.Background", 0xFFF3F3F3);
            Set("Win.Text", 0xE4000000);
            Set("Win.Text.Secondary", 0x9E000000);
            Set("Win.Text.Tertiary", 0x72000000);
            Set("Win.Card", SupportsMica ? 0xB3FFFFFF : 0xFFFBFBFB);
            Set("Win.Card.Stroke", 0x0F000000);
            Set("Win.Control", 0xB3FFFFFF);
            Set("Win.Control.Hover", 0x80F9F9F9);
            Set("Win.Control.Stroke", 0x0F000000);
            Set("Win.Control.StrokeStrong", 0x72000000);
            Set("Win.Nav.Hover", 0x09000000);
            Set("Win.Nav.Selected", 0x09000000);
            Set("Win.OnAccent", 0xFFFFFFFF);
            Set("Win.Divider", 0x0F000000);
            Set("Win.Success", 0xFF0F7B0F);
            Set("Win.Caution", 0xFF9D5D00);
            Set("Win.Badge", 0x14000000);
        }
        resources["Win.Accent"] = Frozen(SystemTheme.Accent(IsDark));
        resources["Win.Str.On"] = L.Get("State_On");
        resources["Win.Str.Off"] = L.Get("State_Off");
    }

    private static SolidColorBrush Frozen(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    /// <summary>The title bar in the app's mode, and Mica behind a window whose background is transparent.</summary>
    public static void Decorate(Window window)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero) return;
        var dark = IsDark ? 1 : 0;
        Win32.DwmSetWindowAttribute(hwnd, Win32.DWMWA_USE_IMMERSIVE_DARK_MODE, ref dark, sizeof(int));
        if (!SupportsMica)
        {
            window.SetResourceReference(Window.BackgroundProperty, "Win.Background");
            return;
        }
        window.Background = Brushes.Transparent;
        if (HwndSource.FromHwnd(hwnd) is { CompositionTarget: { } target }) target.BackgroundColor = Colors.Transparent;
        var margins = new Win32.MARGINS { Left = -1, Right = -1, Top = -1, Bottom = -1 };
        Win32.DwmExtendFrameIntoClientArea(hwnd, ref margins);
        var backdrop = Win32.DWMSBT_MAINWINDOW;
        if (Win32.DwmSetWindowAttribute(hwnd, Win32.DWMWA_SYSTEMBACKDROP_TYPE, ref backdrop, sizeof(int)) != 0)
            window.SetResourceReference(Window.BackgroundProperty, "Win.Background");
    }
}
