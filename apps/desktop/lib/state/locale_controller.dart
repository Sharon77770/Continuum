import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/developer_tools_providers.dart';
import '../features/settings/data/language_preferences_repository.dart';

final languagePreferencesRepositoryProvider =
    Provider<LanguagePreferencesRepository>(
  (ref) => LanguagePreferencesRepository(
    ref.watch(appPathsProvider).dataDirectory,
  ),
);

/// Owns the UI language selected for this desktop application installation.
final localeProvider = NotifierProvider<LocaleController, Locale>(
  LocaleController.new,
);

/// Language used for generated story content in newly created Campaigns.
final gameLanguageProvider = NotifierProvider<GameLanguageController, String>(
  GameLanguageController.new,
);

class GameLanguageController extends Notifier<String> {
  @override
  String build() => 'en';

  Future<void> setLanguage(String languageCode) async {
    const Set<String> supportedLanguages = {'ko', 'en', 'zh', 'ja'};
    if (!supportedLanguages.contains(languageCode)) return;
    await ref
        .read(languagePreferencesRepositoryProvider)
        .saveGameLanguage(languageCode);
    state = languageCode;
  }

  void restoreLanguage(String languageCode) {
    const Set<String> supportedLanguages = {'ko', 'en', 'zh', 'ja'};
    if (supportedLanguages.contains(languageCode)) state = languageCode;
  }
}

class LocaleController extends Notifier<Locale> {
  @override
  Locale build() => const Locale('en');

  /// Changes the UI language to one of the languages shipped by the app.
  Future<void> setLanguage(Locale locale) async {
    const Set<String> supportedLanguages = {'ko', 'en', 'zh', 'ja'};
    if (!supportedLanguages.contains(locale.languageCode)) return;
    await ref
        .read(languagePreferencesRepositoryProvider)
        .saveUiLanguage(locale.languageCode);
    state = locale.languageCode == 'zh'
        ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')
        : Locale(locale.languageCode);
  }

  void restoreLanguage(Locale locale) {
    const Set<String> supportedLanguages = {'ko', 'en', 'zh', 'ja'};
    if (supportedLanguages.contains(locale.languageCode)) {
      state = locale.languageCode == 'zh'
          ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')
          : Locale(locale.languageCode);
    }
  }
}
