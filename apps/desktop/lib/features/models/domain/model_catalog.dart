enum ModelQuality { fast, balanced, higherQuality }

enum ModelSpeed { fast, balanced, deliberate }

enum ModelSource { huggingFace, localImport, openAi }

enum ModelProviderKind { local, openAi, gemini, custom }

enum LocalResourceProfile { conservative, balanced, performance }

class ModelDescriptor {
  const ModelDescriptor({
    required this.id,
    required this.displayName,
    required this.description,
    required this.source,
    required this.repository,
    required this.file,
    required this.downloadUrl,
    required this.downloadSize,
    required this.approximateMemoryRequirement,
    required this.qualityClass,
    required this.speedClass,
    required this.recommendedFor,
    required this.license,
    required this.licenseUrl,
    required this.sha256,
    this.contextSize = 8192,
    this.quantization,
  });

  final String id;
  final String displayName;
  final String description;
  final ModelSource source;
  final String repository;
  final String file;
  final Uri downloadUrl;
  final int downloadSize;
  final int approximateMemoryRequirement;
  final ModelQuality qualityClass;
  final ModelSpeed speedClass;
  final String recommendedFor;
  final String license;
  final Uri licenseUrl;
  final String? sha256;
  final int contextSize;
  final String? quantization;
}

class InstalledModel {
  const InstalledModel({
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.path,
    required this.sizeBytes,
    required this.source,
    required this.repository,
    required this.license,
    required this.qualityClass,
    required this.speedClass,
    required this.contextSize,
    required this.sha256,
    required this.importedAt,
  });

  final String id;
  final String displayName;
  final String fileName;
  final String path;
  final int sizeBytes;
  final ModelSource source;
  final String repository;
  final String license;
  final ModelQuality qualityClass;
  final ModelSpeed speedClass;
  final int contextSize;
  final String? sha256;
  final DateTime importedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'displayName': displayName,
        'fileName': fileName,
        'path': path,
        'sizeBytes': sizeBytes,
        'source': source.name,
        'repository': repository,
        'license': license,
        'qualityClass': qualityClass.name,
        'speedClass': speedClass.name,
        'contextSize': contextSize,
        'sha256': sha256,
        'importedAt': importedAt.toUtc().toIso8601String(),
      };

  factory InstalledModel.fromJson(Map<String, Object?> json) => InstalledModel(
        id: json['id']! as String,
        displayName: json['displayName']! as String,
        fileName: json['fileName']! as String,
        path: json['path']! as String,
        sizeBytes: json['sizeBytes']! as int,
        source: ModelSource.values.byName(json['source']! as String),
        repository: json['repository'] as String? ?? '',
        license: json['license'] as String? ?? 'Unknown',
        qualityClass:
            ModelQuality.values.byName(json['qualityClass']! as String),
        speedClass: ModelSpeed.values.byName(json['speedClass']! as String),
        contextSize: json['contextSize'] as int? ?? 8192,
        sha256: json['sha256'] as String?,
        importedAt: DateTime.parse(json['importedAt']! as String),
      );
}

class ModelSelection {
  const ModelSelection({
    required this.kind,
    required this.modelId,
    required this.displayName,
    this.providerName,
  });

  final ModelProviderKind kind;
  final String modelId;
  final String displayName;
  final String? providerName;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'modelId': modelId,
        'displayName': displayName,
        'providerName': providerName,
      };

  factory ModelSelection.fromJson(Map<String, Object?> json) => ModelSelection(
        kind: ModelProviderKind.values.byName(json['kind']! as String),
        modelId: json['modelId']! as String,
        displayName: json['displayName']! as String,
        providerName: json['providerName'] as String?,
      );
}

class DeviceCapabilities {
  const DeviceCapabilities({
    required this.systemMemoryBytes,
    required this.cpuArchitecture,
    required this.cpuName,
    required this.gpuAvailable,
    required this.gpuVendor,
    required this.gpuName,
    required this.availableVramBytes,
    required this.availableDiskBytes,
  });

  final int systemMemoryBytes;
  final String cpuArchitecture;
  final String cpuName;
  final bool gpuAvailable;
  final String? gpuVendor;
  final String? gpuName;
  final int? availableVramBytes;
  final int availableDiskBytes;
}

class ModelRecommendation {
  const ModelRecommendation({required this.model, required this.fits});
  final ModelDescriptor model;
  final bool fits;
}

class ModelDownloadProgress {
  const ModelDownloadProgress({required this.receivedBytes, this.totalBytes});
  final int receivedBytes;
  final int? totalBytes;
  double? get fraction => totalBytes == null || totalBytes! <= 0
      ? null
      : (receivedBytes / totalBytes!).clamp(0, 1);
}

enum RuntimeStatus { notInstalled, stopped, starting, ready, failed }

class RuntimeSnapshot {
  const RuntimeSnapshot({
    required this.status,
    this.version,
    this.modelId,
    this.processId,
    this.endpoint,
    this.message,
    this.logPath,
  });

  final RuntimeStatus status;
  final String? version;
  final String? modelId;
  final int? processId;
  final Uri? endpoint;
  final String? message;
  final String? logPath;
}
