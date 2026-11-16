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
    Start-Sleep -Seconds 1
}

function Save-Screen([string] $Path, [switch] $Full, [switch] $Zoom) {
    $width = [ColDesktop]::GetSystemMetrics(0)
    $height = [ColDesktop]::GetSystemMetrics(1)
    if ($Full) { $x = 0; $y = 0; $w = $width; $h = $height }
    elseif ($Zoom) { $w = 720; $h = 280; $x = [int](($width - $w) / 2); $y = 0 }
    else { $x = 0; $y = 0; $w = $width; $h = 320 }
    $bitmap = New-Object System.Drawing.Bitmap $w, $h
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    # CaptureBlt: layered windows, the island among them, are part of the capture.
    $operation = [System.Drawing.CopyPixelOperation]::SourceCopy -bor [System.Drawing.CopyPixelOperation]::CaptureBlt
    $graphics.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size $w, $h), $operation)
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
