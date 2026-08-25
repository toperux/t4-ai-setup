<#
.SYNOPSIS
Installs the Claude Code user-level setup: CLI prerequisites plus the bundled
~/.claude configuration.

.EXAMPLE
.\setup-claude-windows.ps1

.EXAMPLE
.\setup-claude-windows.ps1 -SkipToolchain -SkipPlugins

.NOTES
Version policy - nothing already installed is upgraded; these apply only when a
command is missing.

  Tracks latest automatically:
    git, uv, jq, Rust (rustup stable), graphify (PyPI 'graphifyy'),
    typescript-language-server, csharp-ls, ponytail, and rtk (git HEAD of
    rtk-ai/rtk - NOT the unrelated crates.io crate of the same name).

  Resolved at run time:
    Node.js - newest LTS with an MSI for this architecture, from
              https://nodejs.org/dist/index.json, SHA256-verified.
    .NET    - newest LTS still in active or maintenance support, from the
              official releases-index.json.

  Pinned, needs a human bump:
    Python  -PythonVersion  3.14  (latest stable; revisit when 3.15 ships)
#>
[CmdletBinding()]
param(
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$SharedSource = (Join-Path $PSScriptRoot "..\shared"),

    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$ConfigSource = (Join-Path $PSScriptRoot "config"),

    [string]$ClaudeDirectory = (Join-Path $HOME ".claude"),

    [string]$PythonVersion = "3.14",

    [switch]$SkipToolchain,

    [switch]$SkipPlugins,

    [switch]$SkipBackup
)

$ErrorActionPreference = "Stop"
$script:RestartRequired = $false

$sharedPath = (Resolve-Path $SharedSource).Path
$sourcePath = (Resolve-Path $ConfigSource).Path
$targetPath = [IO.Path]::GetFullPath($ClaudeDirectory)
foreach ($root in @($sharedPath, $sourcePath)) {
    if ($root.TrimEnd("\") -eq $targetPath.TrimEnd("\")) {
        throw "The config source must not be the destination .claude directory."
    }
}

# CLAUDE.md is assembled at install time from a platform-neutral core plus a
# per-platform appendix, so the ~70 shared lines are not duplicated across the
# Windows, WSL and macOS overlays. The two halves are a byte cut of the original
# file, so a raw byte concatenation reproduces it exactly - no re-encoding and
# no line-ending normalisation (this file is LF; the Copilot one is CRLF).
$ComposedFile = @{
    Output = "CLAUDE.md"
    Core   = "CLAUDE.core.md"
    Append = "CLAUDE.append.md"
}

# $ErrorActionPreference = "Stop" makes PowerShell treat ANY native-command
# stderr output as a terminating error - including routine chatter like git's
# CRLF warnings, `npm WARN`, and winget progress. Every external command in this
# script therefore runs through here, and success is judged by $LASTEXITCODE.
function Invoke-Native {
    param([Parameter(Mandatory)][scriptblock]$Script)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Script
    } finally {
        $ErrorActionPreference = $previous
    }
}

# `([string]$null).Trim()` throws on Windows PowerShell 5.1 - [string] of $null
# is $null, not "". Joining first is null-safe: `$null -join ""` is "".
function Get-NativeText {
    param([Parameter(Mandatory)][scriptblock]$Script)

    return ((Invoke-Native $Script) -join "`n").Trim()
}

# Set-Content -Encoding UTF8 emits a UTF-8 BOM on Windows PowerShell 5.1. The
# source files have none, and a BOM can break strict JSON parsers, so write the
# bytes ourselves.
function Write-TextFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

# Installers write to the Machine/User PATH, which this already-running session
# does not see. Without this, a tool installed a moment ago still looks missing.
function Update-SessionPath {
    $combined = @(
        $env:Path
        [Environment]::GetEnvironmentVariable("Path", "User")
        [Environment]::GetEnvironmentVariable("Path", "Machine")
    ) -join ";"
    $env:Path = (($combined -split ";" | Where-Object { $_ } | Select-Object -Unique) -join ";")
}

function Add-UserPath {
    param([Parameter(Mandatory)][string]$Path)

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $segments = @($userPath -split ";" | Where-Object { $_ })
    if ($segments -notcontains $Path) {
        [Environment]::SetEnvironmentVariable("Path", (($segments + $Path) -join ";"), "User")
    }
    if ($env:Path -notlike "*$Path*") {
        $env:Path = "$Path;$env:Path"
    }
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Command
    )

    if (Get-Command $Command -ErrorAction SilentlyContinue) {
        return
    }

    Invoke-Native {
        & winget install --id $Id --exact --source winget --accept-package-agreements --accept-source-agreements
    }
    if ($LASTEXITCODE -ne 0) {
        throw "winget failed to install $Id."
    }

    # Fail here, with the package name, rather than three steps later.
    Update-SessionPath
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "$Id installed, but '$Command' is still not on PATH."
    }
}

function Test-PythonManager {
    if (-not (Get-Command pymanager -ErrorAction SilentlyContinue)) {
        return $false
    }
    Invoke-Native { & pymanager --version *> $null }
    return ($LASTEXITCODE -eq 0)
}

function Install-Python {
    if (-not (Test-PythonManager)) {
        Invoke-Native {
            & winget install --id Python.PythonInstallManager --exact --source winget --force `
                --accept-package-agreements --accept-source-agreements
        }
        if ($LASTEXITCODE -ne 0) {
            throw "winget failed to install Python Install Manager."
        }
        Update-SessionPath
        if (-not (Test-PythonManager)) {
            throw "Python Install Manager installed, but 'pymanager' is not on PATH."
        }
    }

    Invoke-Native { & pymanager "-V:$PythonVersion" --version *> $null }
    if ($LASTEXITCODE -ne 0) {
        Invoke-Native { & pymanager install $PythonVersion }
        if ($LASTEXITCODE -ne 0) {
            throw "Python $PythonVersion installation failed."
        }
        Update-SessionPath
    }
}

# The hooks are invoked as `python ...`, but the Python Install Manager only
# guarantees `py`/`pymanager`. The sensitive-file hook fails open, so a missing
# `python` would silently stop blocking secrets.
function Confirm-PythonShim {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        return
    }

    $executable = Get-NativeText { & pymanager "-V:$PythonVersion" -c "import sys; print(sys.executable)" 2>$null }
    if ($executable) {
        Add-UserPath (Split-Path $executable -Parent)
    }

    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Warning "'python' is not on PATH. The sensitive-file hook fails open, so Read/Edit/Write"
        Write-Warning "on .env / appsettings / secrets would NOT be hard-blocked. The configuration will"
        Write-Warning "still be installed, but this run will fail its final check until you fix this."
    }
}

# Newest LTS still in active or maintenance support, per the official index -
# so this keeps tracking LTS releases without a hardcoded major version.
function Install-DotNetLts {
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        $sdks = Invoke-Native { & dotnet --list-sdks 2>$null }
    } else {
        $sdks = @()
    }

    try {
        $index = Invoke-RestMethod "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json"
    } catch {
        throw "Could not reach the .NET releases index to resolve the current LTS: $_"
    }

    $release = $index."releases-index" |
        Where-Object { $_."release-type" -eq "lts" -and $_."support-phase" -in @("active", "maintenance") } |
        Sort-Object { [version]$_."channel-version" } -Descending |
        Select-Object -First 1
    if (-not $release) {
        throw "Could not find an active .NET LTS release."
    }

    # `dotnet` resolving is not enough: an older SDK satisfies it while csharp-ls
    # wants the current LTS.
    $major = $release."channel-version".Split(".")[0]
    if (($sdks | Where-Object { $_ -match "^\s*$major\." } | Measure-Object).Count -gt 0) {
        return
    }
    if ($sdks) {
        Write-Host ".NET is installed but no $major.x SDK is present; adding it."
    }

    Install-WingetPackage -Id "Microsoft.DotNet.SDK.$major" -Command "dotnet"
}

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-NodeJsLts {
    if (Get-Command node -ErrorAction SilentlyContinue) {
        return
    }

    $architecture = switch ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
        "X64" { "x64" }
        "Arm64" { "arm64" }
        default { throw "Node.js LTS is not available for this architecture." }
    }

    try {
        $releases = Invoke-RestMethod "https://nodejs.org/dist/index.json"
    } catch {
        throw "Could not reach https://nodejs.org/dist/index.json to resolve the Node.js LTS version: $_"
    }

    # The feed is newest-first; require an MSI actually published for this arch.
    $release = $releases |
        Where-Object { $_.lts -and $_.files -contains "win-$architecture-msi" } |
        Select-Object -First 1
    if (-not $release) {
        throw "Could not find a Node.js LTS installer for Windows $architecture."
    }

    $installerName = "node-$($release.version)-$architecture.msi"
    $installerUrl = "https://nodejs.org/dist/$($release.version)/$installerName"

    if (-not (Test-Elevated)) {
        Write-Warning "Node.js is missing and installing it needs an elevated PowerShell. Skipping."
        Write-Warning "Re-run from an admin prompt, or install $($release.version) manually:"
        Write-Warning "  $installerUrl"
        return
    }

    Write-Host "Installing Node.js $($release.version) ($($release.lts)) for $architecture..."

    # The PS 5.1 progress bar makes Invoke-WebRequest an order of magnitude slower.
    $previousProgress = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    $installer = Join-Path $env:TEMP "$PID-$installerName"
    try {
        $checksums = (Invoke-WebRequest "https://nodejs.org/dist/$($release.version)/SHASUMS256.txt" -UseBasicParsing).Content
        $pattern = "^\s*([a-fA-F0-9]{64})\s+\*?" + [regex]::Escape($installerName) + "\r?$"
        $expectedHash = ([regex]::Match($checksums, $pattern, [Text.RegularExpressions.RegexOptions]::Multiline)).Groups[1].Value
        if (-not $expectedHash) {
            throw "Could not find the published checksum for $installerName."
        }

        Invoke-WebRequest $installerUrl -OutFile $installer -UseBasicParsing
        $actualHash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
        if ($actualHash -ine $expectedHash) {
            throw "Node.js installer checksum verification failed - refusing to run it."
        }

        $process = Start-Process msiexec.exe `
            -ArgumentList "/i", "`"$installer`"", "/qn", "/norestart" -Wait -PassThru
        # 3010 = success, reboot required.
        if ($process.ExitCode -notin @(0, 3010)) {
            throw "Node.js installation failed with exit code $($process.ExitCode)."
        }
        if ($process.ExitCode -eq 3010) {
            $script:RestartRequired = $true
        }
    } finally {
        $ProgressPreference = $previousProgress
        Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
    }

    $nodeDirectory = Join-Path $env:ProgramFiles "nodejs"
    if (-not (Test-Path (Join-Path $nodeDirectory "node.exe"))) {
        throw "Node.js installation completed but node.exe was not found in $nodeDirectory."
    }
    $env:Path = "$nodeDirectory;$env:Path"
    Update-SessionPath
}

function Install-ClaudeCode {
    if (Get-Command claude -ErrorAction SilentlyContinue) { return }

    # Anthropic's own installer: user scope, no elevation, and it verifies the
    # binary's SHA256 against a signed manifest before running `claude install`
    # to wire up the launcher. Only when missing, so an existing install is never
    # upgraded - and a running one is never replaced, because a running one is
    # not missing.
    Write-Host "Installing Claude Code..."
    $previousProgress = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    $installer = Join-Path $env:TEMP "$PID-claude-install.ps1"
    try {
        Invoke-WebRequest "https://claude.ai/install.ps1" -OutFile $installer -UseBasicParsing
        & $installer
    } catch {
        Write-Warning "Could not install Claude Code: $_"
    } finally {
        $ProgressPreference = $previousProgress
        Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
    }

    Add-UserPath (Join-Path $HOME ".local\bin")
    Update-SessionPath
    # Presence, not the exit code: install.ps1 only calls `exit` on failure, so a
    # successful run leaves $LASTEXITCODE holding whatever came before it.
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Warning "Claude Code is still not on PATH, so the plugin step will be skipped."
        Write-Warning "Install it yourself (irm https://claude.ai/install.ps1 | iex) and re-run."
    }
}

# crates.io's `rtk` is a DIFFERENT tool - "Rust Type Kit" (reachingforthejack/rtk,
# stuck at 0.1.0). The one this setup needs is rtk-ai/rtk, installed from git.
# `rtk gain` is the discriminator: Rust Type Kit has no such subcommand.
function Test-RtkIsTokenKiller {
    if (-not (Get-Command rtk -ErrorAction SilentlyContinue)) {
        return $false
    }
    Invoke-Native { & rtk gain *> $null }
    return ($LASTEXITCODE -eq 0)
}

function Install-Toolchain {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget is required to install the user-level tools."
    }

    Add-UserPath (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links")
    Update-SessionPath

    Install-WingetPackage -Id "Git.Git" -Command "git"
    Install-Python
    Install-WingetPackage -Id "astral-sh.uv" -Command "uv"
    Install-WingetPackage -Id "jqlang.jq" -Command "jq"
    Install-WingetPackage -Id "Rustlang.Rustup" -Command "rustup"
    Install-NodeJsLts
    Install-DotNetLts
    Install-ClaudeCode

    $cargoBin = Join-Path $HOME ".cargo\bin"
    Add-UserPath $cargoBin
    Add-UserPath (Join-Path $HOME ".local\bin")
    Add-UserPath (Join-Path $env:APPDATA "npm")
    Add-UserPath (Join-Path $HOME ".dotnet\tools")
    Update-SessionPath

    # rustup installs proxy shims - rustc.exe, cargo.exe, rust-analyzer.exe and
    # the rest of a fixed list - into ~\.cargo\bin whether or not a toolchain is
    # present, so `Get-Command rustc` only proves the shim is on disk. winget's
    # Rustlang.Rustup leaves exactly that state: shims, no toolchain. The guard
    # then passed, this step was skipped, and `cargo install` died with "rustup
    # could not choose a version of cargo to run ... no default is configured".
    # Ask rustup instead - `show active-toolchain` exits non-zero when there is
    # no default (verified: 1 with an empty RUSTUP_HOME, 0 once one exists).
    if (Get-Command rustup -ErrorAction SilentlyContinue) {
        $null = Get-NativeText { & rustup show active-toolchain 2>$null }
        if ($LASTEXITCODE -ne 0) {
            # Installing stable also makes it the default when there is none,
            # so this covers both "no toolchain" and "toolchain, no default".
            Invoke-Native { & rustup toolchain install stable }
            if ($LASTEXITCODE -ne 0) {
                throw "Rust stable toolchain installation failed."
            }
            Update-SessionPath
        }
    }

    # rtk: the Bash PreToolUse hook shells out to `rtk hook claude` on every Bash
    # tool call. Without it, every Bash call errors. Must be rtk-ai/rtk from git.
    if (-not (Test-RtkIsTokenKiller)) {
        $cargo = Join-Path $cargoBin "cargo.exe"
        if (-not (Test-Path $cargo)) {
            throw "cargo not found at $cargo - the Rust toolchain did not finish installing."
        }
        if (Get-Command rtk -ErrorAction SilentlyContinue) {
            Write-Warning "An 'rtk' is on PATH but it is not rtk-ai/rtk (most likely Rust Type Kit"
            Write-Warning "from crates.io, which shares the name). Replacing it."
        }
        Invoke-Native { & $cargo install --git https://github.com/rtk-ai/rtk.git rtk --locked --force }
        if ($LASTEXITCODE -ne 0) {
            throw "rtk installation failed."
        }
        Update-SessionPath
        if (-not (Test-RtkIsTokenKiller)) {
            throw "rtk installed but 'rtk gain' still fails - the wrong rtk is winning on PATH."
        }
    }

    # graphify: backs the bundled graphify skill and its two hooks. The PyPI
    # package is 'graphifyy' (two y's); plain 'graphify' does not exist.
    if (-not (Get-Command graphify -ErrorAction SilentlyContinue)) {
        Invoke-Native { & uv tool install graphifyy }
        if ($LASTEXITCODE -ne 0) {
            throw "graphify installation failed."
        }
        Update-SessionPath
    }

    # Language servers behind the three official LSP plugins.
    if (-not (Get-Command typescript-language-server -ErrorAction SilentlyContinue)) {
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            Invoke-Native { & npm install --global typescript typescript-language-server }
            if ($LASTEXITCODE -ne 0) {
                throw "TypeScript language server installation failed."
            }
            Update-SessionPath
        } else {
            Write-Warning "npm is not available (Node.js was skipped), so typescript-language-server"
            Write-Warning "was not installed. The typescript-lsp plugin will not work until you run:"
            Write-Warning "  npm install --global typescript typescript-language-server"
        }
    }

    if (-not (Get-Command csharp-ls -ErrorAction SilentlyContinue)) {
        Invoke-Native { & dotnet tool install --global csharp-ls }
        if ($LASTEXITCODE -ne 0) {
            throw "C# language server installation failed."
        }
        Update-SessionPath
    }

    # The same shim trap as the toolchain check: rust-analyzer.exe is one of the
    # proxies rustup always creates, so a presence check succeeds even when the
    # component is not installed, the add is skipped, and the plugin gets a shim
    # that exits 1 with "Unknown binary 'rust-analyzer.exe' in official
    # toolchain". Run it instead - that also correctly skips a standalone
    # rust-analyzer someone installed by another route.
    $rustAnalyzerWorks = $false
    if (Get-Command rust-analyzer -ErrorAction SilentlyContinue) {
        $null = Get-NativeText { & rust-analyzer --version 2>$null }
        $rustAnalyzerWorks = ($LASTEXITCODE -eq 0)
    }
    if (-not $rustAnalyzerWorks) {
        Invoke-Native { & rustup component add rust-analyzer }
        if ($LASTEXITCODE -ne 0) {
            throw "Rust Analyzer installation failed."
        }
        Update-SessionPath
    }
}

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)

    # git writes warnings and hints to stderr on perfectly successful commands
    # (CRLF conversion, detached HEAD, ...), so go by exit code only.
    Invoke-Native { & git -C $ClaudeDirectory @Arguments }
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed."
    }
}

function Backup-ClaudeDirectory {
    # The backup is the only undo path for an existing config, so a missing git
    # is a hard stop rather than a silent overwrite.
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw ("git is not on PATH, so $ClaudeDirectory cannot be backed up before it is " +
               "overwritten. Install git (or re-run without -SkipToolchain), or pass " +
               "-SkipBackup to overwrite with no undo path.")
    }

    # Look for .git in this directory specifically. `--is-inside-work-tree` would
    # be true when merely NESTED in someone else's repo, which would commit the
    # parent (potentially the whole home directory) instead of creating a repo
    # here. Comparing `rev-parse --show-toplevel` against the target would fix
    # that but introduce another: git reports the path with reparse points
    # resolved, so a .claude that is a junction or symlink into a dotfiles
    # checkout reports its real location, the comparison fails, and an existing
    # repo gets treated as a fresh one and reconfigured. Verified: git returned
    # ...\winsym\real for a target of ...\winsym\link.
    $isGitRepository = Test-Path -LiteralPath (Join-Path $ClaudeDirectory ".git")
    if ($isGitRepository) {
        # Someone else's repo. Whatever it tracks and whatever its .gitignore says
        # is their decision - they may well be relying on it to restore sessions
        # and history. Commit what is about to be overwritten and change nothing
        # else: no .gitignore edits, no untracking. Adding an ignore rule here
        # would not untrack what is already in the repo, but it WOULD stop
        # `git add` from picking up new files underneath, so tomorrow's sessions
        # would silently stop being backed up while yesterday's stayed.
        Write-Host "Using the existing repo in $ClaudeDirectory as-is; its .gitignore is left alone."
    } else {
        Invoke-Git -Arguments @("init")

        # Only ever written for a repo this script just created, where nothing is
        # tracked yet and so nothing can be lost. It keeps OAuth credentials, our
        # own residue from an interrupted run, and bulk runtime state out from the
        # start. The last of those is megabytes per commit and no use as an undo
        # point.
        $gitignore = Join-Path $ClaudeDirectory ".gitignore"
        $ignoreEntries = @(
            ".credentials.json", ".claude-setup-staging-*", ".claude-setup-backup-*",
            "downloads/", "projects/", "shell-snapshots/", "session-env/",
            "file-history/", "cache/", "plugins/", "paste-cache/", "backups/",
            "history.jsonl", "stats-cache.json"
        )
        if (-not (Test-Path $gitignore)) {
            Write-TextFile -Path $gitignore -Content (($ignoreEntries -join "`n") + "`n")
        } else {
            $existing = @(Get-Content $gitignore)
            foreach ($entry in $ignoreEntries) {
                if ($existing -notcontains $entry) {
                    Add-Content -Path $gitignore -Value $entry
                }
            }
        }
    }

    $name = Get-NativeText { & git -C $ClaudeDirectory config user.name }
    $email = Get-NativeText { & git -C $ClaudeDirectory config user.email }
    if (-not $name) {
        Invoke-Git -Arguments @("config", "user.name", "Claude setup backup")
    }
    if (-not $email) {
        Invoke-Git -Arguments @("config", "user.email", "claude-setup@localhost")
    }

    Invoke-Git -Arguments @("add", "--all")
    Invoke-Git -Arguments @("commit", "--allow-empty", "-m", "Backup before Claude setup replication")

    # Reported, not acted on: this is your repo. `ls-files -- <path>` prints the
    # path when tracked and nothing when not, always exiting 0. Deliberately not
    # `--error-unmatch`, whose exit code IS the answer: the not-tracked case
    # would leave $LASTEXITCODE at 1 and a clean install would report failure to
    # whatever invoked it.
    if (Get-NativeText { & git -C $ClaudeDirectory ls-files -- .credentials.json }) {
        Write-Warning "This repo tracks .credentials.json, which holds live OAuth tokens."
        Write-Warning "Left as-is deliberately. To stop committing it, untrack it yourself:"
        Write-Warning "  git -C $ClaudeDirectory rm --cached .credentials.json"
    }
}

# Every file the package ships, as a map of relative path -> absolute source.
# Two roots are merged - the platform-neutral `shared` tree and the per-platform
# overlay - with the overlay winning on a collision. Enumerating rather than
# hardcoding means a file added to either tree is picked up automatically, and
# anything NOT shipped - your own hooks, your own skills - is simply left alone.
function Get-ShippedFileMap {
    $map = [ordered]@{}
    foreach ($root in @($sharedPath, $sourcePath)) {
        foreach ($file in (Get-ChildItem -LiteralPath $root -Recurse -File)) {
            $map[$file.FullName.Substring($root.Length).TrimStart("\")] = $file.FullName
        }
    }
    return $map
}

# What actually lands in ~/.claude: everything shipped, minus the two halves of
# the composed file, plus the composed file itself.
function Get-InstalledFiles {
    param([Parameter(Mandatory)]$Map)
    return @(@($Map.Keys | Where-Object {
        $_ -ne $ComposedFile.Core -and $_ -ne $ComposedFile.Append
    }) + $ComposedFile.Output)
}

function Copy-ClaudeConfiguration {
    $map = Get-ShippedFileMap
    foreach ($required in @($ComposedFile.Core, $ComposedFile.Append)) {
        if (-not $map.Contains($required)) {
            throw "The platform overlay is incomplete: $required was not found under $SharedSource or $ConfigSource."
        }
    }

    # settings.json is rendered from a template and CLAUDE.md is composed from
    # its two halves; both are written straight into staging, so neither takes
    # part in the plain copy below.
    $shipped = @($map.Keys | Where-Object {
        $_ -ne "settings.json" -and $_ -ne $ComposedFile.Core -and $_ -ne $ComposedFile.Append
    })
    if (-not $shipped) {
        throw "No files found under $SharedSource or $ConfigSource - nothing to install."
    }

    # Stage everything first, then swap it in, so a failure midway leaves the
    # existing config intact rather than half-replaced.
    $stagingRoot = Join-Path $ClaudeDirectory ".claude-setup-staging-$PID"
    $backupRoot = Join-Path $ClaudeDirectory ".claude-setup-backup-$PID"
    $backedUp = @()
    $created = @()
    $rollbackFailed = $false

    try {
        New-Item -ItemType Directory -Path $stagingRoot | Out-Null
        New-Item -ItemType Directory -Path $backupRoot | Out-Null

        # settings.json is rendered from the template into staging.
        #
        # ReadAllText, not Get-Content: on PowerShell 5.1 Get-Content decodes a
        # BOM-less file with the system ANSI code page, so the em dash in the
        # graphify hook message (UTF-8 e2 80 94) came back as three cp1252
        # characters and Write-TextFile re-encoded them as "a-hat euro" mojibake.
        # ReadAllText defaults to UTF-8, matching how Write-TextFile writes.
        $template = [IO.File]::ReadAllText($map["settings.json"])
        $forwardSlashHome = $targetPath.TrimEnd("\").Replace("\", "/")
        Write-TextFile -Path (Join-Path $stagingRoot "settings.json") `
                       -Content $template.Replace("__CLAUDE_HOME__", $forwardSlashHome)

        # CLAUDE.md is the two halves joined byte for byte.
        [IO.File]::WriteAllBytes(
            (Join-Path $stagingRoot $ComposedFile.Output),
            ([IO.File]::ReadAllBytes($map[$ComposedFile.Core]) +
             [IO.File]::ReadAllBytes($map[$ComposedFile.Append])))

        foreach ($relativePath in $shipped) {
            $staged = Join-Path $stagingRoot $relativePath
            $stagedParent = Split-Path $staged -Parent
            if (-not (Test-Path $stagedParent)) {
                New-Item -ItemType Directory -Path $stagedParent -Force | Out-Null
            }
            Copy-Item -LiteralPath $map[$relativePath] -Destination $staged -Force
        }

        foreach ($relativePath in (@("settings.json", $ComposedFile.Output) + $shipped)) {
            $staged = Join-Path $stagingRoot $relativePath
            $destination = Join-Path $ClaudeDirectory $relativePath

            $destinationParent = Split-Path $destination -Parent
            if (-not (Test-Path $destinationParent)) {
                New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
            }

            if (Test-Path $destination) {
                $savedTo = Join-Path $backupRoot $relativePath
                $savedParent = Split-Path $savedTo -Parent
                if (-not (Test-Path $savedParent)) {
                    New-Item -ItemType Directory -Path $savedParent -Force | Out-Null
                }
                Move-Item -LiteralPath $destination -Destination $savedTo
                $backedUp += $relativePath
            } else {
                $created += $relativePath
            }
            Move-Item -LiteralPath $staged -Destination $destination
        }
    } catch {
        $originalError = $_
        try {
            foreach ($relativePath in $created) {
                Remove-Item -LiteralPath (Join-Path $ClaudeDirectory $relativePath) `
                            -Recurse -Force -ErrorAction SilentlyContinue
            }
            for ($index = $backedUp.Count - 1; $index -ge 0; $index--) {
                $relativePath = $backedUp[$index]
                $destination = Join-Path $ClaudeDirectory $relativePath
                Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue
                Move-Item -LiteralPath (Join-Path $backupRoot $relativePath) -Destination $destination
            }
        } catch {
            $rollbackFailed = $true
            Write-Warning "Configuration rollback failed. Recovery data remains at $backupRoot."
        }
        throw $originalError
    } finally {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        if (-not $rollbackFailed) {
            Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

}

# `graphify install` appends a skill-registration block to CLAUDE.md:
#
#   # graphify
#   - **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to
#     knowledge graph. Trigger: `/graphify`
#   When the user types `/graphify`, use the installed graphify skill ...
#
# That is redundant here. Claude Code discovers skills from ~/.claude/skills/
# on its own, and the two graphify hooks in settings.json already prompt for
# `graphify query` before searching and `graphify update .` after edits. So the
# block is stripped after each install, which also keeps re-runs clean.
function Remove-GraphifySection {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }

    # Rebuild with the file's own newline. CLAUDE.md is LF and
    # copilot-instructions.md is CRLF; hardcoding either would silently convert
    # the other, and the composed instructions file is guaranteed byte for byte.
    $newline = if ([IO.File]::ReadAllText($Path).Contains("`r`n")) { "`r`n" } else { "`n" }

    $lines = @([IO.File]::ReadAllLines($Path))
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq "# graphify") {
            $start = $i
            break
        }
    }
    if ($start -lt 0) {
        return $false
    }

    # Section runs to the next top-level heading, or to end of file.
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^# ") {
            $end = $i
            break
        }
    }

    $kept = @()
    if ($start -gt 0) {
        $kept += $lines[0..($start - 1)]
    }
    if ($end -lt $lines.Count) {
        $kept += $lines[$end..($lines.Count - 1)]
    }
    Write-TextFile -Path $Path -Content ((($kept -join $newline).TrimEnd()) + $newline)
    return $true
}

# Install graphify's own user-level skill, so it matches the installed version
# rather than the snapshot bundled in this package.
function Install-GraphifySkill {
    if (-not (Get-Command graphify -ErrorAction SilentlyContinue)) {
        Write-Warning "graphify is not on PATH, so its skill was left at the bundled snapshot."
        Write-Warning "Run this once it is installed:  graphify install --platform claude"
        return
    }

    # graphify writes the CLAUDE.md registration to the real home directory and
    # ignores -ClaudeDirectory, so only run it when they are the same place.
    $defaultDirectory = [IO.Path]::GetFullPath((Join-Path $HOME ".claude"))
    if ($targetPath.TrimEnd("\") -ne $defaultDirectory.TrimEnd("\")) {
        Write-Warning "Target is not $defaultDirectory, so the graphify skill was left at the bundled"
        Write-Warning "snapshot version. Run 'graphify install --platform claude' yourself to sync it."
        return
    }

    Invoke-Native { & graphify install --platform claude *> $null }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "'graphify install --platform claude' failed; keeping the bundled skill snapshot."
        return
    }
    Write-Host "graphify skill installed at the user level."

    if (Remove-GraphifySection -Path (Join-Path $ClaudeDirectory "CLAUDE.md")) {
        Write-Host "  removed its redundant CLAUDE.md registration block (hooks already cover it)."
    }
}

function Install-ClaudePlugin {
    param([Parameter(Mandatory)][string]$Name)

    # The name just has to appear as its own whitespace-delimited token. Do NOT
    # try to match the list's bullet: the CLI prints U+276F, PowerShell decodes
    # native output with [Console]::OutputEncoding (IBM437 on a stock console),
    # and it arrives as the letters "Gamma yen guillemet" - so a
    # "leading non-letters" class never matches and every check comes back false.
    $pattern = "(?m)(?:^|\s)" + [regex]::Escape($Name) + "(?:\s|\(|$)"
    $installed = Get-NativeText { & claude plugin list 2>&1 }
    if ($LASTEXITCODE -eq 0 -and $installed -match $pattern) {
        return
    }

    Invoke-Native { & claude plugin install "$Name" }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "'claude plugin install $Name' returned $LASTEXITCODE."
        return
    }

    $installed = Get-NativeText { & claude plugin list 2>&1 }
    if ($LASTEXITCODE -ne 0 -or $installed -notmatch $pattern) {
        Write-Warning "$Name does not appear in 'claude plugin list' after installing it."
    }
}

function Install-Plugins {
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Warning "Claude Code CLI ('claude') is not on PATH, so plugins were not installed."
        Write-Warning "settings.json already enables them, so a first run should fetch them. Otherwise run:"
        Write-Warning "  claude plugin marketplace add anthropics/claude-plugins-official"
        Write-Warning "  claude plugin marketplace add DietrichGebert/ponytail"
        Write-Warning "  claude plugin install ponytail@ponytail"
        Write-Warning "  claude plugin install typescript-lsp@claude-plugins-official"
        Write-Warning "  claude plugin install csharp-lsp@claude-plugins-official"
        Write-Warning "  claude plugin install rust-analyzer-lsp@claude-plugins-official"
        return
    }

    # Point the CLI at the directory being set up; it defaults to ~/.claude and
    # would otherwise ignore -ClaudeDirectory entirely.
    $previousConfigDir = $env:CLAUDE_CONFIG_DIR
    $env:CLAUDE_CONFIG_DIR = $targetPath
    try {
        $marketplaces = @(
            @{ Name = "claude-plugins-official"; Source = "anthropics/claude-plugins-official" },
            @{ Name = "ponytail";                Source = "DietrichGebert/ponytail" }
        )
        $known = Get-NativeText { & claude plugin marketplace list 2>&1 }
        foreach ($marketplace in $marketplaces) {
            $pattern = "(?m)(?:^|\s)" + [regex]::Escape($marketplace.Name) + "(?:\s|\(|$)"
            if ($known -notmatch $pattern) {
                Invoke-Native { & claude plugin marketplace add $marketplace.Source }
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Could not add marketplace $($marketplace.Source); continuing."
                }
            }
        }

        foreach ($plugin in "ponytail@ponytail",
                            "typescript-lsp@claude-plugins-official",
                            "csharp-lsp@claude-plugins-official",
                            "rust-analyzer-lsp@claude-plugins-official") {
            Install-ClaudePlugin -Name $plugin
        }
    } finally {
        $env:CLAUDE_CONFIG_DIR = $previousConfigDir
    }
}

if (-not $SkipToolchain) {
    Install-Toolchain
    Confirm-PythonShim
}

if (-not (Test-Path $ClaudeDirectory)) {
    New-Item -ItemType Directory -Path $ClaudeDirectory | Out-Null
}

if ($SkipBackup) {
    Write-Warning "-SkipBackup: $ClaudeDirectory is being overwritten with no undo path."
} else {
    Backup-ClaudeDirectory
}
Copy-ClaudeConfiguration
Install-GraphifySkill

if (-not $SkipPlugins) {
    Install-Plugins
}

if (-not $SkipToolchain) {
    foreach ($command in "git", "pymanager", "python", "uv", "graphify", "jq",
                         "rustup", "rustc", "cargo", "dotnet", "csharp-ls", "rust-analyzer") {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "$command is not available on PATH after setup."
        }
    }
    # rtk is load-bearing - a hook routes every Bash tool call through it - and
    # merely resolving on PATH is not enough, since a same-named crate exists.
    if (-not (Test-RtkIsTokenKiller)) {
        throw ("rtk is not the expected tool ('rtk gain' fails). The setup's Bash hook will " +
               "break every Bash call. Install it with: " +
               "cargo install --git https://github.com/rtk-ai/rtk.git rtk --locked --force")
    }
    # Node may have been skipped for lack of elevation; that only degrades the
    # typescript-lsp plugin, so warn rather than fail the whole run.
    foreach ($command in "node", "npm", "typescript-language-server") {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            Write-Warning "$command is not on PATH. Re-run from an elevated prompt to install Node.js."
        }
    }
}

# Confirm what was installed actually landed, and that JSON config is readable.
#
# skills\graphify\ is excluded: `graphify install` owns that tree and replaces it
# with whatever the installed graphify version ships. That file set need not match
# the snapshot bundled here, so checking it file-by-file would fail the run purely
# because graphify moved on. Its SKILL.md is asserted separately below.
foreach ($relativePath in (Get-InstalledFiles (Get-ShippedFileMap) |
                           Where-Object { $_ -notlike "skills\graphify\*" })) {
    $installed = Join-Path $ClaudeDirectory $relativePath
    if (-not (Test-Path $installed)) {
        throw "Expected $relativePath in $ClaudeDirectory after the copy, but it is missing."
    }
    if ([IO.Path]::GetExtension($relativePath) -eq ".json") {
        try {
            $null = Get-Content $installed -Raw | ConvertFrom-Json
        } catch {
            throw "$relativePath was installed but is not valid JSON: $_"
        }
    }
}

foreach ($relativePath in "skills\graphify\SKILL.md") {
    if (-not (Test-Path (Join-Path $ClaudeDirectory $relativePath))) {
        throw "Expected $relativePath in $ClaudeDirectory after the copy, but it is missing."
    }
}

if ((Get-Content (Join-Path $ClaudeDirectory "settings.json") -Raw) -match "__CLAUDE_HOME__") {
    throw "settings.json still contains the __CLAUDE_HOME__ placeholder."
}

Write-Host ""
Write-Host "Setup complete. Restart the terminal, then run: claude"
Write-Host "Log in with your own account - no credentials were copied."
if ($script:RestartRequired) {
    Write-Warning "Restart Windows to finish the Node.js installation."
}

# Every real failure above is a `throw`, which exits non-zero on its own. Without
# this, the exit code is whatever $LASTEXITCODE happened to be left at by the
# last native command - a warned-about plugin or a failing `rtk gain` probe would
# make a successful install look like a failed one to a caller.
exit 0
