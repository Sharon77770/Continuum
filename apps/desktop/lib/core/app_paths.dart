import 'dart:io';

import 'package:path/path.dart' as path;

/// Resolves Continuum's user-scoped filesystem locations in one place.
class AppPaths {
  AppPaths({required this.dataDirectory});

  factory AppPaths.resolve({
    required String operatingSystem,
    required Map<String, String> environment,
    required String homeDirectory,
    required String buildMode,
  }) {
    final String applicationDirectory =
        buildMode.toLowerCase() == 'debug' ? 'Continuum-Dev' : 'Continuum';
    final String root = switch (operatingSystem) {
      'windows' =>
        environment['APPDATA'] ?? environment['LOCALAPPDATA'] ?? homeDirectory,
      'macos' => path.join(homeDirectory, 'Library', 'Application Support'),
      _ => environment['XDG_DATA_HOME'] ??
          path.join(homeDirectory, '.local', 'share'),
    };
    return AppPaths(
        dataDirectory: Directory(path.join(root, applicationDirectory)));
  }

  /// User-scoped root; Debug uses an isolated directory for destructive tools.
  final Directory dataDirectory;

  Directory get databaseDirectory => dataDirectory;
  File get databaseFile =>
      File(path.join(dataDirectory.path, 'continuum.sqlite3'));
  Directory get logDirectory =>
      Directory(path.join(dataDirectory.path, 'logs'));
  Directory get backupDirectory =>
      Directory(path.join(dataDirectory.path, 'backups'));
  Directory get modelsDirectory =>
      Directory(path.join(dataDirectory.path, 'models'));
  Directory get runtimeDirectory =>
      Directory(path.join(dataDirectory.path, 'runtime', 'llama.cpp'));
  Directory get runtimeLogDirectory =>
      Directory(path.join(logDirectory.path, 'runtime'));
  Directory get tempDirectory =>
      Directory(path.join(dataDirectory.path, 'temp'));

  Future<void> initialize() async {
    await Future.wait(<Future<void>>[
      dataDirectory.create(recursive: true),
      logDirectory.create(recursive: true),
      backupDirectory.create(recursive: true),
      modelsDirectory.create(recursive: true),
      runtimeDirectory.create(recursive: true),
      runtimeLogDirectory.create(recursive: true),
      tempDirectory.create(recursive: true),
    ]);
  }
}
