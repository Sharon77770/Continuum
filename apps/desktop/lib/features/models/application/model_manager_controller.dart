import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../../core/app_paths.dart';
import '../../../core/developer_tools_providers.dart';
import '../../novel/domain/language_model_settings.dart';
import '../../novel/data/llm_provider.dart';
import '../data/hardware_probe.dart';
import '../data/hugging_face_catalog.dart';
import '../data/llama_runtime_manager.dart';
import '../data/model_downloader.dart';
import '../data/managed_language_model.dart';
import '../data/model_manager_repository.dart';
import '../data/openai_cloud_catalog.dart';
import '../data/secure_secret_store.dart';
import '../domain/model_catalog.dart';
import '../domain/model_manager_repository.dart';
import '../domain/model_registry.dart';
import '../domain/runtime_manager.dart';

final modelManagerRepositoryProvider = Provider<ModelManagerRepository>((ref) =>
    JsonModelManagerRepository(ref.watch(appPathsProvider).modelsDirectory));
final secretStoreProvider =
    Provider<SecretStore>((ref) => FlutterSecureSecretStore());
final hardwareProbeProvider = Provider<DeviceProbe>((ref) => HardwareProbe());
final modelDownloaderProvider = Provider<ModelDownloader>((ref) {
  final HttpModelDownloader downloader = HttpModelDownloader();
  ref.onDispose(downloader.close);
  return downloader;
});
final huggingFaceCatalogProvider = Provider<HuggingFaceCatalog>((ref) {
  final HuggingFaceCatalog catalog = HuggingFaceCatalog();
  ref.onDispose(catalog.close);
  return catalog;
});
final openAiCloudCatalogProvider = Provider<CloudModelCatalog>((ref) {
  final OpenAiCloudCatalog catalog = OpenAiCloudCatalog();
  ref.onDispose(catalog.close);
  return catalog;
});
final geminiCloudCatalogProvider = Provider<CloudModelCatalog>((ref) {
  final GeminiCloudCatalog catalog = GeminiCloudCatalog();
  ref.onDispose(catalog.close);
  return catalog;
});
final llamaRuntimeManagerProvider = Provider<RuntimeManager>((ref) {
  final AppPaths paths = ref.watch(appPathsProvider);
  final RuntimeManager manager = LlamaRuntimeManager(
    modelsDirectory: paths.modelsDirectory,
    logDirectory: paths.runtimeLogDirectory,
    installer:
        GitHubLlamaBinaryInstaller(installDirectory: paths.runtimeDirectory),
  );
  ref.onDispose(() => unawaited(manager.dispose()));
  return manager;
});
final managedLanguageModelProvider = Provider<LlmProvider>((ref) {
  final ManagedLanguageModel provider = ManagedLanguageModel(
    modelRepository: ref.watch(modelManagerRepositoryProvider),
    secrets: ref.watch(secretStoreProvider),
    runtime: ref.watch(llamaRuntimeManagerProvider),
  );
  ref.onDispose(provider.close);
  return provider;
});

final modelManagerControllerProvider =
    NotifierProvider<ModelManagerController, ModelManagerState>(
        ModelManagerController.new);

class ModelManagerState {
  const ModelManagerState({
    this.installed = const [],
    this.recommendations = const [],
    this.device,
    this.selection,
    this.localResourceProfile = LocalResourceProfile.balanced,
    this.downloadProgress,
    this.downloadingModelId,
    this.discovered = const [],
    this.cloudModels = const [],
    this.cloudProvider,
    this.runtime = const RuntimeSnapshot(status: RuntimeStatus.stopped),
    this.isLoading = false,
    this.isSearching = false,
    this.errorMessage,
    this.infoMessage,
  });

  final List<InstalledModel> installed;
  final List<ModelRecommendation> recommendations;
  final DeviceCapabilities? device;
  final ModelSelection? selection;
  final LocalResourceProfile localResourceProfile;
  final ModelDownloadProgress? downloadProgress;
  final String? downloadingModelId;
  final List<DiscoveredModel> discovered;
  final List<String> cloudModels;
  final ModelProviderKind? cloudProvider;
  final RuntimeSnapshot runtime;
  final bool isLoading;
  final bool isSearching;
  final String? errorMessage;
  final String? infoMessage;

  ModelManagerState copyWith({
    List<InstalledModel>? installed,
    List<ModelRecommendation>? recommendations,
    DeviceCapabilities? device,
    ModelSelection? selection,
    LocalResourceProfile? localResourceProfile,
    bool clearSelection = false,
    ModelDownloadProgress? downloadProgress,
    bool clearDownloadProgress = false,
    String? downloadingModelId,
    bool clearDownloadingModel = false,
    List<DiscoveredModel>? discovered,
    List<String>? cloudModels,
    ModelProviderKind? cloudProvider,
    RuntimeSnapshot? runtime,
    bool? isLoading,
    bool? isSearching,
    String? errorMessage,
    bool clearError = false,
    String? infoMessage,
    bool clearInfo = false,
  }) =>
      ModelManagerState(
        installed: installed ?? this.installed,
        recommendations: recommendations ?? this.recommendations,
        device: device ?? this.device,
        selection: clearSelection ? null : selection ?? this.selection,
        localResourceProfile: localResourceProfile ?? this.localResourceProfile,
        downloadProgress: clearDownloadProgress
            ? null
            : downloadProgress ?? this.downloadProgress,
        downloadingModelId: clearDownloadingModel
            ? null
            : downloadingModelId ?? this.downloadingModelId,
        discovered: discovered ?? this.discovered,
        cloudModels: cloudModels ?? this.cloudModels,
        cloudProvider: cloudProvider ?? this.cloudProvider,
        runtime: runtime ?? this.runtime,
        isLoading: isLoading ?? this.isLoading,
        isSearching: isSearching ?? this.isSearching,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
        infoMessage: clearInfo ? null : infoMessage ?? this.infoMessage,
      );
}

class ModelManagerController extends Notifier<ModelManagerState> {
  bool _cancelDownload = false;
  StreamSubscription<RuntimeSnapshot>? _runtimeSubscription;

  @override
  ModelManagerState build() {
    _runtimeSubscription = ref
        .read(llamaRuntimeManagerProvider)
        .changes
        .listen((RuntimeSnapshot snapshot) {
      state = state.copyWith(runtime: snapshot);
    });
    ref.onDispose(() => _runtimeSubscription?.cancel());
    return const ModelManagerState(isLoading: true);
  }

  Future<void> load({bool refreshCloudModels = false}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final AppPaths paths = ref.read(appPathsProvider);
      await paths.initialize();
      DeviceCapabilities device;
      String? deviceMessage;
      try {
        device = await ref
            .read(hardwareProbeProvider)
            .detect(modelsDirectory: paths.modelsDirectory);
      } catch (_) {
        device = const DeviceCapabilities(
          systemMemoryBytes: 0,
          cpuArchitecture: 'Unknown',
          cpuName: 'Unknown',
          gpuAvailable: false,
          gpuVendor: null,
          gpuName: null,
          availableVramBytes: null,
          availableDiskBytes: 0,
        );
        deviceMessage =
            'Device details are unavailable. Model management is still available; check free space before downloading.';
      }
      final ModelManagerRepository repository =
          ref.read(modelManagerRepositoryProvider);
      final List<InstalledModel> installed = await repository.listInstalled();
      ModelSelection? selection = await repository.getSelection();
      final LocalResourceProfile localResourceProfile =
          await repository.getLocalResourceProfile();
      String? loadMessage;
      List<String> cloudModels = const [];
      if (selection?.kind == ModelProviderKind.local &&
          !installed
              .any((InstalledModel model) => model.id == selection?.modelId)) {
        await repository.clearSelection();
        selection = null;
        loadMessage =
            'The selected model file is missing. Choose another model.';
      }
      if (refreshCloudModels &&
          (selection?.kind == ModelProviderKind.openAi ||
              selection?.kind == ModelProviderKind.gemini)) {
        final bool isGemini = selection?.kind == ModelProviderKind.gemini;
        final String secretName =
            isGemini ? 'gemini.api_key' : 'openai.api_key';
        final String? key =
            await ref.read(secretStoreProvider).read(secretName);
        if (key != null) {
          try {
            cloudModels = await (isGemini
                    ? ref.read(geminiCloudCatalogProvider)
                    : ref.read(openAiCloudCatalogProvider))
                .listModels(key);
          } catch (_) {
            // Offline launch still leaves the stored provider selected.
          }
        }
      }
      state = state.copyWith(
        installed: installed,
        selection: selection,
        localResourceProfile: localResourceProfile,
        recommendations: ModelRegistry.recommend(device),
        device: device,
        cloudModels: cloudModels,
        cloudProvider: selection?.kind == ModelProviderKind.gemini ||
                selection?.kind == ModelProviderKind.openAi
            ? selection!.kind
            : null,
        runtime: ref.read(llamaRuntimeManagerProvider).snapshot,
        isLoading: false,
        errorMessage: loadMessage,
        clearError: loadMessage == null,
        infoMessage: loadMessage == null ? deviceMessage : null,
        clearInfo: loadMessage != null || deviceMessage == null,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _userMessage(error),
      );
    }
  }

  void showMessage(String message) {
    state = state.copyWith(infoMessage: message, clearError: true);
  }

  Future<void> download(ModelDescriptor model) async {
    if (state.downloadingModelId != null) return;
    final DeviceCapabilities? device = state.device;
    if (device != null &&
        device.availableDiskBytes > 0 &&
        device.availableDiskBytes < model.downloadSize) {
      state = state.copyWith(
          errorMessage: 'There is not enough free disk space for this model.');
      return;
    }
    _cancelDownload = false;
    state = state.copyWith(
      downloadingModelId: model.id,
      downloadProgress: const ModelDownloadProgress(receivedBytes: 0),
      clearError: true,
      clearInfo: true,
    );
    final Directory models = ref.read(appPathsProvider).modelsDirectory;
    final String safeName =
        path.basename(model.file).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final String safeId = model.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final File target = File(path.join(models.path, '$safeId-$safeName'));
    try {
      final File downloaded = await ref.read(modelDownloaderProvider).download(
            uri: model.downloadUrl,
            destination: target,
            expectedSha256: model.sha256,
            isCancelled: () => _cancelDownload,
            onProgress: (ModelDownloadProgress progress) {
              state = state.copyWith(downloadProgress: progress);
            },
          );
      final InstalledModel installed = InstalledModel(
        id: model.id,
        displayName: model.displayName,
        fileName: path.basename(downloaded.path),
        path: downloaded.absolute.path,
        sizeBytes: await downloaded.length(),
        source: model.source,
        repository: model.repository,
        license: model.license,
        qualityClass: model.qualityClass,
        speedClass: model.speedClass,
        contextSize: model.contextSize,
        sha256: model.sha256,
        importedAt: DateTime.now().toUtc(),
      );
      final ModelManagerRepository repository =
          ref.read(modelManagerRepositoryProvider);
      await repository.saveInstalled(installed);
      state = state.copyWith(
        installed: await repository.listInstalled(),
        infoMessage: '${model.displayName} is ready to use.',
        clearDownloadProgress: true,
        clearDownloadingModel: true,
      );
    } on DownloadCancelled {
      state = state.copyWith(
        infoMessage: 'Download cancelled.',
        clearDownloadProgress: true,
        clearDownloadingModel: true,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        errorMessage: _userMessage(error),
        clearDownloadProgress: true,
        clearDownloadingModel: true,
      );
    }
  }

  void cancelDownload() => _cancelDownload = true;

  Future<void> useLocalModel(InstalledModel model) async {
    if (!await File(model.path).exists()) {
      state = state.copyWith(
          errorMessage:
              'This model file is missing. Import or download it again.');
      return;
    }
    final ModelSelection selection = ModelSelection(
      kind: ModelProviderKind.local,
      modelId: model.id,
      displayName: model.displayName,
    );
    await ref.read(modelManagerRepositoryProvider).saveSelection(selection);
    state = state.copyWith(
        selection: selection,
        infoMessage: 'Story model updated.',
        clearError: true);
  }

  Future<void> setLocalResourceProfile(LocalResourceProfile profile) async {
    if (profile == state.localResourceProfile) return;
    try {
      await ref
          .read(modelManagerRepositoryProvider)
          .saveLocalResourceProfile(profile);
    } catch (error) {
      state = state.copyWith(errorMessage: _userMessage(error));
      return;
    }
    state = state.copyWith(
      localResourceProfile: profile,
      clearInfo: true,
      clearError: true,
    );
    final bool localSelected = state.selection?.kind == ModelProviderKind.local;
    if (localSelected &&
        (state.runtime.status == RuntimeStatus.ready ||
            state.runtime.status == RuntimeStatus.starting)) {
      await startSelectedModel();
    }
  }

  Future<void> removeModel(InstalledModel model) async {
    if (state.selection?.modelId == model.id &&
        state.selection?.kind == ModelProviderKind.local) {
      await ref.read(llamaRuntimeManagerProvider).stop();
    }
    final ModelManagerRepository repository =
        ref.read(modelManagerRepositoryProvider);
    await repository.removeInstalled(model.id);
    state = state.copyWith(
      installed: await repository.listInstalled(),
      clearSelection: state.selection?.modelId == model.id,
      infoMessage: 'Model removed from this device.',
    );
  }

  Future<void> discover(String query) async {
    state = state.copyWith(isSearching: true, clearError: true);
    try {
      final List<DiscoveredModel> results =
          await ref.read(huggingFaceCatalogProvider).search(query);
      state = state.copyWith(discovered: results, isSearching: false);
    } catch (error) {
      state =
          state.copyWith(isSearching: false, errorMessage: _userMessage(error));
    }
  }

  Future<void> connectOpenAi(String apiKey) async {
    await _connectCloud(apiKey,
        secretName: 'openai.api_key',
        catalog: ref.read(openAiCloudCatalogProvider),
        provider: 'OpenAI');
  }

  Future<void> connectGemini(String apiKey) async {
    await _connectCloud(apiKey,
        secretName: 'gemini.api_key',
        catalog: ref.read(geminiCloudCatalogProvider),
        provider: 'Gemini');
  }

  Future<void> _connectCloud(String apiKey,
      {required String secretName,
      required CloudModelCatalog catalog,
      required String provider}) async {
    if (apiKey.trim().isEmpty) {
      state = state.copyWith(errorMessage: 'Enter an API key to connect.');
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final List<String> models = await catalog.listModels(apiKey);
      await ref.read(secretStoreProvider).write(secretName, apiKey.trim());
      state = state.copyWith(
        cloudModels: models,
        cloudProvider: provider == 'Gemini'
            ? ModelProviderKind.gemini
            : ModelProviderKind.openAi,
        isLoading: false,
        infoMessage: '$provider connected. Choose a story model.',
      );
    } catch (error) {
      state =
          state.copyWith(isLoading: false, errorMessage: _userMessage(error));
    }
  }

  Future<void> selectCloudModel(String modelId,
      {ModelProviderKind provider = ModelProviderKind.openAi}) async {
    final String providerName =
        provider == ModelProviderKind.gemini ? 'Gemini' : 'OpenAI';
    final ModelSelection selection = ModelSelection(
      kind: provider,
      modelId: modelId,
      displayName: modelId,
      providerName: providerName,
    );
    await ref.read(modelManagerRepositoryProvider).saveSelection(selection);
    state = state.copyWith(
        selection: selection,
        infoMessage: 'Story model updated.',
        clearError: true);
  }

  Future<void> selectCustomProvider(LanguageModelSettings settings) async {
    if (settings.model.trim().isEmpty) {
      state = state.copyWith(
          errorMessage: 'Set a model name under Advanced first.');
      return;
    }
    final ModelSelection selection = ModelSelection(
      kind: ModelProviderKind.custom,
      modelId: settings.model,
      displayName: settings.model,
      providerName: 'Custom Provider',
    );
    await ref.read(modelManagerRepositoryProvider).saveSelection(selection);
    state = state.copyWith(
        selection: selection,
        infoMessage: 'Custom Provider selected.',
        clearError: true);
  }

  Future<void> importLocalModel() async {
    final XFile? selected = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'GGUF model', extensions: ['gguf']),
    ]);
    if (selected == null) return;
    final File source = File(selected.path);
    final RandomAccessFile reader = await source.open(mode: FileMode.read);
    final List<int> magic;
    try {
      magic = await reader.read(4);
    } finally {
      await reader.close();
    }
    if (String.fromCharCodes(magic) != 'GGUF') {
      state = state.copyWith(
          errorMessage: 'This file is not a compatible GGUF model.');
      return;
    }
    final int size = await source.length();
    final DeviceCapabilities? device = state.device;
    if (device != null &&
        device.availableDiskBytes > 0 &&
        device.availableDiskBytes < size) {
      state = state.copyWith(
          errorMessage:
              'There is not enough free disk space to import this model.');
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final String hash =
          (await sha256.bind(source.openRead()).first).toString();
      final String name = path.basename(source.path);
      final File target = File(path.join(
          ref.read(appPathsProvider).modelsDirectory.path,
          '${hash.substring(0, 16)}-$name'));
      await target.parent.create(recursive: true);
      await source.openRead().pipe(target.openWrite());
      final InstalledModel model = InstalledModel(
        id: 'import:$hash',
        displayName: path.basenameWithoutExtension(name),
        fileName: path.basename(target.path),
        path: target.absolute.path,
        sizeBytes: size,
        source: ModelSource.localImport,
        repository: 'Local import',
        license: 'Unknown',
        qualityClass: ModelQuality.balanced,
        speedClass: ModelSpeed.balanced,
        contextSize: 8192,
        sha256: hash,
        importedAt: DateTime.now().toUtc(),
      );
      final ModelManagerRepository repository =
          ref.read(modelManagerRepositoryProvider);
      await repository.saveInstalled(model);
      state = state.copyWith(
        installed: await repository.listInstalled(),
        isLoading: false,
        infoMessage: 'Model imported. Review its license before use.',
      );
    } catch (error) {
      state =
          state.copyWith(isLoading: false, errorMessage: _userMessage(error));
    }
  }

  Future<void> startSelectedModel() async {
    final ModelSelection? selection = state.selection;
    if (selection == null || selection.kind != ModelProviderKind.local) return;
    final InstalledModel? model = state.installed
        .where((InstalledModel item) => item.id == selection.modelId)
        .firstOrNull;
    if (model == null) {
      state = state.copyWith(
          errorMessage:
              'This model file is missing. Import or download it again.');
      return;
    }
    try {
      await ref
          .read(llamaRuntimeManagerProvider)
          .ensureReady(model, resourceProfile: state.localResourceProfile);
    } catch (error) {
      state = state.copyWith(
          runtime: ref.read(llamaRuntimeManagerProvider).snapshot,
          errorMessage: _userMessage(error));
    }
  }

  Future<void> restartRuntime() async {
    await ref.read(llamaRuntimeManagerProvider).stop();
    await startSelectedModel();
  }

  Future<void> openModelDirectory() async {
    final Directory directory = ref.read(appPathsProvider).modelsDirectory;
    await directory.create(recursive: true);
    final String executable = Platform.isWindows ? 'explorer.exe' : 'xdg-open';
    await Process.start(executable, [directory.absolute.path],
        mode: ProcessStartMode.detached);
  }

  Future<void> openRuntimeLog() async {
    final String? logPath =
        ref.read(llamaRuntimeManagerProvider).snapshot.logPath;
    if (logPath == null || !await File(logPath).exists()) {
      state = state.copyWith(
          infoMessage: 'The runtime log has not been created yet.');
      return;
    }
    await Process.start(
        Platform.isWindows ? 'notepad.exe' : 'xdg-open', [logPath],
        mode: ProcessStartMode.detached);
  }

  String _userMessage(Object error) {
    if (error is RuntimeFailure) return error.message;
    if (error is DownloadCancelled) return 'Download cancelled.';
    if (error is FileSystemException) {
      if (error.message.contains('checksum')) {
        return 'The downloaded file failed verification and was removed.';
      }
      return 'The model could not be saved. Check available disk space and folder permissions.';
    }
    if (error is HttpException || error is SocketException) {
      return 'Continuum could not connect securely. Check your network and try again.';
    }
    if (error is TimeoutException) {
      return 'The request took too long. Check your network and try again.';
    }
    if (error is FormatException) {
      return 'Continuum could not read the model information. Try again later.';
    }
    if (error is StateError) return error.message;
    return 'Continuum could not complete this model action. Try again or check Developer Tools for details.';
  }
}
