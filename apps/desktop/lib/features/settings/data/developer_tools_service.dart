import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/app_file_logger.dart';
import '../../../core/app_paths.dart';
import 'database_snapshot.dart';

/// Implements local-only diagnostics and maintenance outside presentation code.
class DeveloperToolsService {
  DeveloperToolsService(
      {required AppPaths paths, required AppFileLogger logger})
      : _paths = paths,
        _logger = logger;

  final AppPaths _paths;
  final AppFileLogger _logger;

  Future<DatabaseSnapshot> readDatabaseSnapshot() async {
    final DatabaseSnapshot snapshot =
        await _withDatabase((Database database) async {
      Future<int> countRows(String table) async {
        final List<Map<String, Object?>> rows =
            await database.rawQuery('SELECT COUNT(*) FROM $table');
        return rows.single.values.single as int;
      }

      final int fileSize = await _paths.databaseFile.exists()
          ? await _paths.databaseFile.length()
          : 0;
      return DatabaseSnapshot(
        databasePath: _paths.databaseFile.absolute.path,
        databaseSizeBytes: fileSize,
        schemaVersion: await database.getVersion(),
        worldCount: await countRows('worlds'),
        characterCount: await countRows('characters'),
        loreCount: await countRows('lore_entries'),
        locationCount: await countRows('locations'),
      );
    });
    return snapshot;
  }

  Future<bool> runIntegrityCheck() async {
    try {
      final List<Map<String, Object?>> results = await _withDatabase(
          (Database database) => database.rawQuery('PRAGMA integrity_check'));
      final List<String> messages = results
          .map((Map<String, Object?> row) => row.values.first.toString())
          .toList();
      final bool passed = messages.length == 1 && messages.single == 'ok';
      if (passed) {
        await _logger.info('SQLite integrity check passed.');
      } else {
        await _logger
            .warning('SQLite integrity check failed: ${messages.join('; ')}');
      }
      return passed;
    } catch (error, stackTrace) {
      await _logger.error('SQLite integrity check failed', error, stackTrace);
      rethrow;
    }
  }

  Future<File> createDatabaseBackup() async {
    try {
      await _paths.backupDirectory.create(recursive: true);
      final String stamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('-', '')
          .replaceAll('.', '');
      final File backup =
          File(path.join(_paths.backupDirectory.path, 'continuum-$stamp.db'));
      final String escapedPath = backup.absolute.path.replaceAll("'", "''");
      await _withDatabase((Database database) async {
        await database.execute("VACUUM INTO '$escapedPath'");
      });
      await _logger.info('SQLite backup created at ${backup.absolute.path}.');
      return backup;
    } catch (error, stackTrace) {
      await _logger.error('SQLite backup failed', error, stackTrace);
      rethrow;
    }
  }

  Future<void> resetDevelopmentData() async {
    try {
      await _withDatabase((Database database) async {
        await database.transaction((Transaction transaction) async {
          await transaction.delete('worlds');
        });
      });
      await _logger.warning('Local development Worlds were reset.');
    } catch (error, stackTrace) {
      await _logger.error('Development data reset failed', error, stackTrace);
      rethrow;
    }
  }

  Future<T> _withDatabase<T>(Future<T> Function(Database) operation) async {
    sqfliteFfiInit();
    final Database database = await databaseFactoryFfi.openDatabase(
      _paths.databaseFile.absolute.path,
      options: OpenDatabaseOptions(
        readOnly: false,
        singleInstance: false,
        onConfigure: (Database database) async =>
            database.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    try {
      return await operation(database);
    } finally {
      await database.close();
    }
  }
}
