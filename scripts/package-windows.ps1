param(
  [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$desktopRoot = Join-Path $workspaceRoot 'apps/desktop'
$releaseDirectory = Join-Path $desktopRoot 'build/windows/x64/runner/Release'
$installerSource = Join-Path $PSScriptRoot 'installer/Package.wxs'
$artifactDirectory = Join-Path $workspaceRoot 'artifacts'
$installerPath = Join-Path $artifactDirectory 'Continuum-Setup-v1-x64.msi'
$wixDirectory = Join-Path $workspaceRoot '.tools/wix'
$generatedSource = Join-Path $wixDirectory 'Payload.wxs'
$wixExecutable = Join-Path $wixDirectory 'wix.exe'
$wixVersion = '4.0.5'

if (-not $SkipBuild) {
  Push-Location $desktopRoot
  try {
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows Release build failed.' }
  } finally {
    Pop-Location
  }
}

$applicationExecutable = Join-Path $releaseDirectory 'continuum.exe'
if (-not (Test-Path -LiteralPath $applicationExecutable)) {
  throw "Release application was not found: $applicationExecutable"
}
if (-not (Test-Path -LiteralPath (Join-Path $releaseDirectory 'data/flutter_assets'))) {
  throw 'The Flutter asset bundle is missing from the Release output.'
}

if (-not (Test-Path -LiteralPath $wixExecutable)) {
  New-Item -ItemType Directory -Path $wixDirectory -Force | Out-Null
  & dotnet tool install wix --tool-path $wixDirectory --version $wixVersion
  if ($LASTEXITCODE -ne 0) { throw "Could not install WiX Toolset $wixVersion." }
}

New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
$releaseRoot = (Resolve-Path -LiteralPath $releaseDirectory).Path.TrimEnd('\')
$directoryTree = [ordered]@{
  Id = 'INSTALLFOLDER'
  Name = ''
  Children = [ordered]@{}
  Files = [System.Collections.Generic.List[object]]::new()
}
$componentIds = [System.Collections.Generic.List[string]]::new()
$directoryComponentIds = [System.Collections.Generic.List[string]]::new()

function Get-StableHash([string] $Value) {
  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [System.BitConverter]::ToString($algorithm.ComputeHash($bytes)).Replace('-', '')
    return $hash.Substring(0, 24)
  } finally {
    $algorithm.Dispose()
  }
}

function Get-ComponentGuid([string] $RelativePath) {
  $algorithm = [System.Security.Cryptography.SHA1]::Create()
  try {
    $seed = [System.Text.Encoding]::UTF8.GetBytes("Continuum-v1/$RelativePath")
    $hash = [System.BitConverter]::ToString($algorithm.ComputeHash($seed)).Replace('-', '')
    $value = $hash.Substring(0, 32)
    $formatted = '{0}-{1}-{2}-{3}-{4}' -f `
      $value.Substring(0, 8), $value.Substring(8, 4), $value.Substring(12, 4), `
      $value.Substring(16, 4), $value.Substring(20, 12)
    return "{$($formatted.ToUpperInvariant())}"
  } finally {
    $algorithm.Dispose()
  }
}

function ConvertTo-XmlAttribute([string] $Value) {
  return [System.Security.SecurityElement]::Escape($Value)
}

$releaseFiles = Get-ChildItem -LiteralPath $releaseRoot -File -Recurse | Sort-Object FullName
if ($releaseFiles.Count -eq 0) { throw 'The Release output contains no files.' }
foreach ($file in $releaseFiles) {
  $relativePath = $file.FullName.Substring($releaseRoot.Length + 1)
  $pathParts = $relativePath -split '\\'
  $node = $directoryTree
  if ($pathParts.Length -gt 1) {
    $directoryPath = ''
    foreach ($directoryName in $pathParts[0..($pathParts.Length - 2)]) {
      $directoryPath = if ($directoryPath) {
        "$directoryPath/$directoryName"
      } else {
        $directoryName
      }
      if (-not $node.Children.Contains($directoryName)) {
        $node.Children[$directoryName] = [ordered]@{
          Id = "DIR_$(Get-StableHash $directoryPath)"
          Name = $directoryName
          Children = [ordered]@{}
          Files = [System.Collections.Generic.List[object]]::new()
        }
      }
      $node = $node.Children[$directoryName]
    }
  }

  $normalizedPath = $relativePath.Replace('\', '/')
  $componentId = "CMP_$(Get-StableHash $normalizedPath)"
  $fileId = "FILE_$(Get-StableHash $normalizedPath)"
  $sourcePath = "`$(var.PublishDir)\$relativePath"
  $componentXml = @"
        <Component Id="$componentId" Guid="$(Get-ComponentGuid $normalizedPath)">
          <File Id="$fileId" Source="$(ConvertTo-XmlAttribute $sourcePath)" />
          <RegistryValue Root="HKCU" Key="Software\Continuum\Components\$componentId" Name="Installed" Type="integer" Value="1" KeyPath="yes" />
        </Component>
"@
  $node.Files.Add($componentXml)
  $componentIds.Add($componentId)
}

$payload = [System.Text.StringBuilder]::new()
[void] $payload.AppendLine('<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">')
[void] $payload.AppendLine('  <Fragment>')
[void] $payload.AppendLine('    <DirectoryRef Id="INSTALLFOLDER">')
function Add-DirectoryPayload($Node, [int] $Indent) {
  $padding = ' ' * $Indent
  foreach ($componentXml in $Node.Files) {
    [void] $payload.AppendLine($componentXml.TrimEnd("`r", "`n"))
  }
  foreach ($directoryName in $Node.Children.Keys) {
    $child = $Node.Children[$directoryName]
    [void] $payload.AppendLine("$padding<Directory Id=`"$($child.Id)`" Name=`"$(ConvertTo-XmlAttribute $child.Name)`">")
    $directoryComponentId = "DIRCLEAN_$($child.Id.Substring(4))"
    $directoryGuid = Get-ComponentGuid "directory:$($child.Id)"
    $directoryComponentXml = @"
        <Component Id="$directoryComponentId" Guid="$directoryGuid">
          <RemoveFolder Id="REMOVE_$($child.Id.Substring(4))" On="uninstall" />
          <RegistryValue Root="HKCU" Key="Software\Continuum\Directories\$($child.Id)" Name="Installed" Type="integer" Value="1" KeyPath="yes" />
        </Component>
"@
    [void] $payload.AppendLine($directoryComponentXml.TrimEnd("`r", "`n"))
    $directoryComponentIds.Add($directoryComponentId)
    Add-DirectoryPayload $child ($Indent + 2)
    [void] $payload.AppendLine("$padding</Directory>")
  }
}
Add-DirectoryPayload $directoryTree 8
[void] $payload.AppendLine('    </DirectoryRef>')
[void] $payload.AppendLine('  </Fragment>')
[void] $payload.AppendLine('  <Fragment>')
[void] $payload.AppendLine('    <ComponentGroup Id="ApplicationFiles">')
foreach ($componentId in $componentIds) {
  [void] $payload.AppendLine("      <ComponentRef Id=`"$componentId`" />")
}
foreach ($componentId in $directoryComponentIds) {
  [void] $payload.AppendLine("      <ComponentRef Id=`"$componentId`" />")
}
[void] $payload.AppendLine('    </ComponentGroup>')
[void] $payload.AppendLine('  </Fragment>')
[void] $payload.AppendLine('</Wix>')
Set-Content -LiteralPath $generatedSource -Value $payload.ToString() -Encoding utf8

$wixArguments = @(
  'build',
  $installerSource,
  $generatedSource,
  '-arch', 'x64',
  '-d', "PublishDir=$releaseDirectory",
  '-o', $installerPath,
  '-pdbtype', 'none'
)
& $wixExecutable @wixArguments
if ($LASTEXITCODE -ne 0) { throw 'WiX failed to create the Continuum MSI.' }

if (-not (Test-Path -LiteralPath $installerPath)) {
  throw "MSI output was not created: $installerPath"
}
Write-Host "Created installer: $installerPath"
