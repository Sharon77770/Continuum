# Continuum

Continuum is a Windows desktop application for creating interactive story worlds and playing them with local or cloud language models.

## Download for Windows

Download the single-file installer: [Continuum Windows x64 Installer (MSI)](https://github.com/Sharon77770/Continuum/raw/refs/heads/main/artifacts/Continuum-Setup-v1-x64.msi).

The same file is stored in this repository at `artifacts/Continuum-Setup-v1-x64.msi`. Run the MSI and follow Windows Installer. It installs the complete application, including the Flutter engine, native plugins, SQLite library, and Flutter assets, under `%LOCALAPPDATA%\Continuum`, and adds Continuum to the current user's Start menu. No separate application files or administrator permission are required.

## Build the installer

Requirements: Flutter stable with Windows desktop support, .NET SDK, and an internet connection the first time WiX is installed.

From the repository root:

```powershell
./scripts/package-windows.ps1
```

This builds the Windows x64 Release app and creates `artifacts/Continuum-Setup-v1-x64.msi`. WiX Toolset 4.0.5 is installed into the ignored `.tools/wix` directory when it is not already present.
