# ============================================================
# Removes everything setup.bat installed and restores the
# Windows Time service to its factory defaults.
# Must be run from an ELEVATED PowerShell; normally invoked
# by uninstall.bat.
#
# Pure ASCII on purpose -- see the header of ntp_resync.ps1.
# ============================================================

$installDir = "C:\ntp_sync"
$taskName   = "NTP Time Sync (NICT)"

# --- Administrator check ---
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host " [ERROR] Administrator rights required. Re-open PowerShell as administrator." -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# 1. Remove the scheduled task
# ------------------------------------------------------------
# Match by the script the task actually runs, not by name. Older versions of
# this tool registered the task under a Japanese name; finding it this way
# catches those too without needing a non-ASCII literal in this file.
Write-Host " [1/3] Removing scheduled task(s)..." -ForegroundColor Cyan

$targets = @()
foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
    if ($t.TaskName -eq $taskName) { $targets += $t; continue }
    foreach ($a in @($t.Actions)) {
        if ($a.Arguments -and $a.Arguments -like '*ntp_resync.ps1*') { $targets += $t; break }
    }
}

if ($targets.Count -eq 0) {
    Write-Host "       No matching task found (already removed?)." -ForegroundColor Gray
} else {
    foreach ($t in $targets) {
        try {
            Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
            Write-Host "       Removed: $($t.TaskPath)$($t.TaskName)" -ForegroundColor Green
        } catch {
            Write-Host "       [WARN] Could not remove: $($t.TaskName) - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
Write-Host ""

# ------------------------------------------------------------
# 2. Restore the Windows Time service to defaults
# ------------------------------------------------------------
# /unregister + /register is the documented way to reset W32Time. It undoes
# the peer list, MaxAllowedPhaseOffset and the startup type in one step,
# instead of guessing at the correct default for this Windows edition
# (which differs between domain-joined and standalone machines).
Write-Host " [2/3] Restoring Windows Time service defaults..." -ForegroundColor Cyan

try {
    Stop-Service w32time -Force -ErrorAction SilentlyContinue
    & w32tm /unregister 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    & w32tm /register   2>&1 | Out-Null
    Start-Sleep -Seconds 1

    # Leave the service running so the clock still syncs on the Windows
    # default schedule; without this the PC would drift with no sync at all.
    Start-Service w32time -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Write-Host "       [OK] Time service reset to Windows defaults." -ForegroundColor Green
} catch {
    Write-Host "       [WARN] Reset reported an error: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "       Try manually: net stop w32time / w32tm /unregister / w32tm /register / net start w32time" -ForegroundColor Yellow
}
Write-Host ""

# ------------------------------------------------------------
# 3. Delete the installed files
# ------------------------------------------------------------
Write-Host " [3/3] Removing installed files..." -ForegroundColor Cyan

if (-not (Test-Path $installDir)) {
    Write-Host "       $installDir not found (already removed?)." -ForegroundColor Gray
} else {
    # Everything except uninstall.bat. Windows does not lock a running .ps1,
    # so this script can and does delete itself here. uninstall.bat is left
    # alone on purpose: cmd reads a batch file line by line, so removing it
    # now would cut off the remaining output and the closing pause. The bat
    # deletes itself and this folder as its very last act.
    foreach ($f in @("ntp_resync.ps1", "register_task.ps1", "ntp_sync.log",
                     "uninstall.ps1")) {
        $p = Join-Path $installDir $f
        if (Test-Path $p) {
            try { Remove-Item $p -Force -ErrorAction Stop; Write-Host "       Deleted: $f" -ForegroundColor Green }
            catch { Write-Host "       [WARN] Could not delete: $f" -ForegroundColor Yellow }
        }
    }
    $left = @(Get-ChildItem $installDir -Force -ErrorAction SilentlyContinue)
    if ($left.Count -eq 0) {
        Remove-Item $installDir -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "       Deleted folder: $installDir" -ForegroundColor Green
    } else {
        Write-Host "       Remaining: $(($left | ForEach-Object { $_.Name }) -join ', ')" -ForegroundColor Gray
        Write-Host "       The folder is removed when this window closes." -ForegroundColor Gray
    }
}
Write-Host ""

# ------------------------------------------------------------
# Final state
# ------------------------------------------------------------
Write-Host " ==== Current state ====" -ForegroundColor Cyan
$prm = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters"
$cfg = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config"
Write-Host (" NtpServer             : " + (Get-ItemProperty $prm -Name NtpServer -EA SilentlyContinue).NtpServer)
Write-Host (" Type                  : " + (Get-ItemProperty $prm -Name Type -EA SilentlyContinue).Type)
$mapo = (Get-ItemProperty $cfg -Name MaxAllowedPhaseOffset -EA SilentlyContinue).MaxAllowedPhaseOffset
Write-Host (" MaxAllowedPhaseOffset : " + $(if ($null -eq $mapo) { "(not set)" } else { $mapo }))
$svc = Get-Service w32time -ErrorAction SilentlyContinue
if ($svc) { Write-Host (" Service               : {0} / {1}" -f $svc.Status, $svc.StartType) }
$still = @(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue).Count
Write-Host (" Scheduled task        : " + $(if ($still -gt 0) { "STILL PRESENT" } else { "removed" }))
