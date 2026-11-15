#!/usr/bin/env bash
# Renders this repo with the platform's own installer into a temp dir and diffs
# it against ~/.claude. Prints a short summary; the full diff goes to drift.patch.
#   bash .claude/skills/sync-claude-config/drift.sh
set -euo pipefail

die() { printf 'drift: %s\n' "$*" >&2; exit 1; }

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
live="$HOME/.claude"
[ -d "$live" ] || die "$live does not exist - nothing to compare against."
work="${TMPDIR:-/tmp}/claude-config-drift"
rm -rf "$work" && mkdir -p "$work/render"
work="$(cd "$work" && pwd)"
render="$work/render"
log="$work/installer.log"
patch="$work/drift.patch"
: > "$patch"

os="$(uname -s)"
case "$os" in
  MINGW*|MSYS*|CYGWIN*) platform=windows; installer="$repo/claude/windows/setup-claude-windows.ps1"
    flags="-SkipToolchain -SkipPlugins -SkipBackup"
    grep -q '^# Model routing' "$live/CLAUDE.md" 2>/dev/null && flags="$flags -WithModelRouting"
    grep -q '"rust-analyzer-lsp@claude-plugins-official": *true' "$live/settings.json" 2>/dev/null && flags="$flags -WithRust" ;;
  Linux)  platform=linux; installer="$repo/claude/wsl/setup-claude-wsl.sh" ;;
  Darwin) platform=macos; installer="$repo/claude/macos/setup-claude-macos.sh" ;;
  *) die "unsupported platform: $os" ;;
esac

if [ "$platform" = windows ]; then
  # flags is split on purpose: it holds only fixed switch names.
  powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$installer")" $flags \
    -ClaudeDirectory "$(cygpath -w "$render")" > "$log" 2>&1 || { tail -n 20 "$log" >&2; die "installer failed, log: $log"; }
  from="$(cygpath -m "$render")"; to="$(cygpath -m "$live")"
else
  [ "$platform" != macos ] || xcode-select -p >/dev/null 2>&1 \
    || die "Command Line Tools missing - run 'xcode-select --install' first."
  command -v python3 >/dev/null 2>&1 || die "python3 is required to render settings.json."
  flags="--skip-toolchain --skip-plugins --skip-backup"
  grep -q '^# Model routing' "$live/CLAUDE.md" 2>/dev/null && flags="$flags --with-model-routing"
  bash "$installer" $flags --claude-dir "$render" > "$log" 2>&1 || { tail -n 20 "$log" >&2; die "installer failed, log: $log"; }
  from="$render"; to="$(cd "$live" && pwd)"
fi

# Put the real home path back where the render wrote its own.
esc_from="$(printf '%s' "$from" | sed 's/[][\.*^$|]/\\&/g')"
esc_to="$(printf '%s' "$to" | sed 's/[&\\|]/\\&/g')"
sed "s|$esc_from|$esc_to|g" "$render/settings.json" > "$work/settings.tmp" && mv "$work/settings.tmp" "$render/settings.json"
! grep -qF "$(basename "$work")" "$render/settings.json" || die "render path survived the rewrite in settings.json."

echo "platform:  $platform ($os)"
echo "installer: ${installer#"$repo"/}"
echo "flags:     $flags"
echo "drift:"
(cd "$render" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) | while IFS= read -r f; do
  if [ ! -e "$live/$f" ]; then echo "  MISSING  $f"; continue; fi
  rc=0; git diff --no-index --ignore-cr-at-eol -- "$render/$f" "$live/$f" >> "$patch" || rc=$?
  case "$rc" in 0) ;; 1) echo "  differs  $f" ;; *) die "git diff failed ($rc) on $f" ;; esac
done

# ponytail: top-level entries only - an extra file inside a shipped dir (say
# skills/graphify/) is not reported; walk the tree if that ever matters.
echo "candidate additions:"
for d in agents hooks skills; do
  for e in "$live/$d"/*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    n="$(basename "$e")"
    case "$n" in *.bak) continue ;; esac
    [ -e "$render/$d/$n" ] || echo "  $d/$n"
  done
done
# Native form on Windows, so the Read tool can open it.
if [ "$platform" = windows ]; then patch="$(cygpath -m "$patch")"; fi
echo "patch:     $patch"
