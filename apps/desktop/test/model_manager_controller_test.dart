import 'dart:async';
import 'dart:io';

import 'package:continuum_desktop/core/app_paths.dart';
import 'package:continuum_desktop/core/developer_tools_providers.dart';
import 'package:continuum_desktop/features/models/application/model_manager_controller.dart';
import 'package:continuum_desktop/features/models/data/model_downloader.dart';
import 'package:continuum_desktop/features/models/data/openai_cloud_catalog.dart';
import 'package:continuum_desktop/features/models/domain/model_catalog.dart';
import 'package:continuum_desktop/features/models/domain/model_manager_repository.dart';
import 'package:continuum_desktop/features/models/domain/model_registry.dart';
import 'package:continuum_desktop/features/models/domain/runtime_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late _MemoryRepository repository;
  late _ControlledDownloader downloader;
  late _MemorySecrets secrets;
  late _FakeCloudCatalog cloud;
  late _FakeDeviceProbe deviceProbe;
  late ProviderContainer container;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('continuum-model-manager-');
    repository = _MemoryRepository();
    downloader = _ControlledDownloader();
    secrets = _MemorySecrets();
    cloud = _FakeCloudCatalog();
    deviceProbe = _FakeDeviceProbe();
    container = ProviderContainer(overrides: [
      appPathsProvider.overrideWithValue(AppPaths(dataDirectory: temp)),
      modelManagerRepositoryProvider.overrideWithValue(repository),
      hardwareProbeProvider.overrideWithValue(deviceProbe),
      modelDownloaderProvider.overrideWithValue(downloader),
      secretStoreProvider.overrideWithValue(secrets),
      openAiCloudCatalogProvider.overrideWithValue(cloud),
      geminiCloudCatalogProvider.overrideWithValue(cloud),
      llamaRuntimeManagerProvider.overrideWithValue(_FakeRuntime()),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await temp.delete(recursive: true);
  });

  test('loads recommendations and reports download progress', () async {
    final ModelManagerController controller =
        container.read(modelManagerControllerProvider.notifier);
    await controller.load();
    expect(container.read(modelManagerControllerProvider).recommendations,
        hasLength(3));

    await controller.download(ModelRegistry.recommended.first);
    final ModelManagerState state =
        container.read(modelManagerControllerProvider);
    expect(state.installed, hasLength(1));
    expect(state.downloadingModelId, isNull);
    expect(state.infoMessage, contains('ready to use'));
  });

  test('download cancellation clears progress and does not install a model',
      () async {
    downloader.behavior = _DownloadBehavior.cancel;
    final ModelManagerController controller =
        container.read(modelManagerControllerProvider.notifier);
    await controller.load();
    final Future<void> download =
        controller.download(ModelRegistry.recommended.first);
    await downloader.started!.future;
    controller.cancelDownload();
    await download;
    final ModelManagerState state =
        container.read(modelManagerControllerProvider);
    expect(state.installed, isEmpty);
    expect(state.downloadingModelId, isNull);
    expect(state.downloadProgress, isNull);
    expect(state.infoMessage, 'Download cancelled.');
  });

  test('checksum failures become a recoverable download message', () async {
    downloader.behavior = _DownloadBehavior.checksumFailure;
    final ModelManagerController controller =
        container.read(modelManagerControllerProvider.notifier);
    await controller.load();
    await controller.download(ModelRegistry.recommended.first);
    final ModelManagerState state =
        container.read(modelManagerControllerProvider);
    expect(state.installed, isEmpty);
    expect(state.errorMessage, contains('failed verification'));
    expect(state.downloadingModelId, isNull);
  });

  test('local model can be selected and removed', () async {
    final File file = File('${temp.path}/models/local.gguf');
    await file.parent.create(recursive: true);
    await file.writeAsString('GGUF test');
    repository.models.add(_installed(file));
    final ModelManagerController controller =
        container.read(modelManagerControllerProvider.notifier);
    await controller.load();
    await controller.useLocalModel(repository.models.single);
    expect(repository.selection?.kind, ModelProviderKind.local);
    expect(repository.selection?.modelId, 'local-model');
    await controller.removeModel(repository.models.single);
    expect(await file.exists(), isFalse);
    expect(repository.selection, isNull);
  });

  test('cloud connection stores credentials and switches story model',
      () async {
    final ModelManagerController controller =
        container.read(modelManagerControllerProvider.notifier);
    await controller.load();
    await controller.connectOpenAi('secret-test-key');
    expect(cloud.lastKey, 'secret-test-key');
    expect(secrets.values['openai.api_key'], 'secret-test-key');
    expect(container.read(modelManagerControllerProvider).cloudModels,
        ['gpt-test']);
    await controller.selectCloudModel('gpt-test');
    expect(repository.selection?.kind, ModelProviderKind.openAi);
    expect(repository.selection?.modelId, 'gpt-test');
  });

  test('provider network errors do not expose URLs or raw exception text',
      () async {
    cloud.failWithNetworkError = true;
    final ModelManagerController controller =
        container.read(modelManagerControllerProvider.notifier);
    await controller.load();
    await controller.connectOpenAi('secret-test-key');
    final String message =
        container.read(modelManagerControllerProvider).errorMessage!;
    expect(message, contains('connect securely'));
    expect(message, isNot(contains('api.openai.com')));
    expect(message, isNot(contains('socket details')));
  });

  test('Gemini connection stores a separate key and selects Gemini models',
      () async {
    final ModelManagerController controller =
        container.read(modelManagerControllerProvider.notifier);
    await controller.load();
    await controller.connectGemini('gemini-test-key');
    expect(secrets.values['gemini.api_key'], 'gemini-test-key');
    expect(secrets.values, isNot(contains('openai.api_key')));
    expect(container.read(modelManagerControllerProvider).cloudProvider,
        ModelProviderKind.gemini);
    await controller.selectCloudModel('gemini-test',
        provider: ModelProviderKind.gemini);
    expect(repository.selection?.kind, ModelProviderKind.gemini);
    expect(repository.selection?.providerName, 'Gemini');
  });

  test('local resource profile persists and is restored on load', () async {
    final ModelManagerController controller =
        container.read(modelManagerControllerProvider.notifier);
    await controller.load();
    await controller.setLocalResourceProfile(LocalResourceProfile.performance);
    expect(repository.localResourceProfile, LocalResourceProfile.performance);
    await controller.load();
    expect(container.read(modelManagerControllerProvider).localResourceProfile,
        LocalResourceProfile.performance);
  });

  test('device probe failures do not block model management', () async {
    deviceProbe.fail = true;
    final ModelManagerController controller =
        container.read(modelManagerControllerProvider.notifier);
    await controller.load();
    final ModelManagerState state =
        container.read(modelManagerControllerProvider);
    expect(state.errorMessage, isNull);
    expect(state.infoMessage, contains('Device details are unavailable'));
    expect(state.recommendations, hasLength(3));
  });
}

InstalledModel _installed(File file) => InstalledModel(
      id: 'local-model',
      displayName: 'Local model',
      fileName: file.uri.pathSegments.last,
      path: file.path,
      sizeBytes: 9,
      source: ModelSource.localImport,
      repository: 'Local import',
      license: 'Unknown',
      qualityClass: ModelQuality.balanced,
      speedClass: ModelSpeed.balanced,
      contextSize: 4096,
      sha256: null,
      importedAt: DateTime.utc(2026),
    );

class _MemoryRepository implements ModelManagerRepository {
  final List<InstalledModel> models = [];
  ModelSelection? selection;
  LocalResourceProfile localResourceProfile = LocalResourceProfile.balanced;

  @override
  Future<ModelSelection?> getSelection() async => selection;
  @override
  Future<List<InstalledModel>> listInstalled() async => [...models];
  @override
  Future<void> removeInstalled(String modelId) async {
    final InstalledModel? removed =
        models.where((InstalledModel model) => model.id == modelId).firstOrNull;
    if (removed != null) await File(removed.path).delete();
    models.removeWhere((InstalledModel model) => model.id == modelId);
    if (selection?.modelId == modelId) selection = null;
  }

  @override
  Future<void> saveInstalled(InstalledModel model) async {
    models.removeWhere((InstalledModel item) => item.id == model.id);
    models.add(model);
  }

  @override
  Future<void> saveSelection(ModelSelection value) async => selection = value;
  @override
  Future<void> clearSelection() async => selection = null;
  @override
  Future<LocalResourceProfile> getLocalResourceProfile() async =>
      localResourceProfile;
  @override
  Future<void> saveLocalResourceProfile(LocalResourceProfile profile) async =>
      localResourceProfile = profile;
}

class _MemorySecrets implements SecretStore {
  final Map<String, String> values = {};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FakeDeviceProbe implements DeviceProbe {
  bool fail = false;

  @override
  Future<DeviceCapabilities> detect(
      {required Directory modelsDirectory}) async {
    if (fail) throw StateError('WMI permission denied');
    return const DeviceCapabilities(
      systemMemoryBytes: 16 * 1000 * 1000 * 1000,
      cpuArchitecture: 'x64',
      cpuName: 'Test CPU',
      gpuAvailable: false,
      gpuVendor: null,
      gpuName: null,
      availableVramBytes: null,
      availableDiskBytes: 50 * 1000 * 1000 * 1000,
    );
  }
}

class _FakeCloudCatalog implements CloudModelCatalog {
  String? lastKey;
  bool failWithNetworkError = false;
  @override
  Future<List<String>> listModels(String apiKey) async {
    lastKey = apiKey;
    if (failWithNetworkError) {
      throw const HttpException(
        'socket details at https://api.openai.com/v1/models',
      );
    }
    return ['gpt-test'];
  }
}

class _FakeRuntime implements RuntimeManager {
  @override
  RuntimeSnapshot get snapshot =>
      const RuntimeSnapshot(status: RuntimeStatus.stopped);
  @override
  Stream<RuntimeSnapshot> get changes => const Stream.empty();
  @override
  Future<Uri> ensureReady(InstalledModel model,
          {LocalResourceProfile resourceProfile =
              LocalResourceProfile.balanced}) async =>
      Uri.parse('http://127.0.0.1:1/v1');
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

enum _DownloadBehavior { success, cancel, checksumFailure }

class _ControlledDownloader implements ModelDownloader {
  _DownloadBehavior behavior = _DownloadBehavior.success;
  Completer<void>? started;

  @override
  Future<File> download({
    required Uri uri,
    required File destination,
    required String? expectedSha256,
    required void Function(ModelDownloadProgress progress) onProgress,
    required bool Function() isCancelled,
  }) async {
    onProgress(
        const ModelDownloadProgress(receivedBytes: 128, totalBytes: 256));
    if (behavior == _DownloadBehavior.cancel) {
      started = Completer<void>()..complete();
      while (!isCancelled()) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      throw const DownloadCancelled();
    }
    if (behavior == _DownloadBehavior.checksumFailure) {
      throw const FileSystemException('Model checksum verification failed.');
    }
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(const [71, 71, 85, 70]);
    onProgress(
        const ModelDownloadProgress(receivedBytes: 256, totalBytes: 256));
    return destination;
  }
}
