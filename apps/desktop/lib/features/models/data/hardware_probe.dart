import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../domain/model_catalog.dart';
import '../domain/model_manager_repository.dart';

class HardwareProbe implements DeviceProbe {
  @override
  Future<DeviceCapabilities> detect(
      {required Directory modelsDirectory}) async {
    if (!Platform.isWindows) {
      return const DeviceCapabilities(
        systemMemoryBytes: 0,
        cpuArchitecture: 'Unknown',
        cpuName: 'Unknown',
        gpuAvailable: false,
        gpuVendor: null,
        gpuName: null,
        availableVramBytes: null,
        availableDiskBytes: 0,
      );
    }
    final String script = r'''
$memory = 0
$cpuName = $env:PROCESSOR_IDENTIFIER
$architecture = switch ($env:PROCESSOR_ARCHITECTURE) { 'AMD64' { 9 } 'ARM64' { 12 } default { 0 } }
$gpu = @()
try {
  $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
  $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
  $gpu = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object -First 2)
  $memory = [int64]$cs.TotalPhysicalMemory
  if ($cpu.Name) { $cpuName = [string]$cpu.Name }
  if ($null -ne $cpu.Architecture) { $architecture = [int]$cpu.Architecture }
} catch {}
if ($memory -le 0) {
  Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class ContinuumMemoryInfo {
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool GetPhysicallyInstalledSystemMemory(out long totalMemoryInKilobytes);
}
'@
  [long]$memoryKb = 0
  if ([ContinuumMemoryInfo]::GetPhysicallyInstalledSystemMemory([ref]$memoryKb)) {
    $memory = $memoryKb * 1024
  }
}
$driveRoot = [System.IO.Path]::GetPathRoot($env:CONTINUUM_MODELS_DIR)
$drive = [System.IO.DriveInfo]::new($driveRoot)
[pscustomobject]@{
  memory = [int64]$memory
  cpu = [string]$cpuName
  architecture = [int]$architecture
  gpu = @($gpu | ForEach-Object { [pscustomobject]@{ name=[string]$_.Name; vendor=[string]$_.AdapterCompatibility; memory=[int64]$_.AdapterRAM } })
  freeDisk = [int64]$drive.AvailableFreeSpace
} | ConvertTo-Json -Compress -Depth 4
''';
    final String powershell = path.join(
      Platform.environment['WINDIR'] ?? r'C:\Windows',
      'System32',
      'WindowsPowerShell',
      'v1.0',
      'powershell.exe',
    );
    final ProcessResult result = await Process.run(
      powershell,
      ['-NoProfile', '-NonInteractive', '-Command', script],
      environment: <String, String>{
        ...Platform.environment,
        'CONTINUUM_MODELS_DIR': modelsDirectory.absolute.path,
      },
    ).timeout(const Duration(seconds: 15));
    if (result.exitCode != 0) {
      throw StateError('Device information is unavailable.');
    }
    final Map<String, dynamic> json =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final List gpuList = json['gpu'] as List? ?? const [];
    final Map<String, dynamic>? gpu = gpuList.whereType<Map>().isEmpty
        ? null
        : Map<String, dynamic>.from(gpuList.first as Map);
    final int? vram = await _nvidiaFreeVram();
    final int architecture = json['architecture'] as int? ?? -1;
    return DeviceCapabilities(
      systemMemoryBytes: json['memory'] as int? ?? 0,
      cpuArchitecture: switch (architecture) {
        9 => 'x64',
        12 => 'ARM64',
        0 => 'x86',
        _ => 'Unknown',
      },
      cpuName: (json['cpu'] as String? ?? 'Unknown').trim(),
      gpuAvailable: gpu != null,
      gpuVendor: gpu?['vendor'] as String?,
      gpuName: gpu?['name'] as String?,
      availableVramBytes: vram,
      availableDiskBytes: json['freeDisk'] as int? ?? 0,
    );
  }

  Future<int?> _nvidiaFreeVram() async {
    try {
      final ProcessResult result = await Process.run(
        'nvidia-smi',
        const ['--query-gpu=memory.free', '--format=csv,noheader,nounits'],
      ).timeout(const Duration(seconds: 3));
      if (result.exitCode != 0) return null;
      final String first =
          (result.stdout as String).trim().split(RegExp(r'\s+')).first;
      return (int.tryParse(first) ?? 0) * 1024 * 1024;
    } catch (_) {
      return null;
    }
  }
}
