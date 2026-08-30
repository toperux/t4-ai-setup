$json = [Console]::In.ReadToEnd() | ConvertFrom-Json

# ponytail active-mode marker (existing behavior)
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$Flag = Join-Path $ClaudeDir ".ponytail-active"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Esc = [char]27
$prefix = ""
if (Test-Path $Flag) {
    $mode = (Get-Content $Flag -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    $color = switch ($mode) { "lite" { 244 } "ultra" { 203 } default { 108 } }
    $prefix = "${Esc}[38;5;${color}m$([char]0x25CF)${Esc}[0m "
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

# reasoning effort; absent on models that don't support it
$effort = ""
if ($json.effort.level) {
    $short = switch ($json.effort.level) { "medium" { "med" } "xhigh" { "xhi" } default { $json.effort.level } }
    $effort = "${Esc}[2m$short${Esc}[0m "
}

# capsule bar: label + percent painted on a solid background, filled left-to-right
function Get-PillText($label, $pct) {
    $num = if ($null -eq $pct) { "  --" } else { "{0,3}%" -f [Math]::Round($pct) }
    return " $label $num "
}
function Get-Pill($label, $pct, $width) {
    $text = Get-PillText $label $pct
    if ($text.Length -lt $width) { $text = $text.PadRight($width) }

    if ($null -eq $pct) {
        $bg = 236; $fg = 250; $filled = 0
    } else {
        $bg = if ($pct -ge 90) { 174 } elseif ($pct -ge 70) { 186 } else { 151 }
        $fg = 16
        $filled = [Math]::Min($text.Length, [Math]::Max(0, [Math]::Round($pct / 100 * $text.Length)))
    }

    $on = "${Esc}[48;5;${bg};38;5;${fg}m"
    $off = "${Esc}[48;5;236;38;5;250m"
    $r = "${Esc}[0m"
    $capL = if ($filled -gt 0) { $bg } else { 236 }
    $capR = if ($filled -ge $text.Length) { $bg } else { 236 }

    return "${Esc}[38;5;${capL}m$([char]0x2590)$r" +
           "$on$($text.Substring(0, $filled))$r" +
           "$off$($text.Substring($filled))$r" +
           "${Esc}[38;5;${capR}m$([char]0x258C)$r"
}

$BranchGlyph = [char]0x2387

$pills = @(, @($model, $used))

$fiveHour = $json.rate_limits.five_hour.used_percentage
if ($null -ne $fiveHour) {
    $resetsAt = $json.rate_limits.five_hour.resets_at
    $label = if ($null -ne $resetsAt) {
        ([DateTimeOffset]::FromUnixTimeSeconds($resetsAt)).ToLocalTime().ToString("h:mmtt").ToLower()
    } else { "5h" }
    $pills += , @($label, $fiveHour)
}

$sevenDay = $json.rate_limits.seven_day.used_percentage
if ($null -ne $sevenDay) {
    $weekResetsAt = $json.rate_limits.seven_day.resets_at
    $weekLabel = if ($null -ne $weekResetsAt) {
        ([DateTimeOffset]::FromUnixTimeSeconds($weekResetsAt)).ToLocalTime().ToString("MMM d")
    } else { "7d" }
    $pills += , @($weekLabel, $sevenDay)
}

$width = ($pills | ForEach-Object { (Get-PillText $_[0] $_[1]).Length } | Measure-Object -Maximum).Maximum
$bars = ($pills | ForEach-Object { Get-Pill $_[0] $_[1] $width }) -join " "
[Console]::Write("$prefix$effort$bars")

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
