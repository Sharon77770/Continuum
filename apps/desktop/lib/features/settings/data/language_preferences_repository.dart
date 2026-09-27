import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Stores the app-wide UI and default story languages in user data.
class LanguagePreferencesRepository {
  LanguagePreferencesRepository(this.dataDirectory);

  final Directory dataDirectory;
  Future<void> _pendingWrite = Future<void>.value();

  File get _file =>
      File(path.join(dataDirectory.path, 'language_preferences.json'));

  Future<Map<String, String>> load() async {
    if (!await _file.exists()) {
      return <String, String>{'uiLanguage': 'en', 'gameLanguage': 'en'};
    }
    try {
      final Map<String, dynamic> json =
          jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      return <String, String>{
        'uiLanguage': json['uiLanguage'] as String? ?? 'en',
        'gameLanguage': json['gameLanguage'] as String? ?? 'en',
      };
    } on FormatException {
      return <String, String>{'uiLanguage': 'en', 'gameLanguage': 'en'};
    } on TypeError {
      return <String, String>{'uiLanguage': 'en', 'gameLanguage': 'en'};
    }
  }

  Future<void> saveUiLanguage(String languageCode) async {
    await _update('uiLanguage', languageCode);
  }

  Future<void> saveGameLanguage(String languageCode) async {
    await _update('gameLanguage', languageCode);
  }

  Future<void> _update(String key, String languageCode) {
    final Future<void> write = _pendingWrite.then((_) async {
      final Map<String, String> current = await load();
      current[key] = languageCode;
      await _save(current);
    });
    _pendingWrite = write.catchError((Object _) {});
    return write;
  }

  Future<void> _save(Map<String, String> languages) async {
    await dataDirectory.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(languages),
      flush: true,
    );
  }
}
