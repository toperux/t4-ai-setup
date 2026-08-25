$json = [Console]::In.ReadToEnd() | ConvertFrom-Json

# ponytail active-mode marker (existing behavior)
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$Flag = Join-Path $ClaudeDir ".ponytail-active"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Esc = [char]27
$prefix = ""
if (Test-Path $Flag) {
    $mode = (Get-Content $Flag -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    $suffix = if ([string]::IsNullOrEmpty($mode) -or $mode -eq "full") { "" } else { ":$($mode.ToUpperInvariant())" }
    $prefix = "${Esc}[38;5;108m[PONYTAIL$suffix]${Esc}[0m "
}

# logged-in account email (from ~/.claude.json; regex not full parse — file is multi-MB)
# ponytail: raw-read + scoped regex, cache only if it measurably lags
$account = ""
$cfg = Join-Path $HOME ".claude.json"
if (Test-Path $cfg) {
    $raw = Get-Content $cfg -Raw -ErrorAction SilentlyContinue
    if ($raw -match '"oauthAccount"\s*:\s*\{[^}]*?"emailAddress"\s*:\s*"([^"]+)"') {
        $account = $matches[1]
    }
}

$model = $json.model.display_name
$used = $json.context_window.used_percentage

$barWidth = 10
function Get-Bar($pct) {
    $filled = [Math]::Min($barWidth, [Math]::Max(0, [Math]::Round($pct / 100 * $barWidth)))
    $empty = $barWidth - $filled
    $color = if ($pct -ge 90) { "${Esc}[31m" } elseif ($pct -ge 70) { "${Esc}[33m" } else { "${Esc}[32m" }
    $bar = "$color" + ("#" * $filled) + "${Esc}[2m" + ("-" * $empty) + "${Esc}[0m"
    $roundedPct = [Math]::Round($pct)
    return "$bar $color$roundedPct%${Esc}[0m"
}

$dimCyan = "${Esc}[2;36m"
$BranchGlyph = [char]0x2387

if ($null -eq $used) {
    $bar = "${Esc}[2m" + ("-" * $barWidth) + "${Esc}[0m"
    [Console]::Write("$prefix$dimCyan$model${Esc}[0m $bar")
} else {
    [Console]::Write("$prefix$dimCyan$model${Esc}[0m $(Get-Bar $used)")
}

$fiveHour = $json.rate_limits.five_hour.used_percentage
if ($null -ne $fiveHour) {
    $resetsAt = $json.rate_limits.five_hour.resets_at
    $label = "5h:"
    if ($null -ne $resetsAt) {
        $resetTime = ([DateTimeOffset]::FromUnixTimeSeconds($resetsAt)).ToLocalTime().ToString("h:mmtt").ToLower()
        $label = "${resetTime}:"
    }
    [Console]::Write(" $dimCyan$label${Esc}[0m $(Get-Bar $fiveHour)")
}

$sevenDay = $json.rate_limits.seven_day.used_percentage
if ($null -ne $sevenDay) {
    $weekResetsAt = $json.rate_limits.seven_day.resets_at
    $weekLabel = "7d:"
    if ($null -ne $weekResetsAt) {
        $weekLabel = ([DateTimeOffset]::FromUnixTimeSeconds($weekResetsAt)).ToLocalTime().ToString("MMM d") + ":"
    }
    [Console]::Write(" $dimCyan$weekLabel${Esc}[0m $(Get-Bar $sevenDay)")
}

if ($account) {
    [Console]::Write(" ${Esc}[2m$account${Esc}[0m")
}

# git branch (falls back to short SHA on detached HEAD; silent if not a repo)
$dir = $json.workspace.current_dir
$branch = (git -C $dir branch --show-current 2>$null)
if (-not $branch) { $branch = (git -C $dir rev-parse --short HEAD 2>$null) }
if ($branch) {
    [Console]::Write(" $BranchGlyph $branch")
}
