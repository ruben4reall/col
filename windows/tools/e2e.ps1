<#
  Runs the real Col for Windows and drives it like a user and an agent would: colctl's commands, a hook that reports
  work, a permission request answered with the island's Allow button (through UI Automation), the hook's answer, and
  how fast a hook gives up when Col is not running. Then measures Col's memory and processor at rest.

  powershell -File windows/tools/e2e.ps1 -App artifacts/win-x64/Col.exe -Colctl artifacts/win-x64/colctl.exe -Out shots
#>
param(
    [Parameter(Mandatory)] [string] $App,
    [Parameter(Mandatory)] [string] $Colctl,
    [Parameter(Mandatory)] [string] $Out
)

$ErrorActionPreference = 'Stop'
$App = (Resolve-Path $App).Path
$Colctl = (Resolve-Path $Colctl).Path
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Out = (Resolve-Path $Out).Path
. (Join-Path $PSScriptRoot 'desktop.ps1')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$failures = New-Object System.Collections.Generic.List[string]
function Check([bool] $ok, [string] $what) {
    if ($ok) { Write-Host "ok    $what" } else { Write-Host "FAIL  $what"; $failures.Add($what) }
}

function Invoke-Colctl([string[]] $Arguments, [string] $Stdin = $null) {
    $info = New-Object System.Diagnostics.ProcessStartInfo $Colctl
    $info.Arguments = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    if ($Stdin) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Stdin)
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    }
    $process.StandardInput.Close()
    return $process
}

function Finish($process) {
    $output = $process.StandardOutput.ReadToEnd()
    $errors = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{ Code = $process.ExitCode; Output = $output.Trim(); Errors = $errors.Trim() }
}

function Find-Button([string] $id, [int] $seconds = 10) {
    $condition = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::AutomationIdProperty), $id
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        $found = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
        if ($found) { return $found }
        Start-Sleep -Milliseconds 250
    }
    return $null
}

Initialize-Desktop -Out $Out
$hookTimes = @()

# A hook with Col closed answers at once, and changes nothing.
$watch = [System.Diagnostics.Stopwatch]::StartNew()
$closed = Finish (Invoke-Colctl @('hook') '{"session_id":"ci","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}')
$watch.Stop()
Write-Host "colctl hook with Col closed: $($watch.ElapsedMilliseconds) ms"
Check ($closed.Code -eq 0 -and $closed.Output -eq '') 'a hook exits 0 and says nothing when Col is not running'
Check ($watch.ElapsedMilliseconds -lt 1500) 'a hook gives up within the budget when Col is not running'
$status = Finish (Invoke-Colctl @('status'))
Check ($status.Code -eq 1 -and $status.Errors -match 'not running') 'colctl status says when Col is not running'

# Col, as it starts at login.
$col = Start-Process -FilePath $App -ArgumentList '--background' -PassThru
Start-Sleep -Seconds 8
if ($col.HasExited) {
    Write-Host "Col quit with code $($col.ExitCode)"
    Show-Crash
    $log = Join-Path $env:LOCALAPPDATA 'Col\col.log'
    if (Test-Path $log) { Get-Content $log | Write-Host }
    exit 1
}

$status = Finish (Invoke-Colctl @('status'))
Write-Host "status: $($status.Output) $($status.Errors)"
Check ($status.Code -eq 0 -and $status.Output -match '^Col 3\.\d+\.\d+ is running') 'colctl status reaches Col'

$push = Finish (Invoke-Colctl @('push', 'build', '--title', 'Build', '--symbol', 'hammer.fill', '--tint', 'orange', '--progress', '40%'))
Check ($push.Code -eq 0) 'colctl push'
$list = Finish (Invoke-Colctl @('list'))
Write-Host "list: $($list.Output)"
Check ($list.Output -match 'build\s+Build\s+40%') 'colctl list shows the activity'
Start-Sleep -Seconds 1
Save-Screen -Path (Join-Path $Out 'e2e-push.png') -Zoom
$done = Finish (Invoke-Colctl @('done', 'build', '--text', 'Done'))
Check ($done.Code -eq 0) 'colctl done'
$missing = Finish (Invoke-Colctl @('done', 'nothing'))
Check ($missing.Code -eq 1 -and $missing.Errors -match 'no such activity') 'colctl done of an unknown activity fails'

# An agent at work.
$watch.Restart()
$work = Finish (Invoke-Colctl @('hook') '{"session_id":"ci","hook_event_name":"PreToolUse","cwd":"C:\\ci\\col","tool_name":"Bash","tool_input":{"command":"dotnet test"}}')
$watch.Stop()
$hookTimes += $watch.ElapsedMilliseconds
Check ($work.Code -eq 0 -and $work.Output -eq '') 'a PreToolUse hook is taken in and answered with nothing'
Write-Host "colctl hook with Col running: $($watch.ElapsedMilliseconds) ms"
Start-Sleep -Seconds 1
Save-Screen -Path (Join-Path $Out 'e2e-agent.png') -Zoom

# A permission request, allowed from the island.
$request = '{"session_id":"ci","hook_event_name":"PermissionRequest","cwd":"C:\\ci\\col","tool_name":"Bash","tool_input":{"command":"git push origin main","description":"Push"}}'
$waiting = Invoke-Colctl @('hook') $request
Start-Sleep -Seconds 2
Save-Screen -Path (Join-Path $Out 'e2e-permission.png')
Save-Screen -Path (Join-Path $Out 'e2e-permission-zoom.png') -Zoom
$allow = Find-Button 'Allow'
Check ($null -ne $allow) 'the island shows Allow'
if ($allow) {
    $allow.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}
$answer = Finish $waiting
Write-Host "hook answered: $($answer.Output)"
Check ($answer.Output -eq '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}') 'Allow answers the hook as Claude Code reads it'

# A second one, denied.
$waiting = Invoke-Colctl @('hook') ($request -replace 'git push origin main', 'rm -rf build')
$deny = Find-Button 'Deny'
Check ($null -ne $deny) 'the island shows Deny'
if ($deny) {
    Start-Sleep -Milliseconds 800
    $deny.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}
$answer = Finish $waiting
Check ($answer.Output -eq '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from Col."}}}') 'Deny answers the hook as Claude Code reads it'

# The session ends.
$end = Finish (Invoke-Colctl @('hook') '{"session_id":"ci","hook_event_name":"SessionEnd"}')
Check ($end.Code -eq 0) 'SessionEnd'

# Hooks installed in a settings file of the test's own, then taken away.
$settings = Join-Path $env:TEMP 'col-ci-settings.json'
'{ "model": "opus", "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "my-tool.exe" } ] } ] } }' | Set-Content -Path $settings -Encoding UTF8
$install = Finish (Invoke-Colctl @('hooks', 'install', '--agent', 'claude', '--settings', $settings))
Write-Host $install.Output
$json = Get-Content $settings -Raw | ConvertFrom-Json
Check ($install.Code -eq 0 -and $json.model -eq 'opus' -and $json.hooks.Stop.Count -eq 2 -and $json.hooks.PermissionRequest[0].hooks[0].timeout -eq 120) 'hooks install keeps the user''s settings and adds Col''s'
Check (Test-Path "$settings.col-backup") 'hooks install keeps a backup'
$uninstall = Finish (Invoke-Colctl @('hooks', 'uninstall', '--agent', 'claude', '--settings', $settings))
$json = Get-Content $settings -Raw | ConvertFrom-Json
Check ($uninstall.Code -eq 0 -and $json.hooks.Stop.Count -eq 1 -and -not $json.hooks.PermissionRequest) 'hooks uninstall leaves only the user''s hooks'

# Memory and processor at rest: one minute after the last event, nothing playing, nothing to show.
Start-Sleep -Seconds 60
$process = Get-Process -Id $col.Id
$cpuBefore = $process.TotalProcessorTime
Start-Sleep -Seconds 30
$process.Refresh()
$cpu = ($process.TotalProcessorTime - $cpuBefore).TotalMilliseconds / 30000 / [Environment]::ProcessorCount * 100
$summary = "At rest: working set {0:N1} MB, private bytes {1:N1} MB, processor {2:N3} % over 30 s" -f ($process.WorkingSet64 / 1MB), ($process.PrivateMemorySize64 / 1MB), $cpu
Write-Host $summary
$summary | Set-Content -Path (Join-Path $Out 'rest.txt')
Stop-Process -Id $col.Id -Force

# The music demo, where the equalizer dances: what it costs.
$music = Start-Process -FilePath $App -ArgumentList @('--demo', 'music') -PassThru
Start-Sleep -Seconds 5
$music.Refresh()
$cpuBefore = $music.TotalProcessorTime
Start-Sleep -Seconds 20
$music.Refresh()
$cpu = ($music.TotalProcessorTime - $cpuBefore).TotalMilliseconds / 20000 / [Environment]::ProcessorCount * 100
$line = "Music playing (equalizer): working set {0:N1} MB, processor {1:N2} % over 20 s" -f ($music.WorkingSet64 / 1MB), $cpu
Write-Host $line
$line | Add-Content -Path (Join-Path $Out 'rest.txt')
Stop-Process -Id $music.Id -Force

$log = Join-Path $env:LOCALAPPDATA 'Col\col.log'
if (Test-Path $log) {
    Write-Host '--- col.log ---'
    Get-Content $log | Write-Host
}

if ($failures.Count -gt 0) {
    Write-Host "$($failures.Count) check(s) failed"
    exit 1
}
Write-Host 'All end-to-end checks passed'
