#!/bin/bash
# Claude Code status line — port of the Windows statusline-command.ps1
# Shows: ponytail marker, model, context bar, 5h bar, 7d bar, account, git branch
# Portable: bash 3.2 (macOS) and bash 5 (Linux/WSL). Needs python3 + awk.

input=$(cat)

ESC=$(printf '\033')
BRANCH_GLYPH=$(printf '⎇')  # branch glyph (U+2387)
BAR_WIDTH=10

# Colored bar + rounded percentage, matching Get-Bar in the ps1.
get_bar() {
  awk -v p="$1" -v w="$BAR_WIDTH" -v e="$ESC" 'BEGIN{
    f=int(p/100*w+0.5); if(f<0)f=0; if(f>w)f=w;
    c = (p>=90) ? e"[31m" : (p>=70) ? e"[33m" : e"[32m";
    s=c; for(i=0;i<f;i++) s=s"#";
    s=s e"[2m"; for(i=0;i<w-f;i++) s=s"-";
    printf "%s%s %s%d%%%s", s, e"[0m", c, int(p+0.5), e"[0m";
  }'
}

# One pass over the JSON; blank line = field absent. Reset timestamps are
# formatted here so the script needs no GNU date.
fields=()
while IFS= read -r _l; do fields+=("$_l"); done < <(printf '%s' "$input" | python3 -c '
import json, sys
from datetime import datetime
try: d = json.load(sys.stdin)
except Exception: d = {}
def g(*path):
    cur = d
    for k in path:
        if not isinstance(cur, dict) or cur.get(k) is None: return ""
        cur = cur[k]
    return str(cur)
def clock(*path):   # 5:20am
    ts = g(*path)
    if not ts: return ""
    t = datetime.fromtimestamp(float(ts))
    return t.strftime("%I:%M%p").lstrip("0").lower()
def day(*path):     # Aug 29
    ts = g(*path)
    if not ts: return ""
    t = datetime.fromtimestamp(float(ts))
    return t.strftime("%b ") + str(t.day)
print(g("model","display_name") or "unknown")
print(g("context_window","used_percentage"))
print(g("rate_limits","five_hour","used_percentage"))
print(clock("rate_limits","five_hour","resets_at"))
print(g("rate_limits","seven_day","used_percentage"))
print(day("rate_limits","seven_day","resets_at"))
print(g("workspace","current_dir"))
')
model="${fields[0]:-unknown}" used="${fields[1]}"
five="${fields[2]}" five_label="${fields[3]}"
week="${fields[4]}" week_label="${fields[5]}" dir="${fields[6]}"

# account email — regex, not a full parse (~/.claude.json is multi-MB)
account=$(sed -n 's/.*"emailAddress"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' ~/.claude.json 2>/dev/null | head -1)

prefix=$(bash ~/.claude/plugins/marketplaces/ponytail/hooks/ponytail-statusline.sh 2>/dev/null)
[ -n "$prefix" ] && prefix="$prefix "

line="$prefix${ESC}[2;36m$model${ESC}[0m "
if [ -n "$used" ]; then
  line="$line$(get_bar "$used")"
else
  line="$line${ESC}[2m$(printf '%*s' "$BAR_WIDTH" '' | tr ' ' '-')${ESC}[0m"
fi

if [ -n "$five" ]; then
  line="$line ${ESC}[2;36m${five_label:-5h}:${ESC}[0m $(get_bar "$five")"
fi

if [ -n "$week" ]; then
  line="$line ${ESC}[2;36m${week_label:-7d}:${ESC}[0m $(get_bar "$week")"
fi

[ -n "$account" ] && line="$line ${ESC}[2m$account${ESC}[0m"

branch=$(git -C "${dir:-.}" branch --show-current 2>/dev/null)
[ -n "$branch" ] || branch=$(git -C "${dir:-.}" rev-parse --short HEAD 2>/dev/null)
[ -n "$branch" ] && line="$line $BRANCH_GLYPH $branch"

printf '%s' "$line"
