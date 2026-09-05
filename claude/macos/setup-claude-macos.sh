#!/usr/bin/env bash
#
# Installs the Claude Code user-level setup on macOS: CLI prerequisites plus the
# bundled ~/.claude configuration.
#
#   bash setup-claude-macos.sh
#   bash setup-claude-macos.sh --skip-toolchain --skip-plugins
#
# Version policy - nothing already installed is upgraded; these apply only when
# a command is missing. git, jq, python3, uv and Node come from Homebrew; rustup,
# graphify, the language servers and rtk track latest. rtk is built from git HEAD
# of rtk-ai/rtk, NOT the unrelated crates.io crate of the same name.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_SOURCE="$SCRIPT_DIR/../shared"
CONFIG_SOURCE="$SCRIPT_DIR/config"
CLAUDE_DIR="$HOME/.claude"
SKIP_TOOLCHAIN=0
SKIP_PLUGINS=0
SKIP_BACKUP=0

# CLAUDE.md is assembled at install time from a platform-neutral core plus a
# per-platform appendix, so the ~70 shared lines are not duplicated across the
# Windows, WSL and macOS overlays. The two halves are a byte cut of the original
# file, so `cat` reproduces it exactly - no re-encoding, no line-ending changes.
COMPOSED_OUTPUT="CLAUDE.md"
COMPOSED_CORE="CLAUDE.core.md"
COMPOSED_APPEND="CLAUDE.append.md"

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-toolchain) SKIP_TOOLCHAIN=1 ;;
    --skip-plugins)   SKIP_PLUGINS=1 ;;
    --skip-backup)    SKIP_BACKUP=1 ;;
    --shared-source)  SHARED_SOURCE="${2:?--shared-source requires a path}"; shift ;;
    --config-source)  CONFIG_SOURCE="${2:?--config-source requires a path}"; shift ;;
    --claude-dir)     CLAUDE_DIR="${2:?--claude-dir requires a path}"; shift ;;
    -h|--help)        sed -n '3,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

say()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mxx\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# The BSD/Homebrew assumptions below hold nowhere else, and the WSL script is
# the right one for Linux. Fail on the first line rather than halfway through.
[ "$(uname -s)" = "Darwin" ] || die "This installer targets macOS. On Linux or WSL use claude/wsl/setup-claude-wsl.sh."

# Canonicalise every path before comparing. A relative or trailing-slash
# --claude-dir would otherwise slip past the guards and the copy could end up
# deleting its own source.
[ -d "$SHARED_SOURCE" ] || die "Shared config source not found: $SHARED_SOURCE"
[ -d "$CONFIG_SOURCE" ] || die "Platform config source not found: $CONFIG_SOURCE"
SHARED_SOURCE="$(cd "$SHARED_SOURCE" && pwd)"
CONFIG_SOURCE="$(cd "$CONFIG_SOURCE" && pwd)"
mkdir -p "$CLAUDE_DIR"
CLAUDE_DIR="$(cd "$CLAUDE_DIR" && pwd)"
for root in "$SHARED_SOURCE" "$CONFIG_SOURCE"; do
  [ "$root" != "$CLAUDE_DIR" ] || die "The config source must not be the destination directory."
  case "$root" in "$CLAUDE_DIR"/*)
    die "The config source must not live inside the destination ($CLAUDE_DIR)." ;;
  esac
done

# python3 renders settings.json, strips the graphify block and validates JSON,
# and the two hooks are invoked as `python3`.
#
# `command -v python3` is not enough on macOS: /usr/bin/python3 is a stub that
# exists on a machine with no Command Line Tools and only prompts to install
# them when run. Execute it instead of looking for it.
python_ready() { python3 -c 'import sys' >/dev/null 2>&1; }
if ! python_ready && [ "$SKIP_TOOLCHAIN" -eq 1 ]; then
  die "python3 is required. Install it (brew install python, or xcode-select --install) and re-run,
or drop --skip-toolchain and let this script install it."
fi

# Distinguishes Rust Token Killer from the unrelated crates.io `rtk` (Rust Type
# Kit), which has no `gain` subcommand. This is the check RTK.md prescribes.
correct_rtk() { rtk gain >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# PATH
# ---------------------------------------------------------------------------

persist_line() {
  local line="$1" profile
  # ~/.zprofile is written whether or not it already exists, because zsh has been
  # the login shell since Catalina and that file is what decides what a new
  # terminal sees. The others are only appended to when they are already there -
  # creating them would be presumptuous. Writing only-if-exists across the board
  # would strand someone who has just a ~/.bash_profile: the line would land
  # somewhere their login shell never reads.
  for profile in "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    [ "$profile" = "$HOME/.zprofile" ] || [ -f "$profile" ] || continue
    grep -qxF "$line" "$profile" 2>/dev/null || printf '\n%s\n' "$line" >> "$profile"
  done
}

# Prepend for this run, and persist so a new terminal keeps it.
add_path() {
  local dir="$1"
  [ -n "$dir" ] && [ "$dir" != "/bin" ] || return 0
  case ":$PATH:" in *":$dir:"*) ;; *) PATH="$dir:$PATH" ;; esac
  # Only ever persist a directory under $HOME. Homebrew's own bin is already
  # handled by `brew shellenv`, and `npm config get prefix` under Homebrew is
  # the brew prefix - writing that into every profile is pure pollution.
  case "$dir" in "$HOME"/*) ;; *) return 0 ;; esac
  persist_line "export PATH=\"$dir:\$PATH\""
}

# ---------------------------------------------------------------------------
# Homebrew
# ---------------------------------------------------------------------------

install_homebrew() {
  if ! have brew; then
    say "Installing Homebrew (it will ask for your password)"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || warn "The Homebrew installer failed."
  fi

  # Homebrew does not put itself on PATH: /opt/homebrew on Apple Silicon and
  # /usr/local on Intel, neither of which a fresh login shell knows about.
  local prefix
  for prefix in /opt/homebrew /usr/local; do
    if [ -x "$prefix/bin/brew" ]; then
      eval "$("$prefix/bin/brew" shellenv)"
      # ...and persist it, or a new terminal loses brew and everything it
      # installed. The installer only prints this instruction; it does not run it.
      persist_line "eval \"\$($prefix/bin/brew shellenv)\""
      break
    fi
  done
  have brew || die "Homebrew is required and is not on PATH. If its installer failed above, run it
yourself (https://brew.sh), then re-run this script - or pass --skip-toolchain to
install only the configuration."
}

# brew_install <command> <formula>
brew_install() {
  local cmd="$1" formula="$2"
  have "$cmd" && return 0
  say "Installing $formula via Homebrew"
  brew install "$formula" || { warn "Failed to install $formula."; return 1; }
}

# ---------------------------------------------------------------------------
# Toolchain
# ---------------------------------------------------------------------------

# `have dotnet` is the wrong question: the runtime ships the same `dotnet` host,
# so a runtime-only machine has it on PATH with nothing behind it. Verified on
# both Linux and Windows - `dotnet --list-sdks` prints nothing and still exits 0
# there, and `dotnet tool install` then fails with "No .NET SDKs were found"
# (exit 155), which is unrecognisable that far from the cause.
have_dotnet_sdk() {
  have dotnet && [ -n "$(dotnet --list-sdks 2>/dev/null)" ]
}

install_dotnet() {
  have_dotnet_sdk && return 0
  # Microsoft's own script, with the channel that *means* "the newest LTS" - so
  # this needs no editing when .NET 11 ships.
  #
  # Homebrew cannot express that policy. There are dotnet-sdk@8 and @9 casks but
  # no @10, so the current LTS is only reachable as the unversioned `dotnet-sdk`
  # cask - which silently stops being LTS the day 11 is released. The script also
  # installs under $HOME with no sudo, where the cask can want a password.
  #
  # Best-effort either way: csharp-ls is the only casualty if it does not land.
  say "Installing the .NET SDK (latest LTS, for csharp-ls)"
  if curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS; then
    add_path "$HOME/.dotnet"
    # The script installs to $HOME/.dotnet, which is not where macOS looks by
    # default (/usr/local/share/dotnet). A global tool's launcher finds its
    # runtime through DOTNET_ROOT, so csharp-ls would not start without this.
    export DOTNET_ROOT="$HOME/.dotnet"
    persist_line "export DOTNET_ROOT=\"\$HOME/.dotnet\""
    have_dotnet_sdk || warn "The .NET install reports no SDK; csharp-ls will be skipped."
  else
    warn "The .NET SDK did not install; csharp-ls will be skipped."
    warn "Install it manually from https://dot.net and re-run."
  fi
  add_path "$HOME/.dotnet/tools"
}

install_toolchain() {
  install_homebrew

  brew_install git git || true
  brew_install jq  jq  || true
  brew_install uv  uv  || true

  # Gated on python_ready, NOT on `have python3`. /usr/bin/python3 exists as a
  # Command Line Tools stub on a Mac that has none, so a presence check passes,
  # Homebrew's python is never installed, and the run then dies at the
  # python_ready gate after the toolchain step - having installed everything
  # else first.
  if ! python_ready; then
    say "Installing python via Homebrew"
    brew install python || warn "Failed to install python."
  fi

  # uv tool binaries (graphify) and dotnet global tools.
  add_path "$HOME/.local/bin"
  add_path "$HOME/.dotnet/tools"

  # Claude Code itself. Anthropic's installer: user-scope, checksum-verified
  # against a signed manifest, lands in ~/.local/bin, and refuses to run under
  # sudo. Only when missing, so an existing install is never upgraded - and a
  # running one is never replaced, because a running one is not missing.
  if ! have claude; then
    say "Installing Claude Code"
    curl -fsSL https://claude.ai/install.sh | bash || warn "The Claude Code installer failed."
    add_path "$HOME/.local/bin"
  fi

  # Rust toolchain (rustup) - backs both rtk and rust-analyzer. From rustup.rs
  # rather than Homebrew, so `rustup component add` works the same way it does
  # on the other two platforms.
  if ! have rustup && ! have cargo; then
    say "Installing Rust via rustup"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path \
      || warn "rustup install failed."
  fi
  add_path "$HOME/.cargo/bin"

  # `have cargo` above only proves rustup's proxy shim is on PATH: rustup
  # creates cargo, rustc and rust-analyzer proxies from a fixed list whether or
  # not a toolchain is installed. rustup.rs -y does leave a default, but a
  # rustup that was already on the machine may not have one, and the shim then
  # fails with "could not choose a version of cargo to run ... no default is
  # configured" - which is what killed the Windows run this mirrors.
  # `show active-toolchain` exits non-zero in exactly that state, and installing
  # stable also makes it the default when there is none.
  if have rustup && ! rustup show active-toolchain >/dev/null 2>&1; then
    say "Installing the Rust stable toolchain"
    rustup toolchain install stable || warn "Rust stable toolchain install failed."
  fi

  # Node - backs the TypeScript language server. nvm-managed shells expose node
  # only as a shell function, so probe for nvm before falling back to Homebrew.
  if ! have node && [ ! -s "$HOME/.nvm/nvm.sh" ]; then
    brew_install node node || true
  fi
  # nvm.sh references unset variables; sourcing it under `set -u` aborts the run.
  if [ -s "$HOME/.nvm/nvm.sh" ]; then
    set +u
    . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 || true
    set -u
  fi
  if have npm; then
    add_path "$(npm config get prefix 2>/dev/null || echo "$HOME/.npm-global")/bin"
  fi
  if have node; then
    local major
    major="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/')"
    if [ -n "$major" ] && [ "$major" -lt 18 ] 2>/dev/null; then
      warn "Node $major is older than the TypeScript language server supports (needs 18+)."
      warn "Install a newer Node (nvm, or brew upgrade node) if the typescript-lsp plugin misbehaves."
    fi
  fi

  install_dotnet

  # rtk: the Bash PreToolUse hook shells out to `rtk hook claude` on every Bash
  # tool call. Without it on PATH, every Bash call errors.
  #
  # Installed from git, NOT crates.io. The crates.io `rtk` name is owned by an
  # unrelated project ("The CLI for Rust Type Kit", v0.1.0), so
  # `cargo install rtk` silently installs the wrong tool. See RTK.md.
  if have rtk && ! correct_rtk; then
    warn "A different 'rtk' is on PATH: $(command -v rtk)"
    warn "This is the Rust Type Kit name collision - it does not implement 'rtk hook claude',"
    warn "so every Bash tool call would fail. Replacing it with Rust Token Killer."
  fi
  if ! have rtk || ! correct_rtk; then
    have cargo || die "cargo is required to build rtk. Install Rust, then re-run."
    say "Installing rtk from github.com/rtk-ai/rtk (a few minutes)"
    cargo install --git https://github.com/rtk-ai/rtk rtk --locked --force \
      || warn "rtk installation failed. Remove the 'rtk hook claude' entry from settings.json, or retry."
  fi

  # graphify: backs the bundled graphify skill and its two hooks.
  if ! have graphify; then
    if have uv; then
      say "Installing graphify"
      uv tool install graphifyy || warn "graphify installation failed."
    else
      warn "uv missing; cannot install graphify."
    fi
  fi

  # Language servers behind the three official LSP plugins.
  if ! have typescript-language-server && have npm; then
    say "Installing TypeScript language server"
    npm install --global typescript typescript-language-server || warn "TypeScript LSP install failed."
  fi
  if ! have csharp-ls && have dotnet; then
    say "Installing C# language server"
    dotnet tool install --global csharp-ls || warn "csharp-ls install failed."
  fi
  # Run it rather than look for it: rust-analyzer is one of the proxies rustup
  # always creates, so `have rust-analyzer` is true even when the component is
  # missing and the shim only exits 1 with "Unknown binary".
  if have rustup && ! rust-analyzer --version >/dev/null 2>&1; then
    say "Installing rust-analyzer"
    rustup component add rust-analyzer || warn "rust-analyzer install failed."
  fi
}

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

backup_claude_dir() {
  # The backup is the only undo path for an existing config, so a missing git is
  # a hard stop rather than a silent overwrite.
  have git || die "git is not on PATH, so $CLAUDE_DIR cannot be backed up before it is overwritten.
Install git (or re-run without --skip-toolchain), or pass --skip-backup to overwrite with no undo path."

  # Only ever reuse a repo rooted *here*. `rev-parse --is-inside-work-tree` is
  # also true when an ancestor is a repo, which is the normal case for dotfiles
  # setups where $HOME itself is tracked; committing into that would sweep up
  # unrelated $HOME files and make the restore command below revert far more
  # than ~/.claude.
  #
  # Testing for .git here, rather than comparing `rev-parse --show-toplevel`
  # against the path: git reports the *physical* path while `cd`+`pwd` reports
  # the logical one, so a single symlink anywhere in between makes the two
  # differ and an existing repo look brand new - at which point the branch below
  # would rewrite someone's .gitignore. Not hypothetical on macOS, where /tmp
  # and /var are symlinks into /private. A .git that is a file rather than a
  # directory is a linked worktree or submodule: still a root, still not ours.
  local entry
  if [ -e "$CLAUDE_DIR/.git" ]; then
    # Someone else's repo. Whatever it tracks and whatever its .gitignore says is
    # their decision - they may well be relying on it to restore sessions and
    # history. Commit what is about to be overwritten and change nothing else:
    # no .gitignore edits, no untracking. Adding an ignore rule here would not
    # untrack what is already in the repo, but it WOULD stop `git add` from
    # picking up new files underneath, so tomorrow's sessions would silently
    # stop being backed up while yesterday's stayed.
    say "Using the existing repo in $CLAUDE_DIR as-is; its .gitignore is left alone."
  else
    say "Initialising a backup repo in $CLAUDE_DIR"
    git -C "$CLAUDE_DIR" init -q

    # Only ever written for a repo this script just created, where nothing is
    # tracked yet and so nothing can be lost. It keeps OAuth credentials, our own
    # residue from an interrupted run, bulk runtime state and .DS_Store litter
    # out from the start. Bulk state is megabytes per commit and no use as an
    # undo point.
    local gitignore="$CLAUDE_DIR/.gitignore"
    for entry in ".credentials.json" ".claude-setup-staging-*" ".claude-setup-backup-*" \
                 "downloads/" "projects/" "shell-snapshots/" "session-env/" \
                 "file-history/" "cache/" "plugins/" "paste-cache/" "backups/" \
                 "history.jsonl" "stats-cache.json" \
                 "daemon/" "daemon.log" "sessions/" "tasks/" "jobs/" "*.bak" \
                 ".last-*" ".in_use/" ".DS_Store"; do
      grep -qxF "$entry" "$gitignore" 2>/dev/null || echo "$entry" >> "$gitignore"
    done
  fi

  git -C "$CLAUDE_DIR" config user.name  >/dev/null 2>&1 || git -C "$CLAUDE_DIR" config user.name  "Claude setup backup"
  git -C "$CLAUDE_DIR" config user.email >/dev/null 2>&1 || git -C "$CLAUDE_DIR" config user.email "claude-setup@localhost"

  git -C "$CLAUDE_DIR" add --all
  git -C "$CLAUDE_DIR" commit --allow-empty -q -m "Backup before Claude setup replication"

  # Reported, not acted on: this is your repo. `ls-files -- <path>` prints the
  # path when tracked and nothing when not, and always exits 0 - unlike
  # --error-unmatch, whose exit code is the answer and would linger in $?.
  if [ -n "$(git -C "$CLAUDE_DIR" ls-files -- .credentials.json 2>/dev/null)" ]; then
    warn "This repo tracks .credentials.json, which holds live OAuth tokens."
    warn "Left as-is deliberately. To stop committing it, untrack it yourself:"
    warn "  git -C $CLAUDE_DIR rm --cached .credentials.json"
  fi
  say "Snapshot committed - restore with: git -C $CLAUDE_DIR checkout HEAD -- ."
}

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

# Every file the package ships, as paths relative to a config root. Two roots
# are merged - the platform-neutral `shared` tree and the per-platform overlay -
# with the overlay winning on a collision. Enumerating rather than hardcoding
# means a file added to either tree is picked up automatically, and anything NOT
# shipped - your own hooks, your own skills - is simply left alone.
shipped_files() {
  {
    (cd "$SHARED_SOURCE" && find . -type f | sed 's|^\./||')
    (cd "$CONFIG_SOURCE" && find . -type f | sed 's|^\./||')
  } | sort -u
}

# Resolve a relative path to its absolute source, overlay winning.
resolve_source() {
  if [ -f "$CONFIG_SOURCE/$1" ]; then printf '%s' "$CONFIG_SOURCE/$1"
  else printf '%s' "$SHARED_SOURCE/$1"; fi
}

# What actually lands in ~/.claude: everything shipped, minus the two halves of
# the composed file, plus the composed file itself.
installed_files() {
  shipped_files | grep -vxF -e "$COMPOSED_CORE" -e "$COMPOSED_APPEND"
  printf '%s\n' "$COMPOSED_OUTPUT"
}

copy_configuration() {
  local rel core append
  for rel in "$COMPOSED_CORE" "$COMPOSED_APPEND"; do
    [ -f "$(resolve_source "$rel")" ] \
      || die "The platform overlay is incomplete: $rel was not found under $SHARED_SOURCE or $CONFIG_SOURCE."
  done
  [ -f "$(resolve_source settings.json)" ] || die "settings.json was not found in either config source."

  # Stage everything first, then swap it in, so a failure midway leaves the
  # existing config intact rather than half-replaced.
  local staging="$CLAUDE_DIR/.claude-setup-staging-$$"
  local backup="$CLAUDE_DIR/.claude-setup-backup-$$"
  local backed_up=() created=() rollback_failed=0
  mkdir -p "$staging" "$backup"

  rollback() {
    local r
    for r in "${created[@]:-}"; do
      [ -n "$r" ] && rm -f "$CLAUDE_DIR/$r"
    done
    for r in "${backed_up[@]:-}"; do
      [ -n "$r" ] || continue
      mkdir -p "$(dirname "$CLAUDE_DIR/$r")"
      mv -f "$backup/$r" "$CLAUDE_DIR/$r" || rollback_failed=1
    done
    if [ "$rollback_failed" -eq 1 ]; then
      warn "Configuration rollback FAILED. Recovery data remains at $backup."
    else
      rm -rf "$backup"
      warn "Install failed partway through; $CLAUDE_DIR was restored to its previous state."
    fi
    rm -rf "$staging"
  }
  trap 'rollback' ERR

  # Everything except settings.json (templated) and the two composed halves.
  # `while read` rather than `for rel in $(...)`, so a config file whose name
  # contains a space is copied rather than split into two nonexistent paths.
  # Process substitution, not a pipe, so the arrays below stay in this shell.
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    mkdir -p "$staging/$(dirname "$rel")"
    cp "$(resolve_source "$rel")" "$staging/$rel"
  done < <(shipped_files | grep -vxF -e settings.json -e "$COMPOSED_CORE" -e "$COMPOSED_APPEND")

  # CLAUDE.md is the two halves joined byte for byte.
  core="$(resolve_source "$COMPOSED_CORE")"
  append="$(resolve_source "$COMPOSED_APPEND")"
  cat "$core" "$append" > "$staging/$COMPOSED_OUTPUT"

  # settings.json is rendered from the template.
  python3 - "$(resolve_source settings.json)" "$staging/settings.json" "$CLAUDE_DIR" <<'PY'
import sys
src, dst, home = sys.argv[1:4]
with open(src, encoding="utf-8") as f:
    rendered = f.read().replace("__CLAUDE_HOME__", home.rstrip("/"))
with open(dst, "w", encoding="utf-8", newline="") as f:
    f.write(rendered)
PY

  chmod +x "$staging"/hooks/*.py 2>/dev/null || true
  [ -f "$staging/statusline-command.sh" ] && chmod +x "$staging/statusline-command.sh"

  # Swap staged files in, remembering what was replaced so it can be put back.
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    mkdir -p "$(dirname "$CLAUDE_DIR/$rel")"
    if [ -e "$CLAUDE_DIR/$rel" ]; then
      mkdir -p "$(dirname "$backup/$rel")"
      mv "$CLAUDE_DIR/$rel" "$backup/$rel"
      backed_up+=("$rel")
    else
      created+=("$rel")
    fi
    mv "$staging/$rel" "$CLAUDE_DIR/$rel"
  done < <(installed_files)

  trap - ERR
  rm -rf "$staging" "$backup"
  say "Configuration written to $CLAUDE_DIR"
}

# ---------------------------------------------------------------------------
# graphify
# ---------------------------------------------------------------------------

# `graphify install` appends a skill-registration block to CLAUDE.md. That is
# redundant here: Claude Code discovers skills from ~/.claude/skills/ on its own,
# and the two graphify hooks in settings.json already prompt for `graphify query`
# before searching and `graphify update .` after edits. Stripping it on every run
# also keeps re-runs from re-adding it.
strip_graphify_section() {
  python3 - "$1" <<'PY'
import sys
path = sys.argv[1]
raw = open(path, "rb").read().decode("utf-8")
# Rebuild with the file's own newline. CLAUDE.md is LF and the Copilot
# equivalent is CRLF; hardcoding either would silently convert the other.
newline = "\r\n" if "\r\n" in raw else "\n"
lines = raw.split(newline)
start = next((i for i, l in enumerate(lines) if l.strip() == "# graphify"), -1)
if start < 0:
    raise SystemExit(1)
end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("# ")), len(lines))
kept = lines[:start] + lines[end:]
open(path, "w", encoding="utf-8", newline="").write(newline.join(kept).rstrip() + newline)
PY
}

install_graphify_skill() {
  if ! have graphify; then
    warn "graphify is not on PATH, so its skill was not installed."
    warn "Run this once it is installed:  graphify install --platform claude"
    return 0
  fi
  # graphify writes to the real home directory and ignores --claude-dir, so only
  # run it when they are the same place.
  if [ "$CLAUDE_DIR" != "$HOME/.claude" ]; then
    warn "Target is not $HOME/.claude, so the graphify skill was left at the bundled"
    warn "snapshot version. Run 'graphify install --platform claude' yourself to sync it."
    return 0
  fi
  if ! graphify install --platform claude >/dev/null 2>&1; then
    warn "'graphify install --platform claude' failed; keeping the bundled skill snapshot."
    return 0
  fi
  say "graphify skill installed at the user level."
  if strip_graphify_section "$CLAUDE_DIR/$COMPOSED_OUTPUT"; then
    say "  removed its redundant CLAUDE.md registration block (hooks already cover it)."
  fi
}

# ---------------------------------------------------------------------------
# Plugins
# ---------------------------------------------------------------------------

MARKETPLACES="anthropics/claude-plugins-official DietrichGebert/ponytail"
PLUGINS="ponytail@ponytail typescript-lsp@claude-plugins-official csharp-lsp@claude-plugins-official rust-analyzer-lsp@claude-plugins-official"

# Is $2 present in the listing $1 as its own whitespace-delimited token?
#
# Exact string comparison over split tokens rather than a regex: it needs no
# metacharacter escaping and makes no assumption about how the CLI's U+276F
# bullet survives the terminal's encoding. Anchoring a pattern on that bullet is
# what made the Windows checks fail, which meant spurious "not installed"
# warnings and a full reinstall on every run.
listed() {
  local text="$1" name="$2" token found=1
  set -f                       # tokens are compared literally, never globbed
  for token in $text; do
    if [ "$token" = "$name" ]; then found=0; break; fi
  done
  set +f
  return $found
}

install_plugins() {
  if ! have claude; then
    warn "Claude Code CLI ('claude') is not on PATH, so plugins were not installed."
    warn "settings.json already enables them, so a first run should fetch them. Otherwise run:"
    local m p
    for m in $MARKETPLACES; do warn "  claude plugin marketplace add $m"; done
    for p in $PLUGINS;      do warn "  claude plugin install $p"; done
    return 0
  fi

  # Point the CLI at the directory being set up; it defaults to ~/.claude and
  # would otherwise ignore --claude-dir entirely.
  local previous_config_dir="${CLAUDE_CONFIG_DIR-}"
  export CLAUDE_CONFIG_DIR="$CLAUDE_DIR"

  local known name source p installed
  known="$(claude plugin marketplace list 2>&1 || true)"
  for source in $MARKETPLACES; do
    # `claude plugin marketplace list` reports the repository name, not the
    # owner/repo the marketplace was added by.
    name="${source##*/}"
    if ! listed "$known" "$name"; then
      claude plugin marketplace add "$source" 2>&1 \
        || warn "Could not add marketplace $source; continuing."
    fi
  done

  installed="$(claude plugin list 2>&1 || true)"
  for p in $PLUGINS; do
    if listed "$installed" "$p"; then continue; fi
    if ! claude plugin install "$p" 2>&1; then
      warn "'claude plugin install $p' returned non-zero."
      continue
    fi
    installed="$(claude plugin list 2>&1 || true)"
    listed "$installed" "$p" || warn "$p does not appear in 'claude plugin list' after installing it."
  done

  if [ -n "$previous_config_dir" ]; then
    export CLAUDE_CONFIG_DIR="$previous_config_dir"
  else
    unset CLAUDE_CONFIG_DIR
  fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

if [ "$SKIP_TOOLCHAIN" -eq 0 ]; then
  install_toolchain
fi

# Everything from here needs a python3 that actually runs.
python_ready || die "python3 is required but does not run. Install it (brew install python,
or xcode-select --install) and re-run."

if [ "$SKIP_BACKUP" -eq 1 ]; then
  warn "--skip-backup: $CLAUDE_DIR is being overwritten with no undo path."
else
  backup_claude_dir
fi

copy_configuration
install_graphify_skill

[ "$SKIP_PLUGINS" -eq 0 ] && install_plugins

# --- verification ----------------------------------------------------------

if [ "$SKIP_TOOLCHAIN" -eq 0 ]; then
  missing=""
  for c in brew git python3 uv graphify jq rustup rtk node dotnet csharp-ls rust-analyzer claude; do
    have "$c" || missing="$missing $c"
  done
  if [ -n "$missing" ]; then
    warn "Not on PATH after setup:$missing"
    warn "Open a new terminal (PATH was updated) and re-check before reporting a failure."
  fi

  # Presence is not enough: confirm it is Rust Token Killer, not the collision.
  if have rtk && ! correct_rtk; then
    warn "'rtk' resolves to the wrong tool ($(command -v rtk)) - 'rtk gain' does not work."
    warn "Every Bash tool call will fail. Fix with:"
    warn "  cargo install --git https://github.com/rtk-ai/rtk rtk --locked --force"
  fi
fi

# skills/graphify/ is excluded: `graphify install` owns that tree and replaces it
# with whatever the installed graphify version ships, so checking it
# file-by-file would fail purely because graphify moved on. Its SKILL.md is
# asserted separately.
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  [ -f "$CLAUDE_DIR/$rel" ] || die "Expected $rel in $CLAUDE_DIR after the copy, but it is missing."
  case "$rel" in *.json)
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$CLAUDE_DIR/$rel" \
      || die "$rel was installed but is not valid JSON." ;;
  esac
done < <(installed_files | grep -v '^skills/graphify/')
[ -f "$CLAUDE_DIR/skills/graphify/SKILL.md" ] \
  || die "Expected skills/graphify/SKILL.md in $CLAUDE_DIR after the copy, but it is missing."

grep -q "__CLAUDE_HOME__" "$CLAUDE_DIR/settings.json" \
  && die "settings.json still contains the __CLAUDE_HOME__ placeholder."

# The statusline must not crash: it runs on every render.
printf '{"model":{"display_name":"probe"},"context_window":{"used_percentage":1}}' \
  | bash "$CLAUDE_DIR/statusline-command.sh" >/dev/null 2>&1 \
  || warn "statusline-command.sh returned an error on a probe payload."

echo
say "Setup complete. Restart the terminal, then run: claude"
say "Log in with your own account - no credentials were copied."
