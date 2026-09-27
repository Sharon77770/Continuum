import 'dart:io';

import 'package:continuum_desktop/core/app_file_logger.dart';
import 'package:continuum_desktop/core/app_paths.dart';
import 'package:continuum_desktop/features/settings/data/developer_tools_service.dart';
import 'package:continuum_desktop/features/world/data/sqlite_world_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
      'reports database, creates a usable backup, checks and safely resets data',
      () async {
    final Directory temporaryDirectory =
        await Directory.systemTemp.createTemp('continuum-devtools-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final AppPaths paths = AppPaths(dataDirectory: temporaryDirectory);
    await paths.initialize();
    final AppFileLogger logger = AppFileLogger(paths.logDirectory);
    final SqliteWorldRepository repository =
        await SqliteWorldRepository.open(paths.databaseFile.path);
    addTearDown(repository.close);
    await repository.createWorld(const World(
      id: 'test-world',
      name: 'Test World',
      description: 'Temporary fixture',
      genre: <String>[],
      tone: <String>[],
    ));
    final DeveloperToolsService service =
        DeveloperToolsService(paths: paths, logger: logger);

    final snapshot = await service.readDatabaseSnapshot();
    expect(snapshot.databasePath, paths.databaseFile.absolute.path);
    expect(snapshot.schemaVersion, 3);
    expect(snapshot.worldCount, 1);
    expect(await service.runIntegrityCheck(), isTrue);

    final File backup = await service.createDatabaseBackup();
    expect(await backup.exists(), isTrue);
    final Database backupDatabase =
        await databaseFactoryFfi.openDatabase(backup.path);
    expect(
      (await backupDatabase.rawQuery('SELECT COUNT(*) FROM worlds'))
          .single
          .values
          .single,
      1,
    );
    await backupDatabase.close();

    await service.resetDevelopmentData();
    expect(await repository.listWorlds(), isEmpty);
    expect((await service.readDatabaseSnapshot()).worldCount, 0);
    expect(await service.runIntegrityCheck(), isTrue);
  });
}
