namespace Col.Native;

/// <summary>
/// Tells when a full-screen app (a video, a game, a presentation) covers the island's monitor. Explorer says so to
/// registered app bars, and Windows says when another window comes to the front; nothing is polled.
/// </summary>
internal sealed class FullScreenWatcher : IDisposable
{
    private readonly IntPtr _window;
    private readonly int _message;
    private readonly Win32.WinEventProc _foregroundChanged;
    private IntPtr _hook;
    private bool _registered;
    private Func<Win32.RECT>? _monitor;

    public bool IsFullScreen { get; private set; }
    public event Action<bool>? Changed;

    public FullScreenWatcher(IntPtr window)
    {
        _window = window;
        _message = Win32.RegisterWindowMessage("Col.AppBar");
        _foregroundChanged = (_, _, _, _, _, _, _) => Check();
    }

    /// <summary>The message Explorer sends to the island's window.</summary>
    public int Message => _message;

    public void Start(Func<Win32.RECT> monitor)
    {
        _monitor = monitor;
        var data = new Win32.APPBARDATA
        {
            cbSize = System.Runtime.InteropServices.Marshal.SizeOf<Win32.APPBARDATA>(),
            hWnd = _window,
            uCallbackMessage = _message,
        };
        // Registered, never given room: Col reserves no space at the edge of the screen.
        _registered = Win32.SHAppBarMessage(Win32.ABM_NEW, ref data) != UIntPtr.Zero;
        _hook = Win32.SetWinEventHook(Win32.EVENT_SYSTEM_FOREGROUND, Win32.EVENT_SYSTEM_FOREGROUND, IntPtr.Zero,
            _foregroundChanged, 0, 0, Win32.WINEVENT_OUTOFCONTEXT | Win32.WINEVENT_SKIPOWNPROCESS);
        Check();
    }

    /// <summary>Called from the island's window procedure for <see cref="Message"/>.</summary>
    public void OnAppBarMessage(IntPtr wParam)
    {
        if (wParam.ToInt64() == Win32.ABN_FULLSCREENAPP) Check();
    }

    public void Check()
    {
        if (_monitor is null) return;
        var full = CoversMonitor(Win32.GetForegroundWindow(), _monitor());
        if (full == IsFullScreen) return;
        IsFullScreen = full;
        Changed?.Invoke(full);
    }

    /// <summary>Whether a window covers a whole monitor: the desktop and the shell's own windows never count.</summary>
    private bool CoversMonitor(IntPtr hwnd, Win32.RECT monitor)
    {
        if (hwnd == IntPtr.Zero || hwnd == _window || hwnd == Win32.GetShellWindow() || hwnd == Win32.GetDesktopWindow()) return false;
        var name = Win32.ClassName(hwnd);
        if (name is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd" or "Windows.UI.Core.CoreWindow") return false;
        // A window with a title bar is a maximised window, not a full-screen one, even over a taskbar that hides.
        const long caption = 0x00C00000;
        if ((Win32.GetWindowLongPtr(hwnd, -16).ToInt64() & caption) == caption) return false;
        if (!Win32.GetWindowRect(hwnd, out var rect)) return false;
        return rect.Left <= monitor.Left && rect.Top <= monitor.Top && rect.Right >= monitor.Right && rect.Bottom >= monitor.Bottom;
    }

    public void Dispose()
    {
        if (_hook != IntPtr.Zero) Win32.UnhookWinEvent(_hook);
        _hook = IntPtr.Zero;
        if (!_registered) return;
        var data = new Win32.APPBARDATA
        {
            cbSize = System.Runtime.InteropServices.Marshal.SizeOf<Win32.APPBARDATA>(),
            hWnd = _window,
        };
        Win32.SHAppBarMessage(Win32.ABM_REMOVE, ref data);
        _registered = false;
    }
}
