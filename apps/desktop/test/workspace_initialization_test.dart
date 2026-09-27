import 'dart:io';

import 'package:continuum_desktop/core/app_file_logger.dart';
import 'package:continuum_desktop/core/app_paths.dart';
import 'package:continuum_desktop/core/developer_tools_providers.dart';
import 'package:continuum_desktop/features/world/data/sqlite_world_repository.dart';
import 'package:continuum_desktop/features/library/application/sample_world_factory.dart';
import 'package:continuum_desktop/features/library/domain/first_run_world_repository.dart';
import 'package:continuum_desktop/state/workspace_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initializes the repository and loads the workspace from isolated paths',
      () async {
    final Directory temporaryDirectory =
        await Directory.systemTemp.createTemp('continuum-workspace-');
    final AppPaths paths = AppPaths(dataDirectory: temporaryDirectory);
    final AppFileLogger logger = AppFileLogger(paths.logDirectory);
    final ProviderContainer container = ProviderContainer(overrides: <Override>[
      appPathsProvider.overrideWithValue(paths),
      appFileLoggerProvider.overrideWithValue(logger),
    ]);
    addTearDown(() async {
      final repository = container.read(worldRepositoryProvider);
      if (repository case final SqliteWorldRepository sqliteRepository) {
        await sqliteRepository.close();
      }
      container.dispose();
      await temporaryDirectory.delete(recursive: true);
    });

    await container.read(workspaceProvider.notifier).initialize();

    expect(container.read(workspaceProvider).loadStatus,
        WorkspaceLoadStatus.ready);
    final state = container.read(workspaceProvider);
    expect(state.worlds, hasLength(1));
    expect(state.worlds.single.name, '마지막 등대의 불빛');
    expect(state.worlds.single.playerDefinition.name, isNotEmpty);
    expect(state.worlds.single.openingDefinition.startingLocationId, isNotNull);
    expect(state.worlds.single.characters, hasLength(1));
    expect(state.worlds.single.locations, hasLength(1));
    await (container.read(worldRepositoryProvider) as FirstRunWorldRepository)
        .seedDefaultWorldIfFirstRun(SampleWorldFactory.create());
    expect((await container.read(worldRepositoryProvider).listWorlds()),
        hasLength(1));
    await container.read(workspaceProvider.notifier).initialize();
    expect(container.read(workspaceProvider).worlds, hasLength(1));
    expect(await paths.databaseFile.exists(), isTrue);
    expect(await logger.currentLogFile.exists(), isTrue);
  });
}
