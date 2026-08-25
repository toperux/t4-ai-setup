#!/usr/bin/env bash
#
# Installs the GitHub Copilot CLI user-level setup on macOS: CLI prerequisites
# plus the bundled ~/.copilot configuration.
#
#   bash setup-copilot-macos.sh
#   bash setup-copilot-macos.sh --skip-toolchain --skip-plugins
#
# Version policy - nothing already installed is upgraded; these apply only when
# a command is missing. git, jq, python3, uv, node and copilot come from
# Homebrew; rustup, graphify, the language servers and rtk track latest. rtk is
# built from git HEAD of rtk-ai/rtk, NOT the unrelated crates.io crate of the
# same name. The .NET SDK resolves to the newest LTS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_SOURCE="$SCRIPT_DIR/../shared"
CONFIG_SOURCE="$SCRIPT_DIR/config"
COPILOT_DIR="$HOME/.copilot"
SKIP_TOOLCHAIN=0
SKIP_PLUGINS=0
SKIP_BACKUP=0

# copilot-instructions.md is assembled at install time from a platform-neutral
# core plus a per-platform appendix, so the ~70 shared lines are not duplicated
# across the Windows, WSL and macOS overlays. The two halves are a byte cut of
# the original file, so `cat` reproduces it exactly - no re-encoding and no
# line-ending changes, which matters here because this file is CRLF throughout
# while its Claude counterpart is LF.
COMPOSED_OUTPUT="copilot-instructions.md"
COMPOSED_CORE="copilot-instructions.core.md"
COMPOSED_APPEND="copilot-instructions.append.md"

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-toolchain) SKIP_TOOLCHAIN=1 ;;
    --skip-plugins)   SKIP_PLUGINS=1 ;;
    --skip-backup)    SKIP_BACKUP=1 ;;
    --shared-source)  SHARED_SOURCE="${2:?--shared-source requires a path}"; shift ;;
    --config-source)  CONFIG_SOURCE="${2:?--config-source requires a path}"; shift ;;
    --copilot-dir)    COPILOT_DIR="${2:?--copilot-dir requires a path}"; shift ;;
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
[ "$(uname -s)" = "Darwin" ] || die "This installer targets macOS. On Linux or WSL use copilot/wsl/setup-copilot-wsl.sh."

# Canonicalise every path before comparing. A relative or trailing-slash
# --copilot-dir would otherwise slip past the guards and the copy could end up
# deleting its own source.
[ -d "$SHARED_SOURCE" ] || die "Shared config source not found: $SHARED_SOURCE"
[ -d "$CONFIG_SOURCE" ] || die "Platform config source not found: $CONFIG_SOURCE"
SHARED_SOURCE="$(cd "$SHARED_SOURCE" && pwd)"
CONFIG_SOURCE="$(cd "$CONFIG_SOURCE" && pwd)"
mkdir -p "$COPILOT_DIR"
COPILOT_DIR="$(cd "$COPILOT_DIR" && pwd)"
for root in "$SHARED_SOURCE" "$CONFIG_SOURCE"; do
  [ "$root" != "$COPILOT_DIR" ] || die "The config source must not be the destination directory."
  case "$root" in "$COPILOT_DIR"/*)
    die "The config source must not live inside the destination ($COPILOT_DIR)." ;;
  esac
done

# python3 strips the graphify block and validates JSON, and all five hooks are
# invoked as `python3`.
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
# Kit), which has no `gain` subcommand.
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

install_dotnet() {
  have dotnet && return 0
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

  # The Copilot CLI itself, from the official cask rather than the install
  # script the WSL port uses: on a machine that already has Homebrew set up,
  # this is the route GitHub documents for macOS and it keeps `brew upgrade`
  # working afterwards. It is a cask, not a formula, so brew_install's
  # `brew install <formula>` will not do.
  if ! have copilot; then
    say "Installing GitHub Copilot CLI"
    brew install --cask copilot-cli || warn "The Copilot CLI cask failed to install."
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
      warn "Install a newer Node (nvm, or brew upgrade node) if the typescript LSP misbehaves."
    fi
  fi

  install_dotnet

  # rtk: a preToolUse hook routes every shell command through `rtk hook copilot`.
  # Without it on PATH, every shell call errors.
  #
  # Installed from git, NOT crates.io. The crates.io `rtk` name is owned by an
  # unrelated project ("The CLI for Rust Type Kit", v0.1.0), so
  # `cargo install rtk` silently installs the wrong tool.
  if have rtk && ! correct_rtk; then
    warn "A different 'rtk' is on PATH: $(command -v rtk)"
    warn "This is the Rust Type Kit name collision - it does not implement 'rtk hook copilot',"
    warn "so every shell tool call would fail. Replacing it with Rust Token Killer."
  fi
  if ! have rtk || ! correct_rtk; then
    have cargo || die "cargo is required to build rtk. Install Rust, then re-run."
    say "Installing rtk from github.com/rtk-ai/rtk (a few minutes)"
    cargo install --git https://github.com/rtk-ai/rtk rtk --locked --force \
      || warn "rtk installation failed. Remove hooks/rtk.json, or retry."
  fi

  # graphify: backs the bundled debug skill's graph queries and the two graphify
  # hooks. The PyPI package is spelled with two y's.
  if ! have graphify; then
    if have uv; then
      say "Installing graphify"
      uv tool install graphifyy || warn "graphify installation failed."
    else
      warn "uv missing; cannot install graphify."
    fi
  fi

  # Language servers behind the three entries in lsp-config.json.
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

backup_copilot_dir() {
  # The backup is the only undo path for an existing config, so a missing git is
  # a hard stop rather than a silent overwrite.
  have git || die "git is not on PATH, so $COPILOT_DIR cannot be backed up before it is overwritten.
Install git (or re-run without --skip-toolchain), or pass --skip-backup to overwrite with no undo path."

  # Only ever reuse a repo rooted *here*. `rev-parse --is-inside-work-tree` is
  # also true when an ancestor is a repo, which is the normal case for dotfiles
  # setups where $HOME itself is tracked; committing into that would sweep up
  # unrelated $HOME files and make the restore command below revert far more
  # than ~/.copilot.
  #
  # Testing for .git here, rather than comparing `rev-parse --show-toplevel`
  # against the path: git reports the *physical* path while `cd`+`pwd` reports
  # the logical one, so a single symlink anywhere in between makes the two
  # differ and an existing repo look brand new - at which point the branch below
  # would rewrite someone's .gitignore. Not hypothetical on macOS, where /tmp
  # and /var are symlinks into /private. A .git that is a file rather than a
  # directory is a linked worktree or submodule: still a root, still not ours.
  local entry
  if [ -e "$COPILOT_DIR/.git" ]; then
    # Someone else's repo. Whatever it tracks and whatever its .gitignore says is
    # their decision - they may well be relying on it to restore sessions.
    # Commit what is about to be overwritten and change nothing else: no
    # .gitignore edits, no untracking. Adding an ignore rule here would not
    # untrack what is already in the repo, but it WOULD stop `git add` from
    # picking up new files underneath, so tomorrow's sessions would silently
    # stop being backed up while yesterday's stayed.
    say "Using the existing repo in $COPILOT_DIR as-is; its .gitignore is left alone."
  else
    say "Initialising a backup repo in $COPILOT_DIR"
    git -C "$COPILOT_DIR" init -q

    # Only ever written for a repo this script just created, where nothing is
    # tracked yet and so nothing can be lost. It keeps our own residue from an
    # interrupted run and the bulk runtime state out from the start - the latter
    # is megabytes per commit and no use as an undo point. session-store.db
    # alone runs to megabytes and its -wal changes on every interaction.
    #
    # There is no credential entry, unlike ~/.claude: ~/.copilot has no token
    # file, and config.json is user settings worth keeping.
    local gitignore="$COPILOT_DIR/.gitignore"
    for entry in ".copilot-setup-staging-*" ".copilot-setup-backup-*" \
                 "chats/" "jb/" "session-state/" "sidebar-sessions-state/" \
                 "logs/" "ide/" "run/" "restart/" "media-cache/" \
                 "data.db" "data.db-shm" "data.db-wal" \
                 "session-store.db" "session-store.db-shm" "session-store.db-wal" \
                 "command-history-state.json" "vscode.session.metadata.cache.json" \
                 ".DS_Store"; do
      grep -qxF "$entry" "$gitignore" 2>/dev/null || echo "$entry" >> "$gitignore"
    done
  fi

  git -C "$COPILOT_DIR" config user.name  >/dev/null 2>&1 || git -C "$COPILOT_DIR" config user.name  "Copilot setup backup"
  git -C "$COPILOT_DIR" config user.email >/dev/null 2>&1 || git -C "$COPILOT_DIR" config user.email "copilot-setup@localhost"

  git -C "$COPILOT_DIR" add --all
  git -C "$COPILOT_DIR" commit --allow-empty -q -m "Backup before Copilot setup replication"
  say "Snapshot committed - restore with: git -C $COPILOT_DIR checkout HEAD -- ."
}

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

# Every file the package ships, as paths relative to a config root. Two roots
# are merged - the platform-neutral `shared` tree and the per-platform overlay -
# with the overlay winning on a collision. Enumerating rather than hardcoding
# means a file added to either tree is picked up automatically, and anything NOT
# shipped - your own instructions, your own prompts and skills - is left alone.
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

# What actually lands in ~/.copilot: everything shipped, minus the two halves of
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
  local staging="$COPILOT_DIR/.copilot-setup-staging-$$"
  local backup="$COPILOT_DIR/.copilot-setup-backup-$$"
  local backed_up=() created=() rollback_failed=0
  mkdir -p "$staging" "$backup"

  rollback() {
    local r
    for r in "${created[@]:-}"; do
      [ -n "$r" ] && rm -f "$COPILOT_DIR/$r"
    done
    for r in "${backed_up[@]:-}"; do
      [ -n "$r" ] || continue
      mkdir -p "$(dirname "$COPILOT_DIR/$r")"
      mv -f "$backup/$r" "$COPILOT_DIR/$r" || rollback_failed=1
    done
    if [ "$rollback_failed" -eq 1 ]; then
      warn "Configuration rollback FAILED. Recovery data remains at $backup."
    else
      rm -rf "$backup"
      warn "Install failed partway through; $COPILOT_DIR was restored to its previous state."
    fi
    rm -rf "$staging"
  }
  trap 'rollback' ERR

  # Everything except the two composed halves. Unlike the Claude package there
  # is no template step: settings.json and lsp-config.json hold no paths and no
  # shell, so they are copied verbatim like every other file.
  #
  # `while read` rather than `for rel in $(...)`, so a config file whose name
  # contains a space is copied rather than split into two nonexistent paths.
  # Process substitution, not a pipe, so the arrays below stay in this shell.
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    mkdir -p "$staging/$(dirname "$rel")"
    cp "$(resolve_source "$rel")" "$staging/$rel"
  done < <(shipped_files | grep -vxF -e "$COMPOSED_CORE" -e "$COMPOSED_APPEND")

  # copilot-instructions.md is the two halves joined byte for byte.
  core="$(resolve_source "$COMPOSED_CORE")"
  append="$(resolve_source "$COMPOSED_APPEND")"
  cat "$core" "$append" > "$staging/$COMPOSED_OUTPUT"

  # The hooks are deliberately NOT made executable. They ship CRLF, like the
  # rest of this package, so `./hook.py` would fail with a
  # "bad interpreter: /usr/bin/env python3^M" - their shebang is decoration.
  # copilot-hooks.json invokes them as `python3 <path>`, which is unaffected.

  # Swap staged files in, remembering what was replaced so it can be put back.
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    mkdir -p "$(dirname "$COPILOT_DIR/$rel")"
    if [ -e "$COPILOT_DIR/$rel" ]; then
      mkdir -p "$(dirname "$backup/$rel")"
      mv "$COPILOT_DIR/$rel" "$backup/$rel"
      backed_up+=("$rel")
    else
      created+=("$rel")
    fi
    mv "$staging/$rel" "$COPILOT_DIR/$rel"
  done < <(installed_files)

  trap - ERR
  rm -rf "$staging" "$backup"
  say "Configuration written to $COPILOT_DIR"
}

# ---------------------------------------------------------------------------
# graphify
# ---------------------------------------------------------------------------

# `graphify install` appends a skill-registration block to copilot-instructions.md.
# That is redundant here: the two graphify hooks already prompt for
# `graphify query` before searching and `graphify update .` after edits.
# Stripping it on every run also keeps re-runs from re-adding it.
strip_graphify_section() {
  python3 - "$1" <<'PY'
import sys
path = sys.argv[1]
raw = open(path, "rb").read().decode("utf-8")
# Rebuild with the file's own newline. copilot-instructions.md is CRLF and the
# Claude equivalent is LF; hardcoding either would silently convert the other.
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
    warn "Run this once it is installed:  graphify install --platform copilot"
    return 0
  fi
  # graphify writes to the real home directory and ignores --copilot-dir, so only
  # run it when they are the same place.
  if [ "$COPILOT_DIR" != "$HOME/.copilot" ]; then
    warn "Target is not $HOME/.copilot, so the graphify skill was not installed."
    warn "Run 'graphify install --platform copilot' yourself to add it."
    return 0
  fi
  if ! graphify install --platform copilot >/dev/null 2>&1; then
    warn "'graphify install --platform copilot' failed."
    return 0
  fi
  say "graphify skill installed at the user level."
  if strip_graphify_section "$COPILOT_DIR/$COMPOSED_OUTPUT"; then
    say "  removed its redundant instructions block (hooks already cover it)."
  fi
}

# ---------------------------------------------------------------------------
# Plugins
# ---------------------------------------------------------------------------

MARKETPLACES="DietrichGebert/ponytail"
PLUGINS="ponytail@ponytail"

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
  if ! have copilot; then
    warn "The 'copilot' CLI is not on PATH, so plugins were not installed."
    warn "settings.json already enables them, so a first run should fetch them. Otherwise run:"
    local m p
    for m in $MARKETPLACES; do warn "  copilot plugin marketplace add $m"; done
    for p in $PLUGINS;      do warn "  copilot plugin install $p"; done
    return 0
  fi

  # Point the CLI at the directory being set up; it defaults to ~/.copilot and
  # would otherwise ignore --copilot-dir entirely.
  local previous_home="${COPILOT_HOME-}"
  export COPILOT_HOME="$COPILOT_DIR"

  local known name source p installed
  known="$(copilot plugin marketplace list 2>&1 || true)"
  for source in $MARKETPLACES; do
    # `copilot plugin marketplace list` reports the repository name, not the
    # owner/repo the marketplace was added by.
    name="${source##*/}"
    if ! listed "$known" "$name"; then
      copilot plugin marketplace add "$source" 2>&1 \
        || warn "Could not add marketplace $source; continuing."
    fi
    copilot plugin marketplace update "$name" >/dev/null 2>&1 \
      || warn "Could not update marketplace $name; continuing."
  done

  installed="$(copilot plugin list 2>&1 || true)"
  for p in $PLUGINS; do
    if listed "$installed" "$p"; then continue; fi
    if ! copilot plugin install "$p" 2>&1; then
      warn "'copilot plugin install $p' returned non-zero."
      continue
    fi
    installed="$(copilot plugin list 2>&1 || true)"
    listed "$installed" "$p" || warn "$p does not appear in 'copilot plugin list' after installing it."
  done

  if [ -n "$previous_home" ]; then
    export COPILOT_HOME="$previous_home"
  else
    unset COPILOT_HOME
  fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

if [ "$SKIP_TOOLCHAIN" -eq 0 ]; then
  install_toolchain
fi

python_ready || die "python3 is still not usable, so the hooks would fail on every tool call.
Install it (brew install python) and re-run."

if [ "$SKIP_BACKUP" -eq 1 ]; then
  warn "--skip-backup: $COPILOT_DIR is being overwritten with no undo path."
else
  backup_copilot_dir
fi

copy_configuration
install_graphify_skill

[ "$SKIP_PLUGINS" -eq 0 ] && install_plugins

# --- verification ----------------------------------------------------------

if [ "$SKIP_TOOLCHAIN" -eq 0 ]; then
  missing=""
  for c in git python3 uv graphify jq rustup rtk node dotnet csharp-ls rust-analyzer copilot; do
    have "$c" || missing="$missing $c"
  done
  if [ -n "$missing" ]; then
    warn "Not on PATH after setup:$missing"
    warn "Open a new terminal (PATH was updated) and re-check before reporting a failure."
  fi

  # Presence is not enough: confirm it is Rust Token Killer, not the collision.
  if have rtk && ! correct_rtk; then
    warn "'rtk' resolves to the wrong tool ($(command -v rtk)) - 'rtk gain' does not work."
    warn "Every shell tool call will fail. Fix with:"
    warn "  cargo install --git https://github.com/rtk-ai/rtk rtk --locked --force"
  fi
fi

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  [ -f "$COPILOT_DIR/$rel" ] || die "Expected $rel in $COPILOT_DIR after the copy, but it is missing."
  case "$rel" in *.json)
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$COPILOT_DIR/$rel" \
      || die "$rel was installed but is not valid JSON." ;;
  esac
done < <(installed_files)

# The composed instructions file must stay pure CRLF: a bare LF would mean one
# of the two halves was re-encoded somewhere between the repo and here.
python3 - "$COPILOT_DIR/$COMPOSED_OUTPUT" <<'PY' || warn "copilot-instructions.md has mixed line endings."
import sys
raw = open(sys.argv[1], "rb").read()
raise SystemExit(0 if raw.count(b"\n") == raw.count(b"\r\n") else 1)
PY

echo
say "Setup complete. Restart the terminal, then run: copilot"
say "Log in with your own account - no credentials were copied."
