<#
.SYNOPSIS
Installs the user-level command-line setup and copies bundled Copilot configuration.

.EXAMPLE
.\setup-copilot-windows.ps1

.EXAMPLE
.\setup-copilot-windows.ps1 -SkipToolchain -SkipPlugins

.EXAMPLE
.\setup-copilot-windows.ps1 -WithRust

.NOTES
Rust is opt-in. By default no Rust toolchain is installed at all: rtk comes from
winget as a prebuilt binary, and rust-analyzer and the rust LSP entry are
skipped, so nothing here downloads from static.rust-lang.org. Pass -WithRust for
Rust support.

Version policy - nothing already installed is upgraded; these apply only when a
command is missing.

  Tracks latest automatically:
    git, uv, jq, graphify (PyPI 'graphifyy'), typescript-language-server,
    csharp-ls, copilot, ponytail, rtk (winget 'rtk-ai.rtk', which serves
    rtk-ai/rtk's own release binary - NOT the unrelated crates.io crate of the
    same name), and with -WithRust, Rust (rustup stable).

  Resolved at run time:
    Node.js - newest LTS with an MSI for this architecture, SHA256-verified.
    .NET    - newest LTS still in active or maintenance support.

  Pinned, needs a human bump:
    Python  -PythonVersion  3.14  (latest stable; revisit when 3.15 ships)
#>
[CmdletBinding()]
param(
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$SharedSource = (Join-Path $PSScriptRoot "..\shared"),

    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$ConfigSource = (Join-Path $PSScriptRoot "config"),

    [string]$CopilotDirectory = (Join-Path $HOME ".copilot"),

    [string]$PythonVersion = "3.14",

    [switch]$SkipToolchain,

    [switch]$SkipPlugins,

    [switch]$SkipBackup,

    # Opt in to Rust. Off by default: nothing in this setup needs a Rust
    # toolchain any more (rtk comes from winget as a prebuilt binary), and the
    # ~200 MB of downloads from static.rust-lang.org that rustup pulls have been
    # blocked outright by corporate filters reporting them as a trojan. Passing
    # this adds rustup + the stable toolchain and the rust-analyzer component,
    # and keeps the rust server in lsp-config.json.
    [switch]$WithRust
)

$ErrorActionPreference = "Stop"
$script:RestartRequired = $false

$sharedPath = (Resolve-Path $SharedSource).Path
$sourcePath = (Resolve-Path $ConfigSource).Path
$targetPath = [IO.Path]::GetFullPath($CopilotDirectory)
foreach ($root in @($sharedPath, $sourcePath)) {
    if ($root.TrimEnd("\") -eq $targetPath.TrimEnd("\")) {
        throw "The config source must not be the destination .copilot directory."
    }
}

# copilot-instructions.md is assembled at install time from a platform-neutral
# core plus a per-platform appendix, so the ~70 shared lines are not duplicated
# across the Windows, WSL and macOS overlays. The two halves are a byte cut of
# the original file, so a raw byte concatenation reproduces it exactly - no
# re-encoding and no line-ending normalisation (this file is CRLF; the Claude
# one is LF).
$ComposedFile = @{
    Output = "copilot-instructions.md"
    Core   = "copilot-instructions.core.md"
    Append = "copilot-instructions.append.md"
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
    if (($env:Path -split ";") -notcontains $Path) {
        $env:Path = "$Path;$env:Path"
    }
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Command,
        # For packages where "the command resolves" is not the same question as
        # "the package is installed". The .NET SDK is the case: a runtime-only
        # install, or an older SDK, both put `dotnet` on PATH with nothing
        # csharp-ls can build against. The caller has already decided.
        [switch]$SkipPresenceCheck
    )

    if (-not $SkipPresenceCheck -and (Get-Command $Command -ErrorAction SilentlyContinue)) {
        return
    }

    Invoke-Native {
        & winget install --id $Id --exact --source winget --accept-package-agreements --accept-source-agreements
    }
    if ($LASTEXITCODE -ne 0) {
        throw "winget failed to install $Id."
    }

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

# The hooks are invoked as `python ...`, and the final verification requires it,
# but the Python Install Manager only guarantees `py`/`pymanager`.
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
    } else {
        Write-Host "No .NET SDK is present; installing the $major.x SDK."
    }

    # -SkipPresenceCheck: `dotnet` resolving is precisely what does not settle
    # this. A runtime-only install puts dotnet on PATH with an empty
    # --list-sdks (verified: exit 0, no output), and an older SDK puts a
    # different major there - in both cases the presence check would return
    # early and the message above would be a lie.
    Install-WingetPackage -Id "Microsoft.DotNet.SDK.$major" -Command "dotnet" -SkipPresenceCheck

    # Post-condition, because the failure it prevents is three steps away and
    # unrecognisable there: `dotnet tool install -g csharp-ls` exits 155 with
    # "No .NET SDKs were found" when the SDK did not actually land.
    $sdks = Invoke-Native { & dotnet --list-sdks 2>$null }
    if (($sdks | Where-Object { $_ -match "^\s*$major\." } | Measure-Object).Count -eq 0) {
        throw "Microsoft.DotNet.SDK.$major was installed, but 'dotnet --list-sdks' still reports no $major.x SDK."
    }
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

    $release = $releases |
        Where-Object { $_.lts -and $_.files -contains "win-$architecture-msi" } |
        Select-Object -First 1
    if (-not $release) {
        throw "Could not find a Node.js LTS installer for Windows $architecture."
    }

    $installerName = "node-$($release.version)-$architecture.msi"
    $installerUrl = "https://nodejs.org/dist/$($release.version)/$installerName"

    # msiexec /qn cannot elevate on its own; fail soft so the rest still runs.
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

# Resolve a command the way a NEW process will: Machine PATH first, then User.
#
# Test-RtkIsTokenKiller only proves the rtk that wins in THIS session works, and
# the two orders are not the same - Add-UserPath prepends to the session PATH but
# appends to the persisted one. So a machine with the wrong rtk in ~\.cargo\bin
# (index 0 of the User PATH on the machine this was found on, against index 18
# for WinGet\Links) passes the in-session check and still breaks the shell hook
# in the terminal the user actually opens next. winget cannot remove that copy
# the way `cargo install --force` used to overwrite it, so this has to be
# checked rather than assumed.
function Get-PersistedCommandPath {
    param([Parameter(Mandatory)][string]$Executable)

    foreach ($scope in "Machine", "User") {
        foreach ($directory in ([Environment]::GetEnvironmentVariable("Path", $scope) -split ";")) {
            if (-not $directory) { continue }
            # PATH entries can be quoted or contain characters Join-Path rejects;
            # a bad entry should be skipped, not abort the run.
            try {
                $candidate = Join-Path $directory.Trim('"') $Executable
            } catch {
                continue
            }
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    return $null
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
    if ($WithRust) {
        Install-WingetPackage -Id "Rustlang.Rustup" -Command "rustup"
    }
    Install-WingetPackage -Id "GitHub.Copilot" -Command "copilot"
    Install-NodeJsLts
    Install-DotNetLts

    if ($WithRust) {
        Add-UserPath (Join-Path $HOME ".cargo\bin")
    }
    Add-UserPath (Join-Path $HOME ".local\bin")
    Add-UserPath (Join-Path $env:APPDATA "npm")
    Add-UserPath (Join-Path $HOME ".dotnet\tools")
    Update-SessionPath

    # rtk: a hook rewrites every shell command through it. Must be rtk-ai/rtk -
    # merely having *an* `rtk` on PATH is not enough.
    #
    # From winget, not `cargo install --git`. It is the same artifact - the
    # rtk-ai.rtk manifest is a portable zip pointing at rtk-ai/rtk's own release
    # asset, pinned by SHA256 - so the "must not be the crates.io crate of the
    # same name" rule is satisfied without a Rust toolchain, a source build, or
    # a 70 MB download from static.rust-lang.org that corporate filters have
    # been seen to block as a trojan. winget drops a shim in WinGet\Links, which
    # is already on PATH from above.
    #
    # -SkipPresenceCheck: an `rtk` on PATH may be the wrong one, which is the
    # whole point of Test-RtkIsTokenKiller, so presence must not stand in for it.
    if (-not (Test-RtkIsTokenKiller)) {
        if (Get-Command rtk -ErrorAction SilentlyContinue) {
            Write-Warning "An 'rtk' is on PATH but it is not rtk-ai/rtk (most likely Rust Type Kit"
            Write-Warning "from crates.io, which shares the name). winget installs its own copy"
            Write-Warning "alongside it - unlike the old 'cargo install --force', it cannot remove"
            Write-Warning "that one. If the wrong copy wins on PATH, the check at the end says so."
        }
        # Ask winget first: `winget install` on a package it already has exits
        # non-zero ("no applicable upgrade"), which on a re-run would surface as
        # a failed install and mask the real problem, the throw below.
        Invoke-Native { & winget list --id rtk-ai.rtk --exact --source winget *> $null }
        if ($LASTEXITCODE -ne 0) {
            Install-WingetPackage -Id "rtk-ai.rtk" -Command "rtk" -SkipPresenceCheck
            Update-SessionPath
        }
        if (-not (Test-RtkIsTokenKiller)) {
            throw "rtk-ai.rtk is installed but 'rtk gain' still fails - the wrong rtk is winning on PATH."
        }
    }

    if ($WithRust) {
        # rustup installs proxy shims - rustc.exe, cargo.exe, rust-analyzer.exe
        # and the rest of a fixed list - into ~\.cargo\bin whether or not a
        # toolchain is present, so `Get-Command rustc` only proves the shim is on
        # disk. winget's Rustlang.Rustup leaves exactly that state: shims, no
        # toolchain, and `cargo` then dies with "rustup could not choose a
        # version of cargo to run ... no default is configured". Ask rustup
        # instead - `show active-toolchain` exits non-zero when there is no
        # default (verified: 1 with an empty RUSTUP_HOME, 0 once one exists).
        if (Get-Command rustup -ErrorAction SilentlyContinue) {
            $null = Get-NativeText { & rustup show active-toolchain 2>$null }
            if ($LASTEXITCODE -ne 0) {
                # Installing stable also makes it the default when there is none,
                # so this covers both "no toolchain" and "toolchain, no default".
                Invoke-Native { & rustup toolchain install stable }
                if ($LASTEXITCODE -ne 0) {
                    throw ("Rust stable toolchain installation failed. If the download was blocked " +
                           "(corporate filters have flagged rust-lang.org downloads as malware), " +
                           "drop -WithRust: nothing else here needs Rust.")
                }
                Update-SessionPath
            }
        }
    }

    # graphify: the PyPI package is 'graphifyy' (two y's).
    if (-not (Get-Command graphify -ErrorAction SilentlyContinue)) {
        Invoke-Native { & uv tool install graphifyy }
        if ($LASTEXITCODE -ne 0) {
            throw "graphify installation failed."
        }
        Update-SessionPath
    }

    if (-not (Get-Command typescript-language-server -ErrorAction SilentlyContinue)) {
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            Invoke-Native { & npm install --global typescript typescript-language-server }
            if ($LASTEXITCODE -ne 0) {
                throw "TypeScript language server installation failed."
            }
            Update-SessionPath
        } else {
            Write-Warning "npm is not available (Node.js was skipped), so typescript-language-server"
            Write-Warning "was not installed. Run this once Node.js is in place:"
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

    if ($WithRust) {
        # The same shim trap as the toolchain check: rust-analyzer.exe is one of
        # the proxies rustup always creates, so a presence check succeeds even
        # when the component is not installed, the add is skipped, and the LSP
        # gets a shim that exits 1 with "Unknown binary 'rust-analyzer.exe' in
        # official toolchain". Run it instead - that also correctly skips a
        # standalone rust-analyzer someone installed by another route.
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
}

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)

    # git writes warnings and hints to stderr on perfectly successful commands
    # (CRLF conversion, detached HEAD, ...), so go by exit code only.
    Invoke-Native { & git -C $CopilotDirectory @Arguments }
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed."
    }
}

function Backup-CopilotDirectory {
    # The backup is the only undo path for an existing config, so a missing git
    # is a hard stop rather than a silent overwrite.
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw ("git is not on PATH, so $CopilotDirectory cannot be backed up before it is " +
               "overwritten. Install git (or re-run without -SkipToolchain), or pass " +
               "-SkipBackup to overwrite with no undo path.")
    }

    # Look for .git in this directory specifically. `--is-inside-work-tree` would
    # be true when merely NESTED in someone else's repo, which would commit the
    # parent (potentially the whole home directory) instead of creating a repo
    # here. Comparing `rev-parse --show-toplevel` against the target would fix
    # that but introduce another: git reports the path with reparse points
    # resolved, so a .copilot that is a junction or symlink into a dotfiles
    # checkout reports its real location, the comparison fails, and an existing
    # repo gets treated as a fresh one and reconfigured. Verified: git returned
    # ...\winsym\real for a target of ...\winsym\link.
    $isGitRepository = Test-Path -LiteralPath (Join-Path $CopilotDirectory ".git")
    if ($isGitRepository) {
        # Someone else's repo. Whatever it tracks and whatever its .gitignore says
        # is their decision - they may well be relying on it to restore sessions.
        # Commit what is about to be overwritten and change nothing else: no
        # .gitignore edits, no untracking. Adding an ignore rule here would not
        # untrack what is already in the repo, but it WOULD stop `git add` from
        # picking up new files underneath, so tomorrow's sessions would silently
        # stop being backed up while yesterday's stayed.
        Write-Host "Using the existing repo in $CopilotDirectory as-is; its .gitignore is left alone."
    } else {
        Invoke-Git -Arguments @("init")

        # Only ever written for a repo this script just created, where nothing is
        # tracked yet and so nothing can be lost. It holds our own residue from an
        # interrupted run, plus bulk runtime state: chat transcripts, the two
        # SQLite databases and their write-ahead logs, session and IDE state,
        # logs, and the websocket port and token of the running process.
        # session-store.db alone is megabytes and its -wal changes on every
        # interaction.
        #
        # Settings, instructions, hooks, skills, prompts and installed-plugins are
        # NOT here: those are the config, and backing them up is the point. Nor is
        # there a credential entry - unlike ~/.claude, ~/.copilot has no token
        # file, and config.json is JSONC user settings worth keeping.
        $gitignore = Join-Path $CopilotDirectory ".gitignore"
        $ignoreEntries = @(
            ".copilot-setup-staging-*", ".copilot-setup-backup-*",
            "chats/", "jb/", "session-state/", "sidebar-sessions-state/",
            "logs/", "ide/", "run/", "restart/", "media-cache/",
            "data.db", "data.db-shm", "data.db-wal",
            "session-store.db", "session-store.db-shm", "session-store.db-wal",
            "command-history-state.json", "vscode.session.metadata.cache.json",
            "__pycache__/"
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

    $name = Get-NativeText { & git -C $CopilotDirectory config user.name }
    $email = Get-NativeText { & git -C $CopilotDirectory config user.email }
    if (-not $name) {
        Invoke-Git -Arguments @("config", "user.name", "Copilot setup backup")
    }
    if (-not $email) {
        Invoke-Git -Arguments @("config", "user.email", "copilot-setup@localhost")
    }

    Invoke-Git -Arguments @("add", "--all")
    Invoke-Git -Arguments @("commit", "--allow-empty", "-m", "Backup before Copilot setup replication")
}

# Every file the package ships, as a map of relative path -> absolute source.
# Two roots are merged - the platform-neutral `shared` tree and the per-platform
# overlay - with the overlay winning on a collision.
function Get-ShippedFileMap {
    $map = [ordered]@{}
    foreach ($root in @($sharedPath, $sourcePath)) {
        foreach ($file in (Get-ChildItem -LiteralPath $root -Recurse -File)) {
            $map[$file.FullName.Substring($root.Length).TrimStart("\")] = $file.FullName
        }
    }
    return $map
}

# What actually lands in ~/.copilot: everything shipped, minus the two halves of
# the composed file, plus the composed file itself.
function Get-InstalledFiles {
    param([Parameter(Mandatory)]$Map)
    return @(@($Map.Keys | Where-Object {
        $_ -ne $ComposedFile.Core -and $_ -ne $ComposedFile.Append
    }) + $ComposedFile.Output)
}

# Drop the rust server from lsp-config.json for a default (no-Rust) install, so
# no LSP entry points at a rust-analyzer that was never installed.
#
# Text surgery, not ConvertFrom-Json | ConvertTo-Json: a round trip through
# PowerShell 5.1's JSON writer reindents the whole file and would also rewrite
# its CRLF line endings, a large diff for a one-key change. The entry is
# currently last in lspServers, so the comma that has to go with it is the one
# BEFORE it; both positions are handled rather than depending on that ordering.
# The inner pattern allows exactly one level of nesting, which is the shape of
# these entries (a "fileExtensions" object). Whatever the regex does, the result
# is parsed and the server sets compared, so a mangled file fails here.
function Remove-RustLspServer {
    param([Parameter(Mandatory)][string]$Json)

    # Already absent is the wanted end state, not an error: a custom
    # -SharedSource may ship an lsp-config.json that never had a rust server.
    $before = @(($Json | ConvertFrom-Json).lspServers.PSObject.Properties.Name)
    if ($before -notcontains "rust") {
        return $Json
    }

    $body = '\{(?:[^{}]|\{[^{}]*\})*\}'
    $updated = [regex]::Replace($Json, ',\s*"rust"\s*:\s*' + $body, "")
    if ($updated -eq $Json) {
        $updated = [regex]::Replace($Json, '"rust"\s*:\s*' + $body + '\s*,\s*', "")
    }
    # It parsed as present but survived both patterns, so the patterns are wrong.
    if ($updated -eq $Json) {
        throw "Could not remove the rust server from lsp-config.json for a no-Rust install."
    }

    $after = @(($updated | ConvertFrom-Json).lspServers.PSObject.Properties.Name)
    $removed = @($before | Where-Object { $after -notcontains $_ })
    $added   = @($after  | Where-Object { $before -notcontains $_ })
    if ($removed.Count -ne 1 -or $removed[0] -ne "rust" -or $added.Count -ne 0) {
        throw "Removing the rust server from lsp-config.json changed the server set in some other way."
    }

    return $updated
}

function Copy-CopilotConfiguration {
    # Install exactly the files the package ships, at their own relative paths.
    #
    # The previous version replaced whole directories (hooks, instructions,
    # prompts, skills, intellij-skills). Three of those ship EMPTY, so it
    # deleted the user's existing instructions/, prompts/ and skills/ outright
    # and put empty directories in their place. Enumerating real files means
    # anything not shipped is simply left alone.
    $map = Get-ShippedFileMap
    foreach ($required in @($ComposedFile.Core, $ComposedFile.Append)) {
        if (-not $map.Contains($required)) {
            throw "The platform overlay is incomplete: $required was not found under $SharedSource or $ConfigSource."
        }
    }

    # copilot-instructions.md is composed from its two halves straight into
    # staging, so neither half takes part in the plain copy below.
    $shipped = @($map.Keys | Where-Object {
        $_ -ne $ComposedFile.Core -and $_ -ne $ComposedFile.Append
    })
    if (-not $shipped) {
        throw "No files found under $SharedSource or $ConfigSource - nothing to install."
    }

    # Stage everything first, then swap it in, so a failure midway leaves the
    # existing config intact rather than half-replaced.
    $stagingRoot = Join-Path $CopilotDirectory ".copilot-setup-staging-$PID"
    $backupRoot = Join-Path $CopilotDirectory ".copilot-setup-backup-$PID"
    $backedUp = @()
    $created = @()
    $rollbackFailed = $false

    try {
        New-Item -ItemType Directory -Path $stagingRoot | Out-Null
        New-Item -ItemType Directory -Path $backupRoot | Out-Null

        # copilot-instructions.md is the two halves joined byte for byte.
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

        # Post-process the staged copies rather than special-casing them in the
        # loop above, so the plain copy stays the one path every shipped file
        # takes.
        #
        # copilot-hooks.json points at the hook scripts by absolute path.
        # Forward slashes: PowerShell accepts them, and they need no JSON
        # escaping.
        $hooksConfig = Join-Path $stagingRoot "hooks\copilot-hooks.json"
        if (Test-Path $hooksConfig) {
            $forwardSlashHome = $targetPath.TrimEnd("\").Replace("\", "/")
            Write-TextFile -Path $hooksConfig `
                           -Content ([IO.File]::ReadAllText($hooksConfig).Replace("__COPILOT_HOME__", $forwardSlashHome))
        }

        if (-not $WithRust) {
            $lspConfig = Join-Path $stagingRoot "lsp-config.json"
            if (Test-Path $lspConfig) {
                Write-TextFile -Path $lspConfig `
                               -Content (Remove-RustLspServer ([IO.File]::ReadAllText($lspConfig)))
            }
        }

        foreach ($relativePath in (@($ComposedFile.Output) + $shipped)) {
            $staged = Join-Path $stagingRoot $relativePath
            $destination = Join-Path $CopilotDirectory $relativePath

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
                Remove-Item -LiteralPath (Join-Path $CopilotDirectory $relativePath) `
                            -Force -ErrorAction SilentlyContinue
            }
            for ($index = $backedUp.Count - 1; $index -ge 0; $index--) {
                $relativePath = $backedUp[$index]
                $destination = Join-Path $CopilotDirectory $relativePath
                Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
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

# For --platform copilot, graphify only installs the skill file - its
# `claude_md` flag is false, so it writes no instructions block. This strip is
# defensive: it keeps copilot-instructions.md clean if that ever changes, and
# matches the Claude script, where the block IS injected and IS redundant (the
# graphify hooks already prompt for `graphify query` and `graphify update .`).
function Remove-GraphifySection {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }

    # Rebuild with the file's own newline. copilot-instructions.md is CRLF and
    # CLAUDE.md is LF; hardcoding either would silently convert the other, and
    # the composed instructions file is guaranteed byte for byte.
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

# Install graphify's own user-level skill, so it matches the installed version.
function Install-GraphifySkill {
    if (-not (Get-Command graphify -ErrorAction SilentlyContinue)) {
        Write-Warning "graphify is not on PATH, so its skill was not installed."
        Write-Warning "Run this once it is installed:  graphify install --platform copilot"
        return
    }

    # graphify installs to the real home directory and ignores -CopilotDirectory,
    # so only run it when they are the same place.
    $defaultDirectory = [IO.Path]::GetFullPath((Join-Path $HOME ".copilot"))
    if ($targetPath.TrimEnd("\") -ne $defaultDirectory.TrimEnd("\")) {
        Write-Warning "Target is not $defaultDirectory, so the graphify skill was not installed."
        Write-Warning "Run 'graphify install --platform copilot' yourself to add it."
        return
    }

    Invoke-Native { & graphify install --platform copilot *> $null }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "'graphify install --platform copilot' failed."
        return
    }
    Write-Host "graphify skill installed at the user level."

    if (Remove-GraphifySection -Path (Join-Path $CopilotDirectory "copilot-instructions.md")) {
        Write-Host "  removed its redundant instructions block (hooks already cover it)."
    }
}

function Install-CopilotPlugin {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Marketplace,
        [Parameter(Mandatory)][string]$MarketplaceSource
    )

    if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
        Write-Warning "The 'copilot' CLI is not on PATH, so $Name was not installed. Run:"
        Write-Warning "  copilot plugin marketplace add $MarketplaceSource"
        Write-Warning "  copilot plugin install $Name"
        return
    }

    # Point the CLI at the directory being set up; it defaults to ~/.copilot and
    # would otherwise ignore -CopilotDirectory entirely.
    $previousCopilotHome = $env:COPILOT_HOME
    $env:COPILOT_HOME = $targetPath
    try {
        # The name just has to appear as its own whitespace-delimited token. Do
        # NOT try to match the list's bullet: the CLI prints U+276F, PowerShell
        # decodes native output with [Console]::OutputEncoding (IBM437 on a
        # stock console), and it arrives as the letters "Gamma yen guillemet" -
        # so a "leading non-letters" class never matches and every check comes
        # back false.
        $marketplacePattern = "(?m)(?:^|\s)$([regex]::Escape($Marketplace))(?:\s|\(|$)"
        $pluginPattern = "(?m)(?:^|\s)$([regex]::Escape($Name))(?:\s|\(|$)"

        # A plugin problem must not fail the whole run: the configuration is
        # already installed by this point, so warn and carry on.
        $marketplaces = Get-NativeText { & copilot plugin marketplace list 2>&1 }
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not list Copilot plugin marketplaces; skipping $Name."
            return
        }
        if ($marketplaces -notmatch $marketplacePattern) {
            Invoke-Native { & copilot plugin marketplace add $MarketplaceSource }
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Could not add marketplace $MarketplaceSource; skipping $Name."
                return
            }
        }

        Invoke-Native { & copilot plugin marketplace update $Marketplace }
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not update marketplace $Marketplace; continuing."
        }

        $plugins = Get-NativeText { & copilot plugin list 2>&1 }
        if ($LASTEXITCODE -eq 0 -and $plugins -match $pluginPattern) {
            return
        }

        Invoke-Native { & copilot plugin install "$($Name.Split('@')[0])@$Marketplace" }
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "'copilot plugin install $Name' returned $LASTEXITCODE."
            return
        }

        $plugins = Get-NativeText { & copilot plugin list 2>&1 }
        if ($LASTEXITCODE -ne 0 -or $plugins -notmatch $pluginPattern) {
            Write-Warning "$Name does not appear in 'copilot plugin list' after installing it."
        }
    } finally {
        $env:COPILOT_HOME = $previousCopilotHome
    }
}

if (-not $SkipToolchain) {
    Install-Toolchain
    Confirm-PythonShim
}

if (-not (Test-Path $CopilotDirectory)) {
    New-Item -ItemType Directory -Path $CopilotDirectory | Out-Null
}

if ($SkipBackup) {
    Write-Warning "-SkipBackup: $CopilotDirectory is being overwritten with no undo path."
} else {
    Backup-CopilotDirectory
}
Copy-CopilotConfiguration
Install-GraphifySkill

if (-not $SkipPlugins) {
    Install-CopilotPlugin -Name "ponytail@ponytail" -Marketplace "ponytail" -MarketplaceSource "DietrichGebert/ponytail"
}

if (-not $SkipToolchain) {
    $required = @("git", "pymanager", "python", "uv", "graphify", "jq",
                  "copilot", "dotnet", "csharp-ls")
    if ($WithRust) {
        $required += @("rustup", "rustc", "cargo", "rust-analyzer")
    }
    foreach ($command in $required) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "$command is not available on PATH after setup."
        }
    }
    # rtk is load-bearing - a hook routes shell commands through it - and merely
    # resolving on PATH is not enough, since a same-named crate exists.
    if (-not (Test-RtkIsTokenKiller)) {
        throw ("rtk is not the expected tool ('rtk gain' fails). The setup's shell hook will " +
               "break. Install it with: " +
               "winget install --id rtk-ai.rtk --exact --source winget")
    }
    # ...and the same question for the terminal the user opens next, which
    # resolves PATH in a different order than this session does.
    $persistedRtk = Get-PersistedCommandPath "rtk.exe"
    if (-not $persistedRtk) {
        throw "rtk works here but is on no persisted PATH entry, so a new terminal will not find it."
    }
    Invoke-Native { & $persistedRtk gain *> $null }
    if ($LASTEXITCODE -ne 0) {
        throw ("$persistedRtk is what a new terminal will run as 'rtk', and it is not rtk-ai/rtk " +
               "('rtk gain' fails there) - most likely the crates.io crate of the same name. It " +
               "shadows the copy just installed, and winget cannot remove it. Delete that file " +
               "(or 'cargo uninstall rtk') and re-run.")
    }
    # Node may have been skipped for lack of elevation; that only degrades the
    # TypeScript language server, so warn rather than fail the whole run.
    foreach ($command in "node", "npm", "typescript-language-server") {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            Write-Warning "$command is not on PATH. Re-run from an elevated prompt to install Node.js."
        }
    }
}

# Confirm what was installed actually landed, and that JSON config is readable.
foreach ($relativePath in (Get-InstalledFiles (Get-ShippedFileMap))) {
    $installed = Join-Path $CopilotDirectory $relativePath
    if (-not (Test-Path $installed)) {
        throw "Expected $relativePath in $CopilotDirectory after the copy, but it is missing."
    }
    if ([IO.Path]::GetExtension($relativePath) -eq ".json") {
        try {
            $null = Get-Content $installed -Raw | ConvertFrom-Json
        } catch {
            throw "$relativePath was installed but is not valid JSON: $_"
        }
    }
}

if ((Get-Content (Join-Path $CopilotDirectory "hooks\copilot-hooks.json") -Raw) -match "__COPILOT_HOME__") {
    throw "hooks\copilot-hooks.json still contains the __COPILOT_HOME__ placeholder."
}

Write-Host ""
Write-Host "Setup complete. Restart the terminal, then run: copilot"
if ($script:RestartRequired) {
    Write-Warning "Restart Windows to finish the Node.js installation."
}

# Every real failure above is a `throw`, which exits non-zero on its own. Without
# this, the exit code is whatever $LASTEXITCODE happened to be left at by the
# last native command - a warned-about plugin or a failing `rtk gain` probe would
# make a successful install look like a failed one to a caller.
exit 0
