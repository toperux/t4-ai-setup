<#
.SYNOPSIS
Downloads the t4-ai-setup repository and runs the Claude Code installer for
Windows.

.DESCRIPTION
Intended to be fetched and executed in one line:

    irm https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-windows.ps1 | iex

`| iex` cannot pass arguments. To use the installer's flags, create a
scriptblock instead:

    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/toperux/t4-ai-setup/main/install-claude-windows.ps1))) -SkipToolchain

Everything this script does is visible above the fold - run `irm <url>` on its
own to read it before running it.
#>
[CmdletBinding()]
param(
    # Branch, tag or commit SHA to install from. Pin this for a fixed version -
    # and pin it even when you fetched this script from a tagged URL, because
    # the ref you fetched from is not carried over.
    [string]$Ref = "main",

    # Anything else is forwarded to setup-claude-windows.ps1.
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$InstallerArguments = @()
)

$ErrorActionPreference = "Stop"

# PowerShell 5.1 on older builds still negotiates TLS 1.0 by default, which
# GitHub refuses.
[Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# The piped bootstrap itself is exempt from execution policy, but the .ps1 files
# it extracts are not - the common CurrentUser default is RemoteSigned. Process
# scope only; nothing outside this window changes.
#
# Where Group Policy sets the execution policy, this call errors. Don't let that
# abort the run: the policy may still permit the extracted scripts, and if it
# doesn't, failing at the point of use is a clearer message than failing here.
try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
} catch {
    Write-Warning "Could not relax the execution policy for this process: $($_.Exception.Message)"
    Write-Warning "If the installer is then blocked, run it from a checkout instead."
}

$workspace = Join-Path ([IO.Path]::GetTempPath()) "t4-ai-setup-$PID"
$archive = Join-Path $workspace "repo.zip"

try {
    New-Item -ItemType Directory -Path $workspace -Force | Out-Null

    # A zip, not a clone: the installer is what provisions git, so the
    # bootstrap must not require it. The bare /archive/<ref>.zip form resolves
    # branches, tags and commit SHAs alike; /archive/refs/heads/<ref>.zip would
    # only resolve branches, and 404 on every tag.
    $url = "https://github.com/toperux/t4-ai-setup/archive/$Ref.zip"
    Write-Host "Downloading $url"
    $previousProgress = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"   # ~10x faster Invoke-WebRequest
    try {
        Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
    } finally {
        $ProgressPreference = $previousProgress
    }

    Expand-Archive -LiteralPath $archive -DestinationPath $workspace -Force

    # GitHub names the extracted folder after the ref; resolve it rather than
    # assuming "t4-ai-setup-main".
    $root = Get-ChildItem -LiteralPath $workspace -Directory | Select-Object -First 1
    if (-not $root) {
        throw "The downloaded archive did not contain a repository folder."
    }

    # Clear Mark-of-the-Web from the extracted scripts.
    Get-ChildItem -LiteralPath $root.FullName -Recurse -Filter *.ps1 | Unblock-File

    $installer = Join-Path $root.FullName "claude\windows\setup-claude-windows.ps1"
    if (-not (Test-Path $installer)) {
        throw "Expected the installer at $installer, but it is missing."
    }

    # Rebuild the caller's flags as a hashtable. Splatting the array directly
    # would pass every token positionally and lose the parameter names.
    $installerParameters = @{}
    $index = 0
    while ($index -lt $InstallerArguments.Count) {
        $token = $InstallerArguments[$index]
        if ($token -notlike "-*") {
            throw "Unexpected argument '$token'. Pass installer options as -Name Value."
        }
        $value = if ($index + 1 -lt $InstallerArguments.Count) { $InstallerArguments[$index + 1] } else { $null }
        if ($null -ne $value -and $value -notlike "-*") {
            $installerParameters[$token.TrimStart("-")] = $value
            $index += 2
        } else {
            $installerParameters[$token.TrimStart("-")] = $true   # a switch
            $index += 1
        }
    }

    & $installer @installerParameters
} finally {
    Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
}
