<#
  Helpers for the screenshots on a build machine: a 1920 by 1080 desktop with a light wallpaper (so the black island
  stands out), and captures of the top of the screen. Dot-sourced by screenshots.ps1 and e2e.ps1.
#>

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ColDesktop
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields;
        public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplaySettings(string device, int mode, ref DEVMODE devMode);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int ChangeDisplaySettings(ref DEVMODE devMode, int flags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool SystemParametersInfo(int action, int param, string value, int flags);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll")]
    public static extern void mouse_event(int flags, int dx, int dy, int data, IntPtr extra);

    /// <summary>Moves the pointer as a mouse would: through the input stream, which low-level hooks see.</summary>
    public static void MoveTo(int x, int y)
    {
        int width = GetSystemMetrics(0), height = GetSystemMetrics(1);
        // MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE, in 0 to 65535 across the screen.
        mouse_event(0x8001, (x * 65535 + width / 2) / (width - 1), (y * 65535 + height / 2) / (height - 1), 0, IntPtr.Zero);
    }

    public static void Click()
    {
        mouse_event(0x0002, 0, 0, 0, IntPtr.Zero);
        System.Threading.Thread.Sleep(30);
        mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);
    }

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT point);

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    [DllImport("user32.dll")]
    public static extern IntPtr GetDC(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);

    [DllImport("gdi32.dll")]
    public static extern bool BitBlt(IntPtr dest, int x, int y, int width, int height, IntPtr source, int sx, int sy, int operation);

    /// <summary>Copies part of the screen, layered windows included (CAPTUREBLT), into a device context.</summary>
    public static bool Capture(IntPtr target, int x, int y, int width, int height)
    {
        var screen = GetDC(IntPtr.Zero);
        var copied = BitBlt(target, 0, 0, width, height, screen, x, y, 0x00CC0020 | 0x40000000);
        ReleaseDC(IntPtr.Zero, screen);
        return copied;
    }

    public static int SetResolution(int width, int height)
    {
        var mode = new DEVMODE();
        mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (!EnumDisplaySettings(null, -1, ref mode)) return -100;
        mode.dmPelsWidth = width;
        mode.dmPelsHeight = height;
        mode.dmFields = 0x80000 | 0x100000;
        return ChangeDisplaySettings(ref mode, 0);
    }
}
'@

function Initialize-Desktop([string] $Out) {
    [ColDesktop]::SetProcessDPIAware() | Out-Null
    $result = [ColDesktop]::SetResolution(1920, 1080)
    Write-Host "Resolution change: $result, screen $([ColDesktop]::GetSystemMetrics(0)) x $([ColDesktop]::GetSystemMetrics(1))"

    # A light wallpaper, a sky that darkens toward the bottom, so the island's black and its edges show.
    $width = [ColDesktop]::GetSystemMetrics(0)
    $height = [ColDesktop]::GetSystemMetrics(1)
    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $rect = New-Object System.Drawing.Rectangle 0, 0, $width, $height
    $top = [System.Drawing.Color]::FromArgb(0xDC, 0xE8, 0xF7)
    $bottom = [System.Drawing.Color]::FromArgb(0x5B, 0x7F, 0xB5)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $top, $bottom, 90
    $graphics.FillRectangle($brush, $rect)
    $graphics.Dispose()
    $wallpaper = Join-Path $Out 'wallpaper.bmp'
    $bitmap.Save($wallpaper, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $bitmap.Dispose()
    # SPI_SETDESKWALLPAPER, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE.
    [ColDesktop]::SystemParametersInfo(0x14, 0, $wallpaper, 3) | Out-Null
    # The build machine's own console windows out of the way.
    try { (New-Object -ComObject Shell.Application).MinimizeAll() } catch { Write-Host "MinimizeAll: $_" }
    Start-Sleep -Seconds 2
}

# Why a .NET app quit: the runtime writes the exception to the Application event log.
function Show-Crash {
    try {
        Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = '.NET Runtime', 'Application Error' } -MaxEvents 2 -ErrorAction Stop |
            ForEach-Object { Write-Host "--- $($_.ProviderName) $($_.TimeCreated)"; Write-Host $_.Message }
    }
    catch {
        Write-Host "No event: $_"
    }
}

function Save-Screen([string] $Path, [switch] $Full, [switch] $Zoom) {
    $width = [ColDesktop]::GetSystemMetrics(0)
    $height = [ColDesktop]::GetSystemMetrics(1)
    if ($Full) { $x = 0; $y = 0; $w = $width; $h = $height }
    elseif ($Zoom) { $w = 720; $h = 280; $x = [int](($width - $w) / 2); $y = 0 }
    else { $x = 0; $y = 0; $w = $width; $h = 320 }
    $bitmap = New-Object System.Drawing.Bitmap $w, $h
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $target = $graphics.GetHdc()
    [ColDesktop]::Capture($target, $x, $y, $w, $h) | Out-Null
    $graphics.ReleaseHdc($target)
    $graphics.Dispose()
    if ($Zoom) {
        # Twice as big, without smoothing, to judge the edges pixel by pixel.
        $large = New-Object System.Drawing.Bitmap ($w * 2), ($h * 2)
        $draw = [System.Drawing.Graphics]::FromImage($large)
        $draw.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $draw.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        $draw.DrawImage($bitmap, 0, 0, $w * 2, $h * 2)
        $draw.Dispose()
        $bitmap.Dispose()
        $bitmap = $large
    }
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
}
