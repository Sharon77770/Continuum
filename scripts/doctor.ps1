param(
  [switch] $SkipPubGet
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$desktopRoot = Join-Path $workspaceRoot 'apps/desktop'
$failed = $false

function Write-Check([string] $label, [bool] $passed, [string] $detail) {
  $color = if ($passed) { 'Green' } else { 'Red' }
  $status = if ($passed) { 'PASS' } else { 'FAIL' }
  Write-Host "[$status] $label - $detail" -ForegroundColor $color
}

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter -and $env:USERPROFILE) {
  $bundledFlutter = Join-Path $env:USERPROFILE 'flutter/flutter/bin/flutter.bat'
  if (Test-Path $bundledFlutter) { $flutter = Get-Item $bundledFlutter }
}
$dart = Get-Command dart -ErrorAction SilentlyContinue
if (-not $dart -and $env:USERPROFILE) {
  $bundledDart = Join-Path $env:USERPROFILE 'flutter/flutter/bin/cache/dart-sdk/bin/dart.exe'
  if (Test-Path $bundledDart) { $dart = Get-Item $bundledDart }
}
$vswherePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$hasVsCpp = $false
if (Test-Path $vswherePath) {
  $vsCppPath = & $vswherePath -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  $hasVsCpp = -not [string]::IsNullOrWhiteSpace($vsCppPath)
}
$cmake = Get-Command cmake -ErrorAction SilentlyContinue
if (-not $cmake) {
  $visualStudioRoots = @()
  if ($hasVsCpp) { $visualStudioRoots += $vsCppPath }
  $visualStudioRoots += @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio'),
    (Join-Path $env:ProgramFiles 'Microsoft Visual Studio')
  )
  foreach ($visualStudioRoot in $visualStudioRoots) {
    $installations = @(Get-ChildItem $visualStudioRoot -Directory -ErrorAction SilentlyContinue)
    if (Test-Path (Join-Path $visualStudioRoot 'Common7')) {
      $installations = @((Get-Item $visualStudioRoot))
    }
    $cmakeCandidates = $installations |
      ForEach-Object { Join-Path $_.FullName 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe' }
    $cmakePath = $cmakeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($cmakePath) { $cmake = Get-Item $cmakePath; break }
  }
}
$flutterPath = if ($flutter -is [System.IO.FileInfo]) { $flutter.FullName } else { $flutter.Source }
$dartPath = if ($dart -is [System.IO.FileInfo]) { $dart.FullName } else { $dart.Source }
$cmakeDisplayPath = if ($cmake -is [System.IO.FileInfo]) { $cmake.FullName } else { $cmake.Source }

Write-Check 'Flutter SDK' ($null -ne $flutter) $(if ($flutter) { $flutterPath } else { 'Install Flutter and add flutter/bin to PATH.' })
if ($null -eq $flutter) { $failed = $true }
Write-Check 'Dart SDK' ($null -ne $dart) $(if ($dart) { $dartPath } else { 'Install Flutter; Dart is distributed with the Flutter SDK.' })
if ($null -eq $dart) { $failed = $true }
Write-Check 'CMake' ($null -ne $cmake) $(if ($cmake) { $cmakeDisplayPath } else { 'Install CMake or add it to PATH.' })
if ($null -eq $cmake) { $failed = $true }
Write-Check 'Visual Studio C++ workload' $hasVsCpp $(if ($hasVsCpp) { $vsCppPath } else { 'Install Visual Studio 2022 with Desktop development with C++ and a Windows SDK.' })
if (-not $hasVsCpp) { $failed = $true }

if ($flutter) {
  Push-Location $desktopRoot
  try {
    Write-Host "`nFlutter environment (flutter doctor -v):"
    & $flutterPath doctor -v
    if ($LASTEXITCODE -ne 0) { $failed = $true }
    Write-Host "`nAvailable Flutter devices:"
    $devicesOutput = & $flutterPath devices 2>&1 | Out-String
    Write-Host $devicesOutput
    if ($LASTEXITCODE -ne 0) { $failed = $true }
    $hasWindowsDevice = $devicesOutput -match '(?im)^\s*Windows\s+\('
    Write-Check 'Windows desktop device' $hasWindowsDevice $(if ($hasWindowsDevice) { 'Flutter lists the Windows target.' } else { 'Enable Windows desktop with flutter config --enable-windows-desktop, then rerun this script.' })
    if (-not $hasWindowsDevice) { $failed = $true }
  } finally {
    Pop-Location
  }
}

if (-not (Get-Command nuget -ErrorAction SilentlyContinue)) {
  Write-Warning 'NuGet was not found on PATH. Flutter or Visual Studio may still provide the NuGet client used by the Windows build.'
}

if (-not $SkipPubGet -and $dart) {
  Push-Location $workspaceRoot
  try {
    Write-Host "`nResolving Dart workspace dependencies: dart pub get"
    & $dartPath pub get
    if ($LASTEXITCODE -ne 0) { $failed = $true }
  } finally {
    Pop-Location
  }
}

if ($failed) {
  Write-Error 'Environment checks found a missing prerequisite or a failing Flutter diagnostic.'
  exit 1
}
Write-Host 'Continuum Windows development prerequisites are available.' -ForegroundColor Green
