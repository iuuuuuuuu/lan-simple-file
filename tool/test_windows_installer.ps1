param(
    [Parameter(Mandatory = $true)][string]$RuntimeDir,
    [Parameter(Mandatory = $true)][string]$ProbeExecutable,
    [Parameter(Mandatory = $true)][string]$Compiler,
    [string]$NativeBuild = 'build/native-drop-tests'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runtime = (Resolve-Path -LiteralPath $RuntimeDir).Path
$probe = (Resolve-Path -LiteralPath $ProbeExecutable).Path
$native = (Resolve-Path -LiteralPath $NativeBuild).Path
$helper = Join-Path $native 'installer-tools/Release/installer_shutdown.exe'
$monitor = Join-Path $native 'Release/installer_monitor.exe'
$output = Join-Path $root ('build/installer-verification-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output | Out-Null
$version = (Get-Item -LiteralPath (Join-Path $runtime 'lan_simple_file.exe')).VersionInfo.ProductVersion.Split('+')[0]
& $Compiler "/DRuntimeDir=$runtime" "/DOutputDir=$output" "/DAppVersion=$version" "/DShutdownHelper=$helper" `
    '/DInstallerTest' '/DInstallerAppId=LanSimpleFileInstallerTest' `
    (Join-Path $PSScriptRoot 'windows_installer.iss')
if ($LASTEXITCODE -ne 0) { throw 'Test installer compilation failed' }
$expected = (Get-FileHash -LiteralPath (Join-Path $runtime 'lan_simple_file.exe')).Hash
foreach ($case in @(@('fresh', 'silent'), @('ask', 'wizard'), @('tray', 'silent'), @('legacy', 'wizard'))) {
    $caseOutput = Join-Path $output ($case[0] + '-' + $case[1])
    & $monitor (Join-Path $output 'lan-simple-file-setup.exe') $probe $caseOutput $case[0] $case[1]
    if ($LASTEXITCODE -ne 0) { throw "Installer regression failed: $case ($caseOutput)" }
    $actual = (Get-FileHash -LiteralPath (Join-Path $caseOutput 'installed app/lan_simple_file.exe')).Hash
    if ($expected -ne $actual) { throw "Installed executable differs: $caseOutput" }
    $log = Get-Content -LiteralPath (Join-Path $caseOutput 'setup.log') -Raw
    if ($log -notmatch 'Installed client shutdown: started=1, result=0') {
        throw "Missing successful shutdown result: $caseOutput"
    }
    if ($case[0] -in @('ask', 'tray') -and $log -notmatch 'matched=1 graceful=1 restart_manager=0 forced=0') {
        throw "Client did not complete graceful exit: $caseOutput"
    }
    if ($case[0] -in @('ask', 'tray')) {
        & python (Join-Path $PSScriptRoot 'verify_installer_data.py') `
            (Join-Path $caseOutput 'client/data/db/app.sqlite') $case[0]
        if ($LASTEXITCODE -ne 0) { throw "Upgrade data verification failed: $caseOutput" }
    }
}
Write-Output "Installer regression passed: $output"
