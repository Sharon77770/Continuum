/// Non-secret preferences for an OpenAI-compatible language-model endpoint.
class LanguageModelSettings {
  const LanguageModelSettings({
    this.baseUrl = 'http://localhost:11434/v1',
    this.model = '',
    this.temperature = 0.8,
    this.contextLimit = 4096,
  });

  final String baseUrl;
  final String model;
  final double temperature;
  final int contextLimit;
}

/// Persistence boundary for non-secret language-model preferences.
abstract interface class LanguageModelSettingsRepository {
  Future<void> saveLanguageModelSettings(LanguageModelSettings settings);
  Future<LanguageModelSettings> getLanguageModelSettings();
}
