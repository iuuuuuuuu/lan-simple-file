param(
    [string]$BuildDirectory = 'build\native-drop-tests\Release'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runtime = [IO.Path]::GetFullPath((Join-Path $root $BuildDirectory))
$receiverExe = Join-Path $runtime 'native_file_drop_test.exe'
$senderExe = Join-Path $runtime 'native_file_drop_sender.exe'
$sandbox = Join-Path $root ("build\native-drop-tests\cross-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
$ready = Join-Path $sandbox 'window.txt'
$received = Join-Path $sandbox 'receiver.txt'
$sent = Join-Path $sandbox 'sender.txt'
$linkPath = Join-Path $sandbox 'send.lnk'
$receiver = Start-Process -FilePath $receiverExe -WindowStyle Hidden -PassThru `
    -ArgumentList @("`"$ready`"", "`"$received`"")
try {
    $deadline = (Get-Date).AddSeconds(5)
    while (!(Test-Path -LiteralPath $ready) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 50
    }
    if (!(Test-Path -LiteralPath $ready)) {
        throw 'The hidden elevated receiver was not ready. Run this test from an elevated terminal.'
    }
    $window = (Get-Content -LiteralPath $ready -Raw).Trim()
    if ($window -notmatch '^\d+$') { throw 'Invalid test window identifier.' }
    $wsh = New-Object -ComObject WScript.Shell
    try {
        $link = $wsh.CreateShortcut($linkPath)
        $link.TargetPath = $senderExe
        $link.Arguments = "$window `"$sent`""
        $link.WorkingDirectory = $runtime
        $link.WindowStyle = 7
        $link.Save()
    } finally {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($wsh)
    }
    # Explorer launches this windowless sender with the user's ordinary token.
    Start-Process -FilePath "$env:WINDIR\explorer.exe" `
        -ArgumentList "`"$linkPath`"" -WindowStyle Hidden
    if (!$receiver.WaitForExit(10000) -or $receiver.ExitCode -ne 0) {
        $details = @($sent, $received) | ForEach-Object {
            if (Test-Path -LiteralPath $_) { Get-Content -LiteralPath $_ }
        }
        throw "The ordinary sender could not drop into the elevated receiver. $($details -join ' ')"
    }
    $deadline = (Get-Date).AddSeconds(3)
    while (!(Test-Path -LiteralPath $sent) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 50
    }
    $senderResult = Get-Content -LiteralPath $sent
    if ($senderResult -notcontains 'elevated=0' -or
        $senderResult -notcontains 'normal_test=1' -or
        $senderResult -notcontains 'copied=1' -or
        $senderResult -notcontains 'sent=1' -or
        (Get-Content -LiteralPath $received -TotalCount 1) -ne 'passed') {
        throw 'Cross-integrity drop verification failed.'
    }
    'PASS: ordinary OLE preserved; ordinary sender -> hidden elevated window, Unicode and long paths preserved.'
    $senderResult
} finally {
    $receiver.Refresh()
    if (!$receiver.HasExited) { Stop-Process -Id $receiver.Id }
}
