param(
    [Parameter(Mandatory = $true)][string]$ProbeExecutable,
    [string]$MonitorExecutable = 'build/native-drop-tests/Release/startup_monitor.exe'
)
$ErrorActionPreference = 'Stop'
$probe = (Resolve-Path -LiteralPath $ProbeExecutable).Path
$monitor = (Resolve-Path -LiteralPath $MonitorExecutable).Path
$root = Split-Path -Parent $PSScriptRoot
foreach ($mode in @('saved', 'cli', 'normal', 'show')) {
    $output = Join-Path $root ('build/startup-verification-' + $mode + '-' + [Guid]::NewGuid().ToString('N'))
    & $monitor $probe $output $mode
    if ($LASTEXITCODE -ne 0) {
        throw "Native startup verification failed: $mode ($output)"
    }
    Get-Content -LiteralPath (Join-Path $output 'passed')
}
