param(
  [ValidateSet('Debug', 'Release')]
  [string] $Configuration = 'Release',
  [switch] $SkipSmokeTest
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$desktopRoot = Join-Path $workspaceRoot 'apps/desktop'

$windowsPowerShell = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'doctor.ps1') -SkipPubGet
if ($LASTEXITCODE -ne 0) { throw 'Windows environment diagnostics failed.' }

Push-Location $workspaceRoot
try {
  $dartPath = (Get-Command dart -ErrorAction SilentlyContinue).Source
  if (-not $dartPath) { $dartPath = Join-Path $env:USERPROFILE 'flutter/flutter/bin/cache/dart-sdk/bin/dart.exe' }
  & $dartPath pub get
  if ($LASTEXITCODE -ne 0) { throw 'Dart workspace dependency resolution failed.' }
} finally {
  Pop-Location
}

Push-Location $desktopRoot
try {
  & flutter analyze
  if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }
  & flutter test
  if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
  $buildMode = $Configuration.ToLowerInvariant()
  & flutter build windows "--$buildMode"
  if ($LASTEXITCODE -ne 0) { throw "Flutter Windows $Configuration build failed." }
} finally {
  Pop-Location
}

if (-not $SkipSmokeTest) {
  $executablePath = Join-Path $desktopRoot "build/windows/x64/runner/$Configuration/continuum.exe"
  if (-not (Test-Path $executablePath)) { throw "Build output was not found: $executablePath" }
  $application = Start-Process -FilePath $executablePath -PassThru -WindowStyle Hidden
  try {
    Start-Sleep -Seconds 8
    $application.Refresh()
    if ($application.HasExited) {
      throw "Continuum exited during launch smoke check (exit code $($application.ExitCode))."
    }
    Write-Host "Launch smoke check passed: $executablePath remained running for 8 seconds."
    Write-Warning 'Process survival confirms launch only. Complete the Library, Studio, Developer Tools, and storage scenarios in docs/development/windows.md.'
  } finally {
    if (-not $application.HasExited) {
      $null = $application.CloseMainWindow()
      if (-not $application.WaitForExit(3000)) { Stop-Process -Id $application.Id -Force }
    }
  }
}
