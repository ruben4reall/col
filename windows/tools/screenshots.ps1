<#
  Photographs Col for Windows in each demo state: starts Col.exe --demo <state>, waits for the island to settle,
  captures the top of the screen (and the whole screen for the settings), then quits it.

  pwsh windows/tools/screenshots.ps1 -App artifacts/win-x64/Col.exe -Out shots
#>
param(
    [Parameter(Mandatory)] [string] $App,
    [Parameter(Mandatory)] [string] $Out
)

$ErrorActionPreference = 'Stop'
$App = (Resolve-Path $App).Path
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Out = (Resolve-Path $Out).Path
. (Join-Path $PSScriptRoot 'desktop.ps1')

Initialize-Desktop -Out $Out

$states = @(
    @{ Name = 'collapsed'; Args = @('--demo', 'collapsed') },
    @{ Name = 'peek'; Args = @('--demo', 'peek') },
    @{ Name = 'music'; Args = @('--demo', 'music') },
    @{ Name = 'lyrics'; Args = @('--demo', 'lyrics') },
    @{ Name = 'lyrics-fr'; Args = @('--demo', 'lyrics', '--lang', 'fr') },
    @{ Name = 'agent-permission'; Args = @('--demo', 'agent-permission') },
    @{ Name = 'agents'; Args = @('--demo', 'agents') },
    @{ Name = 'live'; Args = @('--demo', 'live') },
    @{ Name = 'volume'; Args = @('--demo', 'volume') },
    @{ Name = 'battery'; Args = @('--demo', 'battery') },
    @{ Name = 'timer'; Args = @('--demo', 'timer') },
    @{ Name = 'tools'; Args = @('--demo', 'tools') },
    @{ Name = 'settings-general'; Args = @('--demo', 'settings', '--page', 'general'); Full = $true },
    @{ Name = 'settings-music'; Args = @('--demo', 'settings', '--page', 'music'); Full = $true },
    @{ Name = 'settings-agents'; Args = @('--demo', 'settings', '--page', 'agents'); Full = $true },
    @{ Name = 'settings-about'; Args = @('--demo', 'settings', '--page', 'about'); Full = $true },
    @{ Name = 'settings-general-fr'; Args = @('--demo', 'settings', '--page', 'general', '--lang', 'fr'); Full = $true }
)

foreach ($state in $states) {
    $process = Start-Process -FilePath $App -ArgumentList $state.Args -PassThru
    # The first launch of a single-file app unpacks its native parts: give it time, then let the springs settle.
    Start-Sleep -Seconds ($(if ($state.Name -eq 'collapsed') { 8 } else { 4 }))
    if ($process.HasExited) {
        Write-Warning "$($state.Name): Col quit with code $($process.ExitCode)"
        Show-Crash
        continue
    }
    if ($state.Full) {
        Save-Screen -Path (Join-Path $Out "$($state.Name).png") -Full
    }
    else {
        Save-Screen -Path (Join-Path $Out "$($state.Name).png")
        Save-Screen -Path (Join-Path $Out "$($state.Name)-zoom.png") -Zoom
    }
    $process.Refresh()
    Write-Host ("{0,-22} working set {1,6:N1} MB, private {2,6:N1} MB" -f $state.Name, ($process.WorkingSet64 / 1MB), ($process.PrivateMemorySize64 / 1MB))
    Stop-Process -Id $process.Id -Force
    Start-Sleep -Milliseconds 600
}

$log = Join-Path $env:LOCALAPPDATA 'Col\col.log'
if (Test-Path $log) {
    Write-Host '--- col.log ---'
    Get-Content $log | Write-Host
}
