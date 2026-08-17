# ============================================================
# Copies the scripts to a local folder, then registers the task.
# Always copies first: the task runs as SYSTEM, which cannot reach
# network shares, mapped drives or USB paths that may disappear.
# Invoked by setup.bat.
#
# Pure ASCII on purpose -- see the header of ntp_resync.ps1.
# ============================================================

$destDir = "C:\ntp_sync"   # local install folder

# --- Administrator check ---
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host " [ERROR] Administrator rights required. Re-open PowerShell as administrator." -ForegroundColor Red
    exit 1
}

$srcDir = $PSScriptRoot
Write-Host " Source     : $srcDir" -ForegroundColor Gray
Write-Host " Destination: $destDir" -ForegroundColor Gray
Write-Host ""

# --- Copy to the local folder (skip if already running from there) ---
if ($srcDir.TrimEnd('\') -ieq $destDir.TrimEnd('\')) {
    Write-Host " Already running from $destDir - skipping copy." -ForegroundColor Gray
} else {
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    # uninstall.* is copied too, so the tool can still be removed after the
    # folder it was installed from is gone.
    foreach ($f in @("ntp_resync.ps1", "register_task.ps1",
                     "uninstall.ps1", "uninstall.bat")) {
        $src = Join-Path $srcDir $f
        if (-not (Test-Path $src)) {
            Write-Host " [ERROR] Missing file: $src" -ForegroundColor Red
            exit 1
        }
        Copy-Item $src $destDir -Force
    }
    Write-Host " [OK] Scripts copied to $destDir" -ForegroundColor Green
}
Write-Host ""

# --- Register the task from the local copy ---
Write-Host " Registering the scheduled task..." -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $destDir "register_task.ps1")
$rc = $LASTEXITCODE

# register_task.ps1 must RUN from $destDir: it derives the task's target from
# its own $PSScriptRoot, so running it anywhere else would point the task at
# that other folder. It has no job once the task exists, so remove it instead
# of leaving a script in the install folder that nobody will ever run again.
# Only on success - if registration failed, leave it there to retry with.
if ($rc -eq 0) {
    Remove-Item (Join-Path $destDir "register_task.ps1") -Force -ErrorAction SilentlyContinue
}
exit $rc
