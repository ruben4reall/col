using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace Col.Native;

/// <summary>A menu item of Col's own menus: an id, its text, and whether it is on.</summary>
internal sealed record MenuEntry(int Id, string Text, bool Checked = false, bool Enabled = true)
{
    public static readonly MenuEntry Separator = new(0, "");
}

/// <summary>
/// Col's icon in the notification area: a click opens the settings, a right-click shows Open Settings and Quit. Drawn
/// by the shell itself; Col only hands it an icon and answers its messages, on a hidden window of its own.
/// </summary>
internal sealed class TrayIcon : IDisposable
{
    private const int CallbackMessage = Win32.WM_APP + 1;
    private readonly HwndSource _window;
    private readonly int _taskbarCreated;
    private IntPtr _icon;
    private bool _added;
    private string _tip;

    public event Action? Clicked;
    /// <summary>Asks for the menu's items when the menu opens.</summary>
    public Func<IReadOnlyList<MenuEntry>>? MenuEntries { get; set; }
    public event Action<int>? MenuChosen;

    public TrayIcon(string tip)
    {
        _tip = tip;
        var parameters = new HwndSourceParameters("Col.Tray")
        {
            Width = 0,
            Height = 0,
            WindowStyle = 0,
            ExtendedWindowStyle = (int)Win32.WS_EX_TOOLWINDOW,
        };
        _window = new HwndSource(parameters);
        _window.AddHook(Hook);
        _taskbarCreated = Win32.RegisterWindowMessage("TaskbarCreated");
        _icon = LoadIcon();
        Add();
    }

    public IntPtr Handle => _window.Handle;

    public void SetTip(string tip)
    {
        _tip = tip;
        if (!_added) return;
        var data = Data(Win32.NIF_TIP | Win32.NIF_SHOWTIP);
        Win32.Shell_NotifyIcon(Win32.NIM_MODIFY, ref data);
    }

    private Win32.NOTIFYICONDATA Data(int flags) => new()
    {
        cbSize = Marshal.SizeOf<Win32.NOTIFYICONDATA>(),
        hWnd = _window.Handle,
        uID = 1,
        uFlags = flags,
        uCallbackMessage = CallbackMessage,
        hIcon = _icon,
        szTip = _tip.Length > 127 ? _tip[..127] : _tip,
        szInfo = "",
        szInfoTitle = "",
    };

    private void Add()
    {
        var data = Data(Win32.NIF_MESSAGE | Win32.NIF_ICON | Win32.NIF_TIP | Win32.NIF_SHOWTIP);
        _added = Win32.Shell_NotifyIcon(Win32.NIM_ADD, ref data);
        if (!_added) return;
        data.uVersion = Win32.NOTIFYICON_VERSION_4;
        Win32.Shell_NotifyIcon(Win32.NIM_SETVERSION, ref data);
    }

    private IntPtr Hook(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == _taskbarCreated && _taskbarCreated != 0)
        {
            // Explorer restarted: the icon has to be added again.
            Add();
            return IntPtr.Zero;
        }
        if (message != CallbackMessage) return IntPtr.Zero;
        // With version 4, the event is in the low word of lParam.
        var @event = (int)(lParam.ToInt64() & 0xFFFF);
        switch (@event)
        {
            case Win32.WM_LBUTTONUP:
            case Win32.NIN_SELECT:
            case Win32.NIN_KEYSELECT:
                Clicked?.Invoke();
                handled = true;
                break;
            case Win32.WM_CONTEXTMENU:
            case Win32.WM_RBUTTONUP:
                ShowMenu();
                handled = true;
                break;
        }
        return IntPtr.Zero;
    }

    /// <summary>Shows the menu at the pointer. The shell's own rule: the menu's window comes forward first, so the menu
    /// closes when the user clicks elsewhere.</summary>
    public void ShowMenu()
    {
        var items = MenuEntries?.Invoke() ?? [];
        var choice = PopUp(_window.Handle, items);
        if (choice > 0) MenuChosen?.Invoke(choice);
    }

    public static int PopUp(IntPtr owner, IReadOnlyList<MenuEntry> items)
    {
        if (items.Count == 0) return 0;
        var menu = Win32.CreatePopupMenu();
        try
        {
            foreach (var item in items)
            {
                if (item == MenuEntry.Separator || item.Id == 0)
                {
                    Win32.AppendMenu(menu, Win32.MF_SEPARATOR, UIntPtr.Zero, null);
                    continue;
                }
                var flags = Win32.MF_STRING | (item.Checked ? Win32.MF_CHECKED : 0) | (item.Enabled ? 0 : Win32.MF_GRAYED);
                Win32.AppendMenu(menu, flags, (UIntPtr)item.Id, item.Text);
            }
            Win32.GetCursorPos(out var point);
            Win32.SetForegroundWindow(owner);
            var choice = Win32.TrackPopupMenuEx(menu, Win32.TPM_RETURNCMD | Win32.TPM_RIGHTBUTTON, point.X, point.Y, owner, IntPtr.Zero);
            Win32.PostMessage(owner, Win32.WM_NULL, IntPtr.Zero, IntPtr.Zero);
            return choice;
        }
        finally
        {
            Win32.DestroyMenu(menu);
        }
    }

    /// <summary>The icon at the size of the notification area, from Col's .ico.</summary>
    private IntPtr LoadIcon()
    {
        try
        {
            var dpi = Win32.GetDpiForSystem();
            var size = Win32.GetSystemMetricsForDpi(Win32.SM_CXSMICON, dpi);
            var info = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/col.ico"));
            if (info is null) return IntPtr.Zero;
            using var stream = info.Stream;
            using var buffer = new MemoryStream();
            stream.CopyTo(buffer);
            return IconFile.Create(buffer.ToArray(), size <= 0 ? 16 : size);
        }
        catch (Exception error)
        {
            Services.Log.Write("tray icon: " + error.Message);
            return IntPtr.Zero;
        }
    }

    public void Dispose()
    {
        if (_added)
        {
            var data = Data(0);
            Win32.Shell_NotifyIcon(Win32.NIM_DELETE, ref data);
            _added = false;
        }
        if (_icon != IntPtr.Zero) Win32.DestroyIcon(_icon);
        _icon = IntPtr.Zero;
        _window.Dispose();
    }
}

/// <summary>Reads an .ico file and makes a Windows icon of the entry closest to a size.</summary>
internal static class IconFile
{
    public static IntPtr Create(byte[] ico, int size)
    {
        if (ico.Length < 6) return IntPtr.Zero;
        var count = BitConverter.ToUInt16(ico, 4);
        int bestOffset = 0, bestLength = 0, bestSize = 0;
        for (var index = 0; index < count; index++)
        {
            var entry = 6 + index * 16;
            if (entry + 16 > ico.Length) break;
            var width = ico[entry] == 0 ? 256 : ico[entry];
            var length = BitConverter.ToInt32(ico, entry + 8);
            var offset = BitConverter.ToInt32(ico, entry + 12);
            // The smallest entry at least as big as wanted, else the biggest.
            var better = bestSize == 0
                || (width >= size && (bestSize < size || width < bestSize))
                || (width < size && bestSize < size && width > bestSize);
            if (!better) continue;
            bestSize = width;
            bestOffset = offset;
            bestLength = length;
        }
        if (bestLength <= 0 || bestOffset + bestLength > ico.Length) return IntPtr.Zero;
        var bits = new byte[bestLength];
        Array.Copy(ico, bestOffset, bits, 0, bestLength);
        return Win32.CreateIconFromResourceEx(bits, (uint)bits.Length, true, 0x00030000, size, size, 0);
    }
}
