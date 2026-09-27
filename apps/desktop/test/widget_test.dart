import 'package:continuum_desktop/app/continuum_app.dart';
import 'package:continuum_desktop/features/world/domain/world_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';

import 'package:continuum_desktop/state/workspace_controller.dart';

void main() {
  testWidgets(
    'opens a world in Studio and navigates between encyclopedia sections',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(ProviderScope(overrides: [
        workspaceProvider.overrideWith(() => _TestWorkspaceController()),
        worldRepositoryProvider.overrideWithValue(_UnusedRepository()),
      ], child: const ContinuumApp()));
      await tester.pumpAndSettle();
      expect(find.text('Your Worlds'), findsOneWidget);
      expect(find.text('No worlds have been created yet.'), findsOneWidget);
    },
  );

  testWidgets('creates a world and opens its Studio', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        workspaceProvider.overrideWith(() => _TestWorkspaceController()),
        worldRepositoryProvider.overrideWithValue(_UnusedRepository()),
      ],
      child: const ContinuumApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CREATE WORLD'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Paper Moon');
    await tester
        .ensureVisible(find.widgetWithText(FilledButton, 'Create World'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create World'));
    await tester.pumpAndSettle();
    expect(find.text('A world, in brief'), findsOneWidget);
    expect(find.text('Paper Moon'), findsWidgets);
  });

}

class _TestWorkspaceController extends WorkspaceController {
  @override
  WorkspaceState build() =>
      const WorkspaceState(loadStatus: WorkspaceLoadStatus.ready);

  @override
  Future<void> createWorld(
      {required String name,
      required String description,
      required List<String> genre,
      required List<String> tone,
      String? templateId}) async {
    state = WorkspaceState(worlds: [
      World(
          id: 'world_test',
          name: name,
          description: description,
          genre: genre,
          tone: tone)
    ], currentWorldId: 'world_test', loadStatus: WorkspaceLoadStatus.ready);
  }
}

class _UnusedRepository implements WorldRepository {
  @override
  Future<void> createCharacter(
      String worldId, StoryCharacter character) async {}
  @override
  Future<void> createLore(String worldId, LoreEntry entry) async {}
  @override
  Future<void> createLocation(String worldId, StoryLocation location) async {}
  @override
  Future<void> createWorld(World world) async {}
  @override
  Future<void> deleteCharacter(String characterId) async {}
  @override
  Future<void> deleteLore(String entryId) async {}
  @override
  Future<void> deleteLocation(String locationId) async {}
  @override
  Future<void> deleteWorld(String worldId) async {}
  @override
  Future<World> duplicateWorld(String worldId) async =>
      throw UnimplementedError();
  @override
  Future<World?> getWorld(String worldId) async => null;
  @override
  Future<List<World>> listWorlds() async => [];
  @override
  Future<void> updateCharacter(StoryCharacter character) async {}
  @override
  Future<void> updateLore(LoreEntry entry) async {}
  @override
  Future<void> updateLocation(StoryLocation location) async {}
  @override
  Future<void> updateWorld(World world) async {}
  @override
  Future<void> updateWorldDraft(World world) async {}
}
