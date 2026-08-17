# ============================================================
# NTP time sync. Executed by Task Scheduler as SYSTEM.
# Appends one line per run: timestamp / measured offset / result.
#
# This file is deliberately pure ASCII. w32tm prints LOCALIZED text,
# so the Japanese label is built from code points below instead of
# being written literally. Keep it that way -- a raw non-ASCII byte
# here breaks the moment an editor drops the BOM or the console
# code page differs.
# ============================================================

$logFile = Join-Path $PSScriptRoot "ntp_sync.log"
$now     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# The "offset" label as printed by w32tm /query /status /verbose.
#   JP: U+30AA U+30D5 U+30BB U+30C3 U+30C8  -> katakana "ofusetto"
#   EN: "Offset"
# Each is unique to the phase-offset line in that output.
$labelJa = -join ([char[]](0x30AA, 0x30D5, 0x30BB, 0x30C3, 0x30C8))
$labelEn = 'Offset'

# w32tm writes in the machine OEM code page (932 on Japanese Windows).
# Read it from the registry, NOT from CurrentCulture: under the SYSTEM
# account CurrentCulture can be invariant and would yield the wrong page,
# which silently breaks the label match above.
$oemCp = 0
try {
    $oemCp = [int](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' `
                   -Name OEMCP -ErrorAction Stop).OEMCP
} catch {}

function Read-PhaseOffsetLine {
    # Returns the raw phase-offset line, or $null if not found.
    $prev = [Console]::OutputEncoding
    if ($oemCp -gt 0) {
        try { [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding($oemCp) } catch {}
    }
    $out = w32tm /query /status /verbose 2>&1
    try { [Console]::OutputEncoding = $prev } catch {}

    foreach ($l in $out) {
        if (($l -match $labelJa -or $l -match $labelEn) -and $l -match '[+-]?\d+\.\d+\s*s') {
            return [string]$l
        }
    }
    return $null
}

# --- Self-heal: if W32Time is stopped, /resync fails with 0x80070426 ---
$svc = Get-Service w32time -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -ne 'Running') {
    try { Start-Service w32time -ErrorAction Stop; Start-Sleep -Seconds 1 } catch {}
}

# Snapshot the offset line BEFORE resyncing, so the reading taken
# afterwards can be told apart from the stale one.
$before = Read-PhaseOffsetLine

# --- Sync the clock (this is what measures and corrects the drift) ---
$null     = w32tm /resync 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    # W32Time updates its status asynchronously: immediately after /resync
    # returns, /query can still report the PREVIOUS sync. Poll until the line
    # actually changes rather than sleeping a fixed interval and hoping.
    # Cap at 2s; the task itself runs far more often than that.
    $line  = $null
    $fresh = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 100
        $line = Read-PhaseOffsetLine
        if ($null -ne $line -and $line -ne $before) { $fresh = $true; break }
    }

    if ($fresh -and $line -match '([+-]?\d+\.\d+)\s*s') {
        $ms    = [math]::Round([double]$matches[1] * 1000, 1)
        $sign  = if ($ms -ge 0) { '+' } else { '' }
        $entry = "$now [OK] offset=$sign${ms}ms corrected (exit=0)"
    } else {
        # Sync succeeded but the fresh reading never appeared. Say so rather
        # than logging the previous run's number as if it were this one.
        $entry = "$now [OK] offset=unconfirmed corrected (exit=0)"
    }
} else {
    # No offset is reported here on purpose: after a failed resync, /query
    # still returns the offset from the last SUCCESSFUL sync, so printing it
    # would log a stale value as though it were current.
    $hex   = '0x{0:X8}' -f $exitCode
    $entry = "$now [NG] resync failed - check admin rights / network (exit=$hex)"
}

# Log in ASCII: the content is ASCII by construction, and this writes no BOM.
Add-Content -Path $logFile -Value $entry -Encoding ASCII

# --- Keep the log to the most recent 1000 lines ---
$lines = @(Get-Content -Path $logFile -Encoding ASCII -ErrorAction SilentlyContinue)
if ($lines.Count -gt 1000) {
    $lines | Select-Object -Last 1000 | Set-Content -Path $logFile -Encoding ASCII
}
