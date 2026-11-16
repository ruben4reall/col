<#
  Runs the small Col.exe (without .NET inside) on this machine's .NET 8 Desktop Runtime. When it does not stay up,
  shows why (the runtime's report in the event log) and tries the same app published other ways, to tell which
  setting it does not take.

  pwsh windows/tools/smallcheck.ps1 -Rid win-x64
#>
param([string] $Rid = 'win-x64')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'desktop.ps1')

function Test-Runs([string] $exe) {
    $process = Start-Process -FilePath $exe -ArgumentList '--demo', 'collapsed' -PassThru
    Start-Sleep -Seconds 6
    if ($process.HasExited) {
        Write-Host ("{0}: quit with code {1} (0x{1:X8})" -f $exe, $process.ExitCode)
        return $false
    }
    Stop-Process -Id $process.Id -Force
    Start-Sleep -Milliseconds 500
    Write-Host "${exe}: runs"
    return $true
}

& dotnet --list-runtimes
if (Test-Runs (Resolve-Path "artifacts/$Rid-small/Col.exe").Path) { exit 0 }
Show-Crash

$variants = [ordered]@{
    'no ReadyToRun' = @('-p:PublishReadyToRun=false')
    'not a single file' = @('-p:PublishSingleFile=false')
    'no single file, no ReadyToRun' = @('-p:PublishSingleFile=false', '-p:PublishReadyToRun=false')
}
$index = 0
foreach ($name in $variants.Keys) {
    $index++
    $folder = "artifacts/variant-$index"
    $arguments = @('publish', 'windows/src/Col/Col.csproj', '-c', 'Release', '-r', $Rid, '--self-contained', 'false', '-o', $folder) + $variants[$name]
    if ($variants[$name] -notcontains '-p:PublishSingleFile=false') { $arguments += '-p:PublishSingleFile=true' }
    & dotnet @arguments | Out-Null
    Write-Host "--- $name"
    if (-not (Test-Runs (Resolve-Path "$folder/Col.exe").Path)) { Show-Crash }
}
exit 1
