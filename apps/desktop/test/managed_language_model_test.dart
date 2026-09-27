import 'dart:io';

import 'package:continuum_desktop/features/models/data/managed_language_model.dart';
import 'package:continuum_desktop/features/models/domain/model_catalog.dart';
import 'package:continuum_desktop/features/models/domain/model_manager_repository.dart';
import 'package:continuum_desktop/features/models/domain/runtime_manager.dart';
import 'package:continuum_desktop/features/novel/data/llm_provider.dart';
import 'package:continuum_desktop/features/novel/domain/language_model_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late _Repository repository;
  late _Secrets secrets;
  late _Runtime runtime;
  late _Transport transport;
  late ManagedLanguageModel model;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('continuum-managed-model-');
    repository = _Repository();
    secrets = _Secrets();
    runtime = _Runtime();
    transport = _Transport();
    model = ManagedLanguageModel(
      modelRepository: repository,
      secrets: secrets,
      runtime: runtime,
      transport: transport,
    );
  });

  tearDown(() async {
    model.close();
    await temp.delete(recursive: true);
  });

  test('local, cloud and custom selections use the unified model interface',
      () async {
    final File localFile = File('${temp.path}/story.gguf');
    await localFile.writeAsString('GGUF');
    repository.installed = _installed(localFile);
    repository.localResourceProfile = LocalResourceProfile.performance;

    repository.selection = const ModelSelection(
      kind: ModelProviderKind.local,
      modelId: 'local-story',
      displayName: 'Local Story',
    );
    expect(
        await model.listModels(const LanguageModelSettings()), ['local-story']);
    await expectLater(
        model
            .stream('hello', const LanguageModelSettings(),
                systemPrompt: 'system rules', jsonMode: true)
            .join(),
        completion('scene'));
    expect(runtime.model?.id, 'local-story');
    expect(runtime.resourceProfile, LocalResourceProfile.performance);
    expect(transport.lastSystemPrompt, 'system rules');
    expect(transport.lastJsonMode, isTrue);

    secrets.values['openai.api_key'] = 'key-value';
    repository.selection = const ModelSelection(
      kind: ModelProviderKind.openAi,
      modelId: 'gpt-test',
      displayName: 'gpt-test',
    );
    expect(await model.listModels(const LanguageModelSettings()),
        ['transport-model']);
    expect(transport.lastSettings?.baseUrl, 'https://api.openai.com/v1');
    expect(transport.lastApiKey, 'key-value');
    await model
        .stream('hello', const LanguageModelSettings(), jsonMode: true)
        .join();
    expect(transport.lastJsonMode, isTrue);

    repository.selection = const ModelSelection(
      kind: ModelProviderKind.custom,
      modelId: 'custom-story',
      displayName: 'Custom Story',
    );
    const LanguageModelSettings custom = LanguageModelSettings(
      baseUrl: 'https://example.test/v1',
      model: 'custom-story',
    );
    await model.listModels(custom, apiKey: 'session-only-key');
    expect(transport.lastSettings?.baseUrl, 'https://example.test/v1');
    expect(transport.lastApiKey, 'session-only-key');
    await model.stream('hello', custom, jsonMode: true).join();
    expect(transport.lastJsonMode, isTrue);

    secrets.values['gemini.api_key'] = 'gemini-key-value';
    repository.selection = const ModelSelection(
      kind: ModelProviderKind.gemini,
      modelId: 'gemini-test',
      displayName: 'gemini-test',
    );
    await model.listModels(const LanguageModelSettings());
    expect(transport.lastSettings?.baseUrl,
        'https://generativelanguage.googleapis.com/v1beta/openai');
    expect(transport.lastApiKey, 'gemini-key-value');
    await model.stream('hello', const LanguageModelSettings()).join();
    expect(transport.lastSettings?.model, 'gemini-test');
  });

  test('missing selection and missing local model return recovery guidance',
      () async {
    await expectLater(
      model.listModels(const LanguageModelSettings()),
      throwsA(isA<LlmException>().having((LlmException error) => error.message,
          'message', contains('Choose a story model'))),
    );
    repository.selection = const ModelSelection(
      kind: ModelProviderKind.local,
      modelId: 'missing',
      displayName: 'Missing',
    );
    await expectLater(
      model.healthCheck(const LanguageModelSettings()),
      throwsA(isA<LlmException>().having((LlmException error) => error.message,
          'message', contains('file is missing'))),
    );
  });
}

InstalledModel _installed(File file) => InstalledModel(
      id: 'local-story',
      displayName: 'Local Story',
      fileName: 'story.gguf',
      path: file.path,
      sizeBytes: 4,
      source: ModelSource.localImport,
      repository: 'Local import',
      license: 'Unknown',
      qualityClass: ModelQuality.balanced,
      speedClass: ModelSpeed.balanced,
      contextSize: 4096,
      sha256: null,
      importedAt: DateTime.utc(2026),
    );

class _Repository implements ModelManagerRepository {
  InstalledModel? installed;
  ModelSelection? selection;
  LocalResourceProfile localResourceProfile = LocalResourceProfile.balanced;
  @override
  Future<ModelSelection?> getSelection() async => selection;
  @override
  Future<List<InstalledModel>> listInstalled() async =>
      installed == null ? [] : [installed!];
  @override
  Future<void> removeInstalled(String modelId) async => installed = null;
  @override
  Future<void> saveInstalled(InstalledModel model) async => installed = model;
  @override
  Future<void> saveSelection(ModelSelection selection) async =>
      this.selection = selection;
  @override
  Future<void> clearSelection() async => selection = null;
  @override
  Future<LocalResourceProfile> getLocalResourceProfile() async =>
      localResourceProfile;
  @override
  Future<void> saveLocalResourceProfile(LocalResourceProfile profile) async =>
      localResourceProfile = profile;
}

class _Secrets implements SecretStore {
  final Map<String, String> values = {};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Runtime implements RuntimeManager {
  InstalledModel? model;
  LocalResourceProfile? resourceProfile;
  @override
  RuntimeSnapshot get snapshot =>
      const RuntimeSnapshot(status: RuntimeStatus.ready);
  @override
  Stream<RuntimeSnapshot> get changes => const Stream.empty();
  @override
  Future<Uri> ensureReady(InstalledModel value,
      {LocalResourceProfile resourceProfile =
          LocalResourceProfile.balanced}) async {
    model = value;
    this.resourceProfile = resourceProfile;
    return Uri.parse('http://127.0.0.1:1234/v1');
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _Transport extends OpenAiCompatibleProvider {
  LanguageModelSettings? lastSettings;
  String? lastApiKey;
  String? lastSystemPrompt;
  bool? lastJsonMode;
  @override
  Future<List<String>> listModels(LanguageModelSettings settings,
      {String? apiKey}) async {
    lastSettings = settings;
    lastApiKey = apiKey;
    return ['transport-model'];
  }

  @override
  Stream<String> stream(String prompt, LanguageModelSettings settings,
      {String? apiKey,
      int? maxTokens,
      String? systemPrompt,
      bool jsonMode = false}) async* {
    lastSettings = settings;
    lastApiKey = apiKey;
    lastSystemPrompt = systemPrompt;
    lastJsonMode = jsonMode;
    yield 'scene';
  }

  @override
  Future<void> healthCheck(LanguageModelSettings settings,
      {String? apiKey}) async {
    lastSettings = settings;
    lastApiKey = apiKey;
  }
}
