param(
    [string]$Serial,
    [switch]$Watch,
    [switch]$ShowDebugToken
)

$ErrorActionPreference = 'Stop'
$adbCommand = Get-Command adb -ErrorAction Stop
$adbPath = $adbCommand.Source
if (-not $Serial) {
    $connected = @(& $adbPath devices | Where-Object { $_ -match '^\S+\s+device$' })
    if ($connected.Count -ne 1) {
        throw 'Connect and authorize exactly one phone, or supply -Serial.'
    }
    $Serial = ($connected[0] -split '\s+')[0]
}
$appProcessId = ([string](& $adbPath -s $Serial shell pidof com.agroconnect.agro_connect)).Trim()
if (-not $appProcessId) {
    throw 'Open AGRO CONNECT first, then run this script again.'
}
Write-Host "Reading Cygnus/App Check logs for PID $appProcessId."
Write-Host 'Enter Hi in Cygnus. This script does not restart or alter the app.'
if ($ShowDebugToken) {
    Write-Host 'Private token display enabled. Do not include the token in shared logs.'
}
$logArguments = @('-s', $Serial, 'logcat', "--pid=$appProcessId", '-v', 'time')
if (-not $Watch) { $logArguments += '-d' }
& $adbPath @logArguments | ForEach-Object {
    $line = $_
    if ($line -match 'AppCheck|App Check|firebase_app_check|Cygnus|debug token|debug secret|Role .*not supported') {
        if (-not $ShowDebugToken) {
            $line = $line -replace '[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}', '<REDACTED_DEBUG_TOKEN>'
            $line = $line -replace 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', '<REDACTED_JWT>'
        }
        Write-Output $line
    }
}
