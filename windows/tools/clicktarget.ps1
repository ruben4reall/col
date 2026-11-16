<#
  A window across the top of the screen, like a maximised browser's tab strip, that writes down every click it gets.
  e2e.ps1 clicks at the top edge, where the island's wake zone is, and checks the click reached this window.

  powershell -File windows/tools/clicktarget.ps1 -Log clicks.txt
#>
param([Parameter(Mandatory)] [string] $Log)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class ClickTargetDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[ClickTargetDpi]::SetProcessDPIAware() | Out-Null

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Col click target'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.Location = New-Object System.Drawing.Point 0, 0
$form.Size = New-Object System.Drawing.Size ([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width), 120
$form.BackColor = [System.Drawing.Color]::FromArgb(0x2B, 0x57, 0x9A)
$form.ShowInTaskbar = $false
$form.Add_MouseDown({
    param($sender, $click)
    Add-Content -Path $Log -Value ("down {0} {1}" -f $click.X, $click.Y)
})
Set-Content -Path $Log -Value 'ready'
[System.Windows.Forms.Application]::Run($form)
