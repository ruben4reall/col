using System.Runtime.InteropServices;
using Col.Core;
using Col.Services;

namespace Col.Native;

/// <summary>
/// Tells when the pointer arrives on the wake zone at the top edge of the island's monitor, and when it leaves. No
/// window lies there, so clicks at the top edge go to the windows below (a maximised browser's tabs); the zone is
/// watched with a low-level mouse hook instead. Windows calls the hook as the pointer moves, never on a timer, and
/// it runs on a thread of its own, so a busy interface can never slow the pointer down. It reads the pointer's
/// position and whether a button is held, and keeps nothing.
/// </summary>
internal sealed class EdgeWatcher : IDisposable
{
    private readonly Win32.LowLevelMouseProc _procedure;
    private Thread? _thread;
    private uint _threadId;
    private volatile EdgeZone? _zone;
    private bool _inside;

    /// <summary>True as the pointer arrives on the zone, false as it leaves. Raised on the hook's thread.</summary>
    public event Action<bool>? Changed;

    public EdgeWatcher() => _procedure = Procedure;

    public EdgeZone? Zone
    {
        get => _zone;
        set => _zone = value;
    }

    public void Start()
    {
        if (_thread is not null) return;
        _thread = new Thread(Run) { IsBackground = true, Name = "Col top edge" };
        _thread.Start();
    }

    private void Run()
    {
        _threadId = Win32.GetCurrentThreadId();
        var hook = Win32.SetWindowsHookEx(Win32.WH_MOUSE_LL, _procedure, Win32.GetModuleHandle(null), 0);
        if (hook == IntPtr.Zero)
        {
            Log.Write($"edge: no hook ({Marshal.GetLastWin32Error()})");
            return;
        }
        // Windows calls the hook from this loop; nothing else comes to this thread.
        while (Win32.GetMessage(out _, IntPtr.Zero, 0, 0) > 0)
        {
        }
        Win32.UnhookWindowsHookEx(hook);
    }

    private IntPtr Procedure(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0 && wParam.ToInt64() == Win32.WM_MOUSEMOVE && _zone is { } zone)
        {
            // MSLLHOOKSTRUCT starts with the point, in physical pixels.
            var x = Marshal.ReadInt32(lParam, 0);
            var y = Marshal.ReadInt32(lParam, 4);
            var held = (Win32.GetAsyncKeyState(Win32.VK_LBUTTON) & 0x8000) != 0
                || (Win32.GetAsyncKeyState(Win32.VK_RBUTTON) & 0x8000) != 0
                || (Win32.GetAsyncKeyState(Win32.VK_MBUTTON) & 0x8000) != 0;
            var inside = zone.Contains(x, y, held);
            if (inside != _inside)
            {
                _inside = inside;
                Changed?.Invoke(inside);
            }
        }
        return Win32.CallNextHookEx(IntPtr.Zero, code, wParam, lParam);
    }

    public void Dispose()
    {
        if (_thread is null) return;
        Win32.PostThreadMessage(_threadId, Win32.WM_QUIT, IntPtr.Zero, IntPtr.Zero);
        _thread = null;
    }
}
