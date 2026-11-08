param(
    [string]$Flutter = 'flutter',
    [string]$Keytool = 'keytool',
    [string]$TargetPlatform = 'android-arm,android-arm64,android-x64',
    [string]$BuildName,
    [string]$BuildNumber,
    [switch]$NetworkDiagnostics,
    [switch]$InitializeSigningKey
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$signingDir = Join-Path $env:USERPROFILE '.android\lan-simple-file'
$keystore = Join-Path $signingDir 'release-keystore.p12'
$credentialFile = Join-Path $signingDir 'signing-credential.xml'
$names = @(
    'LAN_SIMPLE_FILE_KEYSTORE',
    'LAN_SIMPLE_FILE_STORE_PASSWORD',
    'LAN_SIMPLE_FILE_KEY_ALIAS',
    'LAN_SIMPLE_FILE_KEY_PASSWORD'
)
$previous = @{}
foreach ($name in $names) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

Push-Location $root
try {
    $hasKey = Test-Path -LiteralPath $keystore
    $hasCredential = Test-Path -LiteralPath $credentialFile
    if ($hasKey -ne $hasCredential) {
        throw 'Signing files are incomplete. Restore the original key and credential; do not replace the release key.'
    }
    if (!$hasKey) {
        if (!$InitializeSigningKey) {
            throw 'No release key. Use -InitializeSigningKey once, then back up the signing files securely.'
        }
        New-Item -ItemType Directory -Path $signingDir -Force | Out-Null
        $bytes = New-Object byte[] 48
        $random = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $random.GetBytes($bytes) } finally { $random.Dispose() }
        $password = [Convert]::ToBase64String($bytes)
        $credential = New-Object System.Management.Automation.PSCredential(
            'lan-simple-file',
            (ConvertTo-SecureString $password -AsPlainText -Force)
        )
        $credential | Export-Clixml -LiteralPath $credentialFile
        $env:LAN_SIMPLE_FILE_STORE_PASSWORD = $password
        $env:LAN_SIMPLE_FILE_KEY_PASSWORD = $password
        & $Keytool -genkeypair -keystore $keystore -storetype PKCS12 `
            -keyalg RSA -keysize 3072 -validity 10000 -alias 'lan-simple-file' `
            -dname 'CN=Lan Simple File' `
            -storepass:env LAN_SIMPLE_FILE_STORE_PASSWORD `
            -keypass:env LAN_SIMPLE_FILE_KEY_PASSWORD
        if ($LASTEXITCODE -ne 0) { throw 'Release key generation failed.' }
        Write-Output "Created release signing files outside the repository: $signingDir"
    }
    $credential = Import-Clixml -LiteralPath $credentialFile
    $env:LAN_SIMPLE_FILE_KEYSTORE = $keystore
    $env:LAN_SIMPLE_FILE_KEY_ALIAS = $credential.UserName
    $env:LAN_SIMPLE_FILE_STORE_PASSWORD = $credential.GetNetworkCredential().Password
    $env:LAN_SIMPLE_FILE_KEY_PASSWORD = $env:LAN_SIMPLE_FILE_STORE_PASSWORD
    # --no-pub also skips release plugin registration in this Flutter SDK.
    $buildArguments = @('build', 'apk', '--release', '--split-per-abi', "--target-platform=$TargetPlatform")
    if ($BuildName) { $buildArguments += @("--build-name=$BuildName", "--dart-define=APP_VERSION=$BuildName") }
    if ($BuildNumber) { $buildArguments += "--build-number=$BuildNumber" }
    if ($NetworkDiagnostics) { $buildArguments += '--dart-define=NETWORK_DIAGNOSTICS=true' }
    & $Flutter @buildArguments
    if ($LASTEXITCODE -ne 0) { throw 'Android release build failed.' }
} finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
    $password = $null
    $credential = $null
    Pop-Location
}
