# ============================================================
# Registers the scheduled task "NTP Time Sync (NICT)".
# Must be run from an ELEVATED PowerShell. Normally invoked by
# setup.bat -> deploy_local.ps1; run directly only to re-register
# after changing the interval below.
#
# Pure ASCII on purpose -- see the header of ntp_resync.ps1.
# ============================================================

# ##################################################
#   SYNC INTERVAL IN MINUTES -- change this number only
#   1 = every minute, 2 = every 2 minutes, 5 = every 5 minutes
$IntervalMinutes = 2
# ##################################################

$taskName   = "NTP Time Sync (NICT)"
$ntpServer  = "ntp.nict.jp"
# Target the ntp_resync.ps1 sitting next to this file (location independent).
$scriptPath = Join-Path $PSScriptRoot "ntp_resync.ps1"

# --- Refuse to register against a network / mapped path ---
# The task runs as SYSTEM, which cannot see mapped drives or UNC shares.
# It would register fine and then fail silently on every run, so stop here.
$onNetwork = $false
if ($scriptPath -like "\\*") { $onNetwork = $true }
elseif ($scriptPath -match '^[A-Za-z]:\\') {
    $drive = Get-PSDrive $scriptPath.Substring(0, 1) -ErrorAction SilentlyContinue
    if ($drive -and $drive.DisplayRoot) { $onNetwork = $true }
}
if ($onNetwork) {
    Write-Host " [ERROR] These scripts are on a network or mapped drive:" -ForegroundColor Red
    Write-Host "         $scriptPath" -ForegroundColor Red
    Write-Host "         A SYSTEM task cannot reach that path and would fail every run." -ForegroundColor Red
    Write-Host "         Run setup.bat instead - it copies everything to C:\ntp_sync first." -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $scriptPath)) {
    Write-Host " [ERROR] ntp_resync.ps1 not found next to this script." -ForegroundColor Red
    Write-Host "         Expected: $scriptPath" -ForegroundColor Red
    exit 1
}

# --- Administrator check ---
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host " [ERROR] Administrator rights required. Re-open PowerShell as administrator." -ForegroundColor Red
    exit 1
}

# --- Configure the Windows Time service ---
# (1) Pin the peer to ntp.nict.jp.
# (2) MaxAllowedPhaseOffset=0 forces a STEP correction (set the clock outright)
#     every time. The default is 1 second, meaning sub-second drift is slewed
#     gradually instead -- and on a PC whose clock drifts fast, slewing never
#     catches up and the error keeps growing. Do not "clean this up".
Write-Host " Configuring Windows Time service (peer=$ntpServer, always step-correct)..." -ForegroundColor Cyan
w32tm /config /manualpeerlist:"$ntpServer" /syncfromflags:manual /update | Out-Null
$cfgPath = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config"
New-ItemProperty -Path $cfgPath -Name "MaxAllowedPhaseOffset" -Value 0 -PropertyType DWord -Force | Out-Null

# Start automatically: while the service is stopped, /resync fails with
# 0x80070426 (service not started) and no sync happens at all.
Set-Service w32time -StartupType Automatic
Restart-Service w32time
Start-Sleep -Seconds 2
Write-Host " [OK] Time service configured (automatic start, MaxAllowedPhaseOffset=0)" -ForegroundColor Green
Write-Host ""

# --- Replace any existing task ---
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host " Existing task found - removing and re-registering..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

# Repeat indefinitely at the interval set at the top of this file.
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)

# Run as SYSTEM so it works with no user logged on.
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
    -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

Register-ScheduledTask -TaskName $taskName `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description "Sync the clock with $ntpServer every $IntervalMinutes minute(s)." | Out-Null

Write-Host " [SUCCESS] Task '$taskName' registered - every $IntervalMinutes minute(s)." -ForegroundColor Green
Write-Host ""

# --- Run once now as a test ---
Write-Host " Running once now to test..." -ForegroundColor Cyan
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 5

Write-Host ""
Write-Host " ==== Registered task ====" -ForegroundColor Cyan
# Printed field by field rather than with Format-List: its output starts at
# column 0 and would break the one-space margin used everywhere else.
$info = Get-ScheduledTask -TaskName $taskName | Get-ScheduledTaskInfo
Write-Host (" TaskName       : " + $taskName)
Write-Host (" LastRunTime    : " + $info.LastRunTime)
Write-Host (" LastTaskResult : " + $info.LastTaskResult)
Write-Host (" NextRunTime    : " + $info.NextRunTime)
Write-Host ""

Write-Host " ==== Log (last 3 lines) ====" -ForegroundColor Cyan
$logFile = Join-Path $PSScriptRoot "ntp_sync.log"
if (Test-Path $logFile) {
    Get-Content $logFile -Tail 3 -Encoding ASCII | ForEach-Object { Write-Host (" " + $_) }
} else {
    Write-Host " (no log yet)" -ForegroundColor Gray
}
Write-Host ""
Write-Host " Log file: $logFile" -ForegroundColor Gray
