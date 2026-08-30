#!/bin/bash
# Claude Code status line — port of the Windows statusline-command.ps1
# Shows: ponytail marker, model/context pill, 5h pill, 7d pill, account, git branch
# Portable: bash 3.2 (macOS) and bash 5 (Linux/WSL). Needs python3.

input=$(cat)

ESC=$(printf '\033')
BRANCH_GLYPH=$(printf '⎇')  # branch glyph (U+2387)

# One pass over the JSON: renders the pill row, then the cwd. Reset timestamps
# are formatted here so the script needs no GNU date.
fields=()
while IFS= read -r _l; do fields+=("$_l"); done < <(printf '%s' "$input" | python3 -c '
import json, sys
from datetime import datetime
try: d = json.load(sys.stdin)
except Exception: d = {}
E = "\x1b"
def g(*path):
    cur = d
    for k in path:
        if not isinstance(cur, dict) or cur.get(k) is None: return None
        cur = cur[k]
    return cur

# capsule bar: label + percent painted on a solid background, filled left-to-right
def pill_text(label, pct):
    num = "  --" if pct is None else "%3d%%" % round(pct)
    return " %s %s " % (label, num)
def pill(label, pct, width):
    t = pill_text(label, pct).ljust(width)
    if pct is None:
        bg, fg, filled = 236, 250, 0
    else:
        bg = 174 if pct >= 90 else 186 if pct >= 70 else 151
        fg = 16
        filled = min(len(t), max(0, round(pct / 100 * len(t))))
    on = "%s[48;5;%d;38;5;%dm" % (E, bg, fg)
    off = "%s[48;5;236;38;5;250m" % E
    r = E + "[0m"
    capL = bg if filled > 0 else 236
    capR = bg if filled >= len(t) else 236
    return ("%s[38;5;%dm▐%s" % (E, capL, r) + on + t[:filled] + r
            + off + t[filled:] + r + "%s[38;5;%dm▌%s" % (E, capR, r))

pills = [(g("model", "display_name") or "unknown", g("context_window", "used_percentage"))]

five = g("rate_limits", "five_hour", "used_percentage")
if five is not None:
    ts = g("rate_limits", "five_hour", "resets_at")
    label = datetime.fromtimestamp(float(ts)).strftime("%I:%M%p").lstrip("0").lower() if ts else "5h"
    pills.append((label, five))

week = g("rate_limits", "seven_day", "used_percentage")
if week is not None:
    ts = g("rate_limits", "seven_day", "resets_at")
    if ts:
        t = datetime.fromtimestamp(float(ts))
        label = t.strftime("%b ") + str(t.day)
    else:
        label = "7d"
    pills.append((label, week))

width = max(len(pill_text(l, p)) for l, p in pills)
print(" ".join(pill(l, p, width) for l, p in pills))
print(g("workspace", "current_dir") or "")

# reasoning effort; absent on models that do not support it
lvl = g("effort", "level")
print("" if not lvl else "%s[2m%s%s[0m" % (E, {"medium": "med", "xhigh": "xhi"}.get(lvl, lvl), E))
')
bars="${fields[0]}" dir="${fields[1]}" effort="${fields[2]}"

# account email — regex, not a full parse (~/.claude.json is multi-MB)
account=$(LC_ALL=C sed -n 's/.*"emailAddress"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' ~/.claude.json 2>/dev/null | head -1)

# ponytail active-mode marker: a dot colored by intensity
prefix=""
flag="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.ponytail-active"
if [ -f "$flag" ]; then
    mode=$(head -n1 "$flag" | tr -d '[:space:]')
    case "$mode" in lite) color=244 ;; ultra) color=203 ;; *) color=108 ;; esac
    prefix="${ESC}[38;5;${color}m$(printf '●')${ESC}[0m "
fi

[ -n "$effort" ] && effort="$effort "

line="$prefix$effort$bars"

[ -n "$account" ] && line="$line ${ESC}[2m$account${ESC}[0m"

branch=$(git -C "${dir:-.}" branch --show-current 2>/dev/null)
[ -n "$branch" ] || branch=$(git -C "${dir:-.}" rev-parse --short HEAD 2>/dev/null)
[ -n "$branch" ] && line="$line $BRANCH_GLYPH $branch"

printf '%s' "$line"
