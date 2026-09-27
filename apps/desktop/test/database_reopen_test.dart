import 'dart:io';

import 'package:continuum_desktop/core/app_paths.dart';
import 'package:continuum_desktop/features/world/data/sqlite_world_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('a World remains readable after closing and reopening the database',
      () async {
    final Directory temporaryDirectory =
        await Directory.systemTemp.createTemp('continuum-reopen-');
    final AppPaths paths = AppPaths(dataDirectory: temporaryDirectory);
    await paths.initialize();
    SqliteWorldRepository repository =
        await SqliteWorldRepository.open(paths.databaseFile.path);
    addTearDown(() async {
      await repository.close();
      await temporaryDirectory.delete(recursive: true);
    });

    await repository.createWorld(const World(
      id: 'reopen-world',
      name: 'Reopen World',
      description: 'Persistent fixture',
      genre: <String>['Mystery'],
      tone: <String>['Quiet'],
    ));
    await repository.close();
    repository = await SqliteWorldRepository.open(paths.databaseFile.path);

    final World? restored = await repository.getWorld('reopen-world');
    expect(restored?.name, 'Reopen World');
    expect(restored?.genre, <String>['Mystery']);
    expect(restored?.tone, <String>['Quiet']);
  });
}
