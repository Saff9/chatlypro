# Chatly Desktop (Windows) build script.
#
# Runs on Windows hosts (CI: windows-2022). Builds a portable Chatly desktop binary.
#
# Required env vars:
#   TELEGRAM_API_ID
#   TELEGRAM_API_HASH
#
# Optional env vars:
#   UpstreamDir   — where to clone upstream (default: ./upstream-cache/tdesktop)
#   OutputDir     — where build artifact lands (default: ./apps/desktop/out)
#
# Prerequisites on the host (CI installs these via the upstream guide):
#   - Visual Studio 2022 with C++ workload
#   - Python 3
#   - Git, CMake, Ninja
#   - vcpkg or upstream's prepared dependencies

[CmdletBinding()]
param(
  [string]$UpstreamDir = "",
  [string]$OutputDir   = ""
)

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $Here '..\..')).Path

if (-not $UpstreamDir) { $UpstreamDir = Join-Path $RepoRoot 'upstream-cache\tdesktop' }
if (-not $OutputDir)   { $OutputDir   = Join-Path $Here    'out' }

$pinLine = Get-Content (Join-Path $Here 'upstream.txt') |
  Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' } |
  Select-Object -First 1
$parts = $pinLine -split '\s+'
$UpstreamUrl = $parts[0]
$UpstreamRef = $parts[1]

Write-Host '=========================================================='
Write-Host 'Chatly Desktop (Windows) build'
Write-Host "  upstream:     $UpstreamUrl @ $UpstreamRef"
Write-Host "  upstream dir: $UpstreamDir"
Write-Host "  output dir:   $OutputDir"
Write-Host '=========================================================='

if (-not $env:TELEGRAM_API_ID -or -not $env:TELEGRAM_API_HASH) {
  Write-Error 'TELEGRAM_API_ID and TELEGRAM_API_HASH must be set.'
  exit 65
}

# 1) Clone or update upstream.
if (-not (Test-Path (Join-Path $UpstreamDir '.git'))) {
  Write-Host '[1/4] Cloning upstream TDesktop...'
  git clone --depth 1 --branch $UpstreamRef --recurse-submodules --shallow-submodules `
    $UpstreamUrl $UpstreamDir
} else {
  Write-Host "[1/4] Updating upstream cache to $UpstreamRef..."
  git -C $UpstreamDir fetch --depth 1 origin "refs/tags/${UpstreamRef}:refs/tags/${UpstreamRef}"
  git -C $UpstreamDir checkout -f $UpstreamRef
  git -C $UpstreamDir submodule update --init --recursive --depth 1
}

# 2) Apply overlay.
Write-Host '[2/4] Applying Chatly overlay...'
$overlay = Join-Path $Here 'overlay'
if ((Test-Path $overlay) -and (Get-ChildItem $overlay -Force | Measure-Object).Count -gt 0) {
  Copy-Item -Path (Join-Path $overlay '*') -Destination $UpstreamDir -Recurse -Force
} else {
  Write-Host '  (no overlay — skipping)'
}

# 3) Apply patches.
Write-Host '[3/4] Applying Chatly patches...'
$patches = Join-Path $Here 'patches'
if (Test-Path $patches) {
  Get-ChildItem -Path $patches -Filter '*.patch' | Sort-Object Name | ForEach-Object {
    Write-Host "  applying $($_.Name)"
    git -C $UpstreamDir apply --whitespace=nowarn $_.FullName
  }
}

# 4) Build.
Write-Host '[4/4] Building TDesktop...'
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# Configure with TDESKTOP_API_ID / TDESKTOP_API_HASH baked in.
# Upstream's preferred Windows build uses cmake + ninja in a Visual Studio
# Developer prompt. We expect this script to run inside one (CI sets it up
# via microsoft/setup-msbuild + ilammy/msvc-dev-cmd).
Push-Location $UpstreamDir
try {
  cmake -B out/Release -GNinja `
    -DCMAKE_BUILD_TYPE=Release `
    -DTDESKTOP_API_ID="$env:TELEGRAM_API_ID" `
    -DTDESKTOP_API_HASH="$env:TELEGRAM_API_HASH" `
    -DDESKTOP_APP_DISABLE_AUTOUPDATE=ON `
    -DDESKTOP_APP_DISABLE_CRASH_REPORTS=ON
  cmake --build out/Release
}
finally {
  Pop-Location
}

# Collect output.
Get-ChildItem -Path (Join-Path $UpstreamDir 'out\Release') -Recurse -Include '*.exe', '*.dll' |
  ForEach-Object { Copy-Item $_.FullName -Destination $OutputDir -Force }

Write-Host ''
Write-Host "Build done. Binaries in: $OutputDir"
Get-ChildItem $OutputDir
