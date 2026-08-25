#!/usr/bin/env bash
#
# Downloads the t4-ai-setup repository and runs the GitHub Copilot CLI installer
# for macOS. Intended to be fetched and executed in one line:
#
#   curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-copilot-macos.sh | bash
#
# Installer flags pass straight through after `-s --`:
#
#   curl -fsSL https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-copilot-macos.sh | bash -s -- --skip-toolchain
#
# Everything this script does is visible above the fold - drop the `| bash` to
# read it before running it.
set -euo pipefail

REPO="toperux/t4-ai-setup"
# Branch, tag or commit SHA to install from. Pin this for a fixed version - and
# pin it even when you fetched this script from a tagged URL, because the ref
# you fetched from is not carried over.
REF="main"

ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) REF="${2:?--ref requires a value}"; shift ;;
    *)     ARGS+=("$1") ;;
  esac
  shift
done

[ "$(uname -s)" = "Darwin" ] || { echo "This installer targets macOS. On WSL use install-copilot-wsl.sh." >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }
command -v tar  >/dev/null 2>&1 || { echo "tar is required." >&2; exit 1; }

WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/t4-ai-setup.XXXXXX")"
cleanup() { rm -rf "$WORKSPACE"; }
trap cleanup EXIT

# A tarball, not a clone: the installer is what provisions git, so the bootstrap
# must not require it. A tarball rather than a zip because it preserves the
# executable bit, which the zip does not.
#
# The bare /archive/<ref>.tar.gz form resolves branches, tags and commit SHAs
# alike; /archive/refs/heads/<ref>.tar.gz resolves branches only and 404s on
# every tag.
URL="https://github.com/$REPO/archive/$REF.tar.gz"
echo "Downloading $URL"
curl -fsSL "$URL" -o "$WORKSPACE/repo.tar.gz"

# GitHub names the archive's root directory after the ref, so strip it rather
# than guessing "t4-ai-setup-main".
mkdir -p "$WORKSPACE/repo"
tar -xzf "$WORKSPACE/repo.tar.gz" -C "$WORKSPACE/repo" --strip-components=1

INSTALLER="$WORKSPACE/repo/copilot/macos/setup-copilot-macos.sh"
[ -f "$INSTALLER" ] || { echo "Expected the installer at $INSTALLER, but it is missing." >&2; exit 1; }

bash "$INSTALLER" ${ARGS[@]+"${ARGS[@]}"}
