namespace Col.Native;

/// <summary>One monitor: its full area in physical pixels, its scale, and the name Windows gives it.</summary>
internal sealed record Monitor(IntPtr Handle, string Device, Win32.RECT Bounds, Win32.RECT WorkArea, bool IsPrimary, double Scale)
{
    /// <summary>"Display 2", as Windows' Settings number them.</summary>
    public string Number
    {
        get
        {
            var digits = new string(Device.Where(char.IsDigit).ToArray());
            return digits.Length > 0 ? digits : "1";
        }
    }
}

internal static class Monitors
{
    public static IReadOnlyList<Monitor> All()
    {
        var list = new List<Monitor>();
        Win32.MonitorEnumProc callback = (IntPtr handle, IntPtr hdc, ref Win32.RECT rect, IntPtr data) =>
        {
            if (Describe(handle) is { } monitor) list.Add(monitor);
            return true;
        };
        Win32.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero);
        GC.KeepAlive(callback);
        return list.OrderByDescending(m => m.IsPrimary).ThenBy(m => m.Bounds.Left).ToList();
    }

    public static Monitor? Describe(IntPtr handle)
    {
        var info = new Win32.MONITORINFOEX { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<Win32.MONITORINFOEX>() };
        if (!Win32.GetMonitorInfo(handle, ref info)) return null;
        double scale = 1;
        try
        {
            // MDT_EFFECTIVE_DPI: the scale chosen in Settings, Display.
            if (Win32.GetDpiForMonitor(handle, 0, out var dpi, out _) == 0 && dpi > 0) scale = dpi / 96.0;
        }
        catch (DllNotFoundException)
        {
        }
        return new Monitor(handle, info.szDevice ?? "", info.rcMonitor, info.rcWork, (info.dwFlags & Win32.MONITORINFOF_PRIMARY) != 0, scale);
    }

    /// <summary>The monitor the settings name, or the primary one when it is not connected.</summary>
    public static Monitor? Chosen(string setting)
    {
        var all = All();
        return all.FirstOrDefault(m => !string.Equals(setting, "primary", StringComparison.OrdinalIgnoreCase) &&
                                       string.Equals(m.Device, setting, StringComparison.OrdinalIgnoreCase))
               ?? all.FirstOrDefault(m => m.IsPrimary)
               ?? all.FirstOrDefault();
    }
}
