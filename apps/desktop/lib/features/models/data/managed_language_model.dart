import '../../novel/data/llm_provider.dart';
import '../../novel/domain/language_model_settings.dart';
import '../domain/model_catalog.dart';
import '../domain/model_manager_repository.dart';
import '../domain/runtime_manager.dart';

/// Presents local, cloud and advanced custom models as one Novel transport.
class ManagedLanguageModel implements LlmProvider {
  ManagedLanguageModel({
    required ModelManagerRepository modelRepository,
    required SecretStore secrets,
    required RuntimeManager runtime,
    OpenAiCompatibleProvider? transport,
  })  : _models = modelRepository,
        _secrets = secrets,
        _runtime = runtime,
        _transport = transport ?? OpenAiCompatibleProvider();

  final ModelManagerRepository _models;
  final SecretStore _secrets;
  final RuntimeManager _runtime;
  final OpenAiCompatibleProvider _transport;

  @override
  Future<List<String>> listModels(LanguageModelSettings settings,
      {String? apiKey}) async {
    final ModelSelection selection = await _requireSelection();
    switch (selection.kind) {
      case ModelProviderKind.local:
        return <String>[selection.modelId];
      case ModelProviderKind.openAi:
        final String key = await _cloudKey();
        return _transport.listModels(_cloudSettings(selection.modelId),
            apiKey: key);
      case ModelProviderKind.gemini:
        final String key = await _providerKey('gemini.api_key', 'Gemini');
        return _transport.listModels(_geminiSettings(selection.modelId),
            apiKey: key);
      case ModelProviderKind.custom:
        return _transport.listModels(settings, apiKey: apiKey);
    }
  }

  @override
  Stream<String> stream(String prompt, LanguageModelSettings settings,
      {String? apiKey,
      int? maxTokens,
      String? systemPrompt,
      bool jsonMode = false}) async* {
    final ModelSelection selection = await _requireSelection();
    switch (selection.kind) {
      case ModelProviderKind.local:
        final InstalledModel model = await _installed(selection.modelId);
        final Uri endpoint = await _runtime.ensureReady(model,
            resourceProfile: await _models.getLocalResourceProfile());
        yield* _transport.stream(
          prompt,
          LanguageModelSettings(
            baseUrl: endpoint.toString(),
            model: selection.modelId,
            temperature: settings.temperature,
            contextLimit: settings.contextLimit,
          ),
          maxTokens: maxTokens,
          systemPrompt: systemPrompt,
          jsonMode: jsonMode,
        );
        return;
      case ModelProviderKind.openAi:
        final String key = await _cloudKey();
        yield* _transport.stream(
          prompt,
          _cloudSettings(selection.modelId, preferences: settings),
          apiKey: key,
          maxTokens: maxTokens,
          systemPrompt: systemPrompt,
          jsonMode: jsonMode,
        );
        return;
      case ModelProviderKind.gemini:
        final String key = await _providerKey('gemini.api_key', 'Gemini');
        yield* _transport.stream(
          prompt,
          _geminiSettings(selection.modelId, preferences: settings),
          apiKey: key,
          maxTokens: maxTokens,
          systemPrompt: systemPrompt,
          jsonMode: jsonMode,
        );
        return;
      case ModelProviderKind.custom:
        yield* _transport.stream(prompt, settings,
            apiKey: apiKey,
            maxTokens: maxTokens,
            systemPrompt: systemPrompt,
            jsonMode: jsonMode);
        return;
    }
  }

  @override
  Future<void> healthCheck(LanguageModelSettings settings,
      {String? apiKey}) async {
    final ModelSelection selection = await _requireSelection();
    switch (selection.kind) {
      case ModelProviderKind.local:
        final InstalledModel model = await _installed(selection.modelId);
        await _runtime.ensureReady(model,
            resourceProfile: await _models.getLocalResourceProfile());
        return;
      case ModelProviderKind.openAi:
        final String key = await _cloudKey();
        await _transport.healthCheck(_cloudSettings(selection.modelId),
            apiKey: key);
        return;
      case ModelProviderKind.gemini:
        final String key = await _providerKey('gemini.api_key', 'Gemini');
        await _transport.healthCheck(_geminiSettings(selection.modelId),
            apiKey: key);
        return;
      case ModelProviderKind.custom:
        await _transport.healthCheck(settings, apiKey: apiKey);
        return;
    }
  }

  Future<ModelSelection> _requireSelection() async {
    final ModelSelection? selection = await _models.getSelection();
    if (selection == null) {
      throw const LlmException(
          'Choose a story model in Models before you play.');
    }
    return selection;
  }

  Future<InstalledModel> _installed(String id) async {
    final InstalledModel? model = (await _models.listInstalled())
        .where((InstalledModel value) => value.id == id)
        .firstOrNull;
    if (model == null) {
      throw const LlmException(
          'This model file is missing. Open Models to download or import it again.');
    }
    return model;
  }

  Future<String> _cloudKey() async =>
      await _secrets.read('openai.api_key') ??
      (throw const LlmException('Reconnect OpenAI in Models to continue.'));

  Future<String> _providerKey(String keyName, String provider) async =>
      await _secrets.read(keyName) ??
      (throw LlmException('Reconnect $provider in Models to continue.'));

  LanguageModelSettings _cloudSettings(String modelId,
          {LanguageModelSettings? preferences}) =>
      LanguageModelSettings(
        baseUrl: 'https://api.openai.com/v1',
        model: modelId,
        temperature: preferences?.temperature ?? .8,
        contextLimit: preferences?.contextLimit ?? 8192,
      );

  LanguageModelSettings _geminiSettings(String modelId,
          {LanguageModelSettings? preferences}) =>
      LanguageModelSettings(
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
        model: modelId,
        temperature: preferences?.temperature ?? .8,
        contextLimit: preferences?.contextLimit ?? 8192,
      );

  @override
  void cancelCurrentRequest() => _transport.cancelCurrentRequest();

  void close() => _transport.close();
}
