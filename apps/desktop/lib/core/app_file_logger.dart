import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Writes bounded, content-safe application events to a persistent log file.
class AppFileLogger {
  AppFileLogger(this._logDirectory);

  static const int _maximumFileBytes = 1024 * 1024;
  final Directory _logDirectory;
  Future<void> _writeQueue = Future<void>.value();

  File get currentLogFile =>
      File(path.join(_logDirectory.path, 'continuum.log'));

  Future<void> initialize() async {
    await _logDirectory.create(recursive: true);
    await info('Application file logging initialized.');
  }

  Future<void> debug(String message) =>
      kDebugMode ? _write('DEBUG', message) : Future<void>.value();
  Future<void> info(String message) => _write('INFO', message);
  Future<void> warning(String message) => _write('WARN', message);

  Future<void> error(String message, Object error, StackTrace stackTrace) =>
      _write('ERROR', '$message (errorType=${error.runtimeType})\n$stackTrace');

  Future<void> _write(String level, String message) {
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _logDirectory.create(recursive: true);
        final File activeFile = currentLogFile;
        if (await activeFile.exists() &&
            await activeFile.length() >= _maximumFileBytes) {
          final File previousFile = File('${activeFile.path}.1');
          if (await previousFile.exists()) await previousFile.delete();
          await activeFile.rename(previousFile.path);
        }
        final String timestamp = DateTime.now().toUtc().toIso8601String();
        await activeFile.writeAsString(
          '[$timestamp] $level $message\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (writeError) {
        debugPrint('Could not write Continuum log: $writeError');
      }
    });
    return _writeQueue;
  }
}
