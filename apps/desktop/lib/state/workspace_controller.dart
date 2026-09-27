import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:game_core/game_core.dart';

import '../core/app_file_logger.dart';
import '../core/app_paths.dart';
import '../core/developer_tools_providers.dart';
import '../core/runtime_environment.dart';
import '../features/library/application/sample_world_factory.dart';
import '../features/library/application/scenario_template_catalog.dart';
import '../features/library/data/json_scenario_file_repository.dart';
import '../features/library/domain/first_run_world_repository.dart';
import '../features/novel/domain/campaign_repository.dart';
import '../features/novel/domain/language_model_settings.dart';
import '../features/world/data/sqlite_world_repository.dart';
import '../features/world/domain/world_repository.dart';

enum WorkspaceLoadStatus { loading, ready, failed }

enum AutosaveStatus { idle, saving, saved, failed }

final worldRepositoryProvider = Provider<WorldRepository>((ref) {
  final WorldRepository? repository = ref.watch(_repositoryHolderProvider);
  if (repository == null) {
    throw StateError('Repository is not ready.');
  }
  return repository;
});

final campaignRepositoryProvider = Provider<CampaignRepository>((ref) {
  final WorldRepository repository = ref.watch(worldRepositoryProvider);
  if (repository is! CampaignRepository) {
    throw StateError('Campaign storage is not ready.');
  }
  return repository as CampaignRepository;
});

final languageModelSettingsRepositoryProvider =
    Provider<LanguageModelSettingsRepository>((ref) {
  final WorldRepository repository = ref.watch(worldRepositoryProvider);
  if (repository is! LanguageModelSettingsRepository) {
    throw StateError('Language model settings storage is not ready.');
  }
  return repository as LanguageModelSettingsRepository;
});

final workspaceProvider = NotifierProvider<WorkspaceController, WorkspaceState>(
    WorkspaceController.new);

class WorkspaceState {
  const WorkspaceState(
      {this.worlds = const [],
      this.campaigns = const [],
      this.currentWorldId,
      this.loadStatus = WorkspaceLoadStatus.loading,
      this.autosaveStatus = AutosaveStatus.idle,
      this.errorMessage});
  final List<World> worlds;
  final List<Campaign> campaigns;
  final String? currentWorldId;
  final WorkspaceLoadStatus loadStatus;
  final AutosaveStatus autosaveStatus;
  final String? errorMessage;
  World? get currentWorld =>
      worlds.where((World world) => world.id == currentWorldId).firstOrNull;
  WorkspaceState copyWith(
          {List<World>? worlds,
          List<Campaign>? campaigns,
          String? currentWorldId,
          bool clearCurrentWorld = false,
          WorkspaceLoadStatus? loadStatus,
          AutosaveStatus? autosaveStatus,
          String? errorMessage,
          bool clearError = false}) =>
      WorkspaceState(
          worlds: worlds ?? this.worlds,
          campaigns: campaigns ?? this.campaigns,
          currentWorldId:
              clearCurrentWorld ? null : currentWorldId ?? this.currentWorldId,
          loadStatus: loadStatus ?? this.loadStatus,
          autosaveStatus: autosaveStatus ?? this.autosaveStatus,
          errorMessage: clearError ? null : errorMessage ?? this.errorMessage);
}

/// Coordinates persisted world state and debounced Studio autosave.
class WorkspaceController extends Notifier<WorkspaceState> {
  Timer? _saveTimer;
  Future<void> _saveQueue = Future<void>.value();
  bool _initialized = false;

  @override
  WorkspaceState build() {
    ref.onDispose(() {
      _saveTimer?.cancel();
    });
    return const WorkspaceState();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final AppPaths paths = ref.read(appPathsProvider);
      final AppFileLogger logger = ref.read(appFileLoggerProvider);
      await paths.initialize();
      await logger.initialize();
      final RuntimeEnvironmentInfo environment =
          ref.read(runtimeEnvironmentProvider);
      await logger.info(
          'Application startup version=${environment.appVersion} buildMode=${environment.buildMode} platform=${environment.platform}');
      await logger.info(
          'Resolved data directory: ${paths.dataDirectory.absolute.path}');
      await logger
          .info('Resolved database path: ${paths.databaseFile.absolute.path}');
      final WorldRepository repository =
          await SqliteWorldRepository.open(paths.databaseFile.absolute.path);
      ref.read(_repositoryHolderProvider.notifier).state = repository;
      final int schemaVersion =
          (await ref.read(developerToolsServiceProvider).readDatabaseSnapshot())
              .schemaVersion;
      await logger.info('SQLite database initialized; schema=$schemaVersion.');
      final FirstRunWorldRepository firstRunRepository =
          repository as FirstRunWorldRepository;
      await firstRunRepository
          .seedDefaultWorldIfFirstRun(SampleWorldFactory.create());
      final List<World> worlds = await repository.listWorlds();
      final List<Campaign> campaigns = [
        for (final World world in worlds)
          ...await (repository as CampaignRepository).listCampaigns(world.id),
      ];
      await logger.info('Loaded ${worlds.length} Worlds from local storage.');
      state = state.copyWith(
          worlds: worlds,
          campaigns: campaigns,
          loadStatus: WorkspaceLoadStatus.ready,
          clearError: true);
    } catch (error, stackTrace) {
      _initialized = false;
      _logFailure('initialize database', error, stackTrace);
      state = state.copyWith(
          loadStatus: WorkspaceLoadStatus.failed,
          errorMessage:
              'Could not open the local world database. Check the Windows application data folder and restart Continuum.');
    }
  }

  /// Reloads persistent Worlds after a developer maintenance operation.
  Future<void> reloadWorlds() async {
    final List<World> worlds = await _repository.listWorlds();
    final List<Campaign> campaigns = [
      for (final World world in worlds)
        ...await (_repository as CampaignRepository).listCampaigns(world.id),
    ];
    state = state.copyWith(
      worlds: worlds,
      campaigns: campaigns,
      clearCurrentWorld: true,
      autosaveStatus: AutosaveStatus.idle,
      clearError: true,
    );
  }

  Future<void> refreshCampaigns(String worldId) async {
    final List<Campaign> saved =
        await (_repository as CampaignRepository).listCampaigns(worldId);
    state = state.copyWith(campaigns: [
      ...state.campaigns
          .where((Campaign campaign) => campaign.worldId != worldId),
      ...saved,
    ]);
  }

  Future<void> createWorld(
      {required String name,
      required String description,
      required List<String> genre,
      required List<String> tone,
      String? templateId}) async {
    final String cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('World name is required.');
    if (state.loadStatus != WorkspaceLoadStatus.ready) {
      throw StateError(state.errorMessage ??
          'World storage is still starting. Please try again.');
    }
    final DateTime now = DateTime.now().toUtc();
    final ScenarioTemplate? template =
        templateId == null ? null : ScenarioTemplateCatalog.find(templateId);
    if (templateId != null && template == null) {
      throw ArgumentError.value(
          templateId, 'templateId', 'Unknown scenario template.');
    }
    final World world = template?.createWorld(
          nameOverride: cleanName,
          descriptionOverride: description,
          genreOverride: genre,
          toneOverride: tone,
        ) ??
        World(
            id: createStableId('world'),
            name: cleanName,
            description: description,
            genre: genre,
            tone: tone,
            createdAt: now,
            updatedAt: now);
    await _guard('create world', () async {
      await _repository.createWorld(world);
      state = state.copyWith(
          worlds: [world, ...state.worlds],
          currentWorldId: world.id,
          autosaveStatus: AutosaveStatus.saved,
          clearError: true);
    });
  }

  /// Imports a scenario as a new world with fresh identifiers for all content.
  Future<World?> importScenario() async {
    if (state.loadStatus != WorkspaceLoadStatus.ready) {
      throw StateError('World storage is not ready.');
    }
    final World? imported =
        await ref.read(scenarioFileRepositoryProvider).importScenario();
    if (imported == null) return null;
    final World world = _copyImportedScenario(imported);
    await _guard('import scenario', () async {
      await _repository.createWorld(world);
      state = state.copyWith(
        worlds: [world, ...state.worlds],
        autosaveStatus: AutosaveStatus.saved,
        clearError: true,
      );
    });
    return world;
  }

  /// Exports the latest saved draft of a world to a JSON scenario file.
  Future<bool> exportScenario(String worldId) async {
    await flushPendingChanges();
    final World? world =
        state.worlds.where((World item) => item.id == worldId).firstOrNull;
    if (world == null) throw StateError('The selected world no longer exists.');
    return ref.read(scenarioFileRepositoryProvider).exportScenario(world);
  }

  World _copyImportedScenario(World source) {
    final DateTime now = DateTime.now().toUtc();
    final String worldId = createStableId('world');
    final Map<String, String> characterIds = {
      for (final StoryCharacter item in source.characters)
        item.id: createStableId('char'),
    };
    final Map<String, String> locationIds = {
      for (final StoryLocation item in source.locations)
        item.id: createStableId('loc'),
    };
    return World(
      id: worldId,
      name: source.name,
      description: source.description,
      genre: List<String>.of(source.genre),
      tone: List<String>.of(source.tone),
      rules: List<String>.of(source.rules),
      loreEntries: [
        for (final LoreEntry item in source.loreEntries)
          LoreEntry(
            id: createStableId('lore'),
            worldId: worldId,
            title: item.title,
            category: item.category,
            content: item.content,
            createdAt: now,
            updatedAt: now,
          ),
      ],
      characters: [
        for (final StoryCharacter item in source.characters)
          StoryCharacter(
            id: characterIds[item.id]!,
            worldId: worldId,
            name: item.name,
            role: item.role,
            description: item.description,
            appearance: item.appearance,
            personality: item.personality,
            background: item.background,
            publicInformation: item.publicInformation,
            secretInformation: item.secretInformation,
            createdAt: now,
            updatedAt: now,
          ),
      ],
      locations: [
        for (final StoryLocation item in source.locations)
          StoryLocation(
            id: locationIds[item.id]!,
            worldId: worldId,
            name: item.name,
            description: item.description,
            parentId: item.parentId == null ? null : locationIds[item.parentId],
            createdAt: now,
            updatedAt: now,
          ),
      ],
      playerDefinition: PlayerDefinition(
        name: source.playerDefinition.name,
        description: source.playerDefinition.description,
        background: source.playerDefinition.background,
        traits: List<String>.of(source.playerDefinition.traits),
      ),
      openingDefinition: OpeningDefinition(
        startingLocationId: source.openingDefinition.startingLocationId == null
            ? null
            : locationIds[source.openingDefinition.startingLocationId],
        startingCharacterIds: [
          for (final String id in source.openingDefinition.startingCharacterIds)
            characterIds[id]!,
        ],
        situation: source.openingDefinition.situation,
      ),
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> openWorld(String worldId) async {
    await flushPendingChanges();
    state = state.copyWith(
        currentWorldId: worldId, autosaveStatus: AutosaveStatus.idle);
  }

  void updateCurrentWorld(World updatedWorld) {
    final World? previous = _pendingWorlds[updatedWorld.id] ??
        state.worlds
            .where((World world) => world.id == updatedWorld.id)
            .firstOrNull;
    if (previous == null) {
      return;
    }
    _pendingWorlds.putIfAbsent(updatedWorld.id, () => previous);
    state = state.copyWith(worlds: [
      for (final World world in state.worlds)
        world.id == updatedWorld.id ? updatedWorld : world
    ], autosaveStatus: AutosaveStatus.saving, clearError: true);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 650),
        () => unawaited(_persistPendingWorld(updatedWorld.id)));
  }

  final Map<String, World> _pendingWorlds = {};

  Future<void> _persistPendingWorld(String worldId) async {
    final World? previous = _pendingWorlds.remove(worldId);
    final World? updated =
        state.worlds.where((World world) => world.id == worldId).firstOrNull;
    if (previous == null || updated == null) {
      return;
    }
    bool failed = false;
    await _enqueueSave(() => _repository.updateWorldDraft(updated), updated.id,
        markComplete: false, onFailure: () => failed = true);
    if (!failed &&
        state.currentWorldId == updated.id &&
        state.autosaveStatus != AutosaveStatus.failed) {
      state = state.copyWith(
          autosaveStatus: AutosaveStatus.saved, clearError: true);
    }
  }

  Future<void> _enqueueSave(Future<void> Function() save, String worldId,
      {bool markComplete = true, VoidCallback? onFailure}) async {
    final Completer<void> completion = Completer<void>();
    _saveQueue = _saveQueue.then((_) async {
      try {
        await save();
        unawaited(ref
            .read(appFileLoggerProvider)
            .info('Persistence operation completed: autosave world $worldId.'));
      } catch (error, stackTrace) {
        onFailure?.call();
        _logFailure('autosave world $worldId', error, stackTrace);
        if (state.currentWorldId == worldId) {
          state = state.copyWith(
              autosaveStatus: AutosaveStatus.failed,
              errorMessage:
                  'Changes could not be saved. Your edits remain on screen; edit again to retry.');
        }
      } finally {
        completion.complete();
      }
    });
    await completion.future;
    if (markComplete &&
        state.currentWorldId == worldId &&
        state.autosaveStatus != AutosaveStatus.failed) {
      state = state.copyWith(
          autosaveStatus: AutosaveStatus.saved, clearError: true);
    }
  }

  Future<void> flushPendingChanges() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final List<String> worldIds = _pendingWorlds.keys.toList();
    for (final String worldId in worldIds) {
      await _persistPendingWorld(worldId);
    }
    await _saveQueue;
  }

  Future<void> deleteWorld(String worldId) async {
    await flushPendingChanges();
    await _guard('delete world', () async {
      await _repository.deleteWorld(worldId);
      final List<World> worlds =
          state.worlds.where((World item) => item.id != worldId).toList();
      state = state.copyWith(
          worlds: worlds,
          clearCurrentWorld: state.currentWorldId == worldId,
          autosaveStatus: AutosaveStatus.saved,
          clearError: true);
    });
  }

  Future<void> duplicateWorld(String worldId) async =>
      _guard('duplicate world', () async {
        final World copy = await _repository.duplicateWorld(worldId);
        state = state.copyWith(
            worlds: [copy, ...state.worlds],
            currentWorldId: copy.id,
            autosaveStatus: AutosaveStatus.saved,
            clearError: true);
      });

  Future<void> createLore(String worldId, LoreEntry entry) async =>
      _mutateWorld(
          worldId,
          (World world) =>
              world.copyWith(loreEntries: [...world.loreEntries, entry]),
          () => _repository.createLore(worldId, entry));
  Future<void> updateLore(LoreEntry entry) async => _mutateWorld(
      entry.worldId,
      (World world) => world.copyWith(loreEntries: [
            for (final LoreEntry item in world.loreEntries)
              item.id == entry.id ? entry : item
          ]),
      () => _repository.updateLore(entry));
  Future<void> deleteLore(String worldId, String entryId) async => _mutateWorld(
      worldId,
      (World world) => world.copyWith(
          loreEntries: world.loreEntries
              .where((LoreEntry item) => item.id != entryId)
              .toList()),
      () => _repository.deleteLore(entryId));
  Future<void> createCharacter(
          String worldId, StoryCharacter character) async =>
      _mutateWorld(
          worldId,
          (World world) =>
              world.copyWith(characters: [...world.characters, character]),
          () => _repository.createCharacter(worldId, character));
  Future<void> updateCharacter(StoryCharacter character) async => _mutateWorld(
      character.worldId,
      (World world) => world.copyWith(characters: [
            for (final StoryCharacter item in world.characters)
              item.id == character.id ? character : item
          ]),
      () => _repository.updateCharacter(character));
  Future<void> deleteCharacter(String worldId, String id) async => _mutateWorld(
      worldId,
      (World world) => world.copyWith(
          characters: world.characters
              .where((StoryCharacter item) => item.id != id)
              .toList(),
          openingDefinition: OpeningDefinition(
            startingLocationId: world.openingDefinition.startingLocationId,
            startingCharacterIds: world.openingDefinition.startingCharacterIds
                .where((String characterId) => characterId != id)
                .toList(),
            situation: world.openingDefinition.situation,
          )),
      () => _repository.deleteCharacter(id));
  Future<void> createLocation(String worldId, StoryLocation location) async =>
      _mutateWorld(
          worldId,
          (World world) =>
              world.copyWith(locations: [...world.locations, location]),
          () => _repository.createLocation(worldId, location));
  Future<void> updateLocation(StoryLocation location) async => _mutateWorld(
      location.worldId,
      (World world) => world.copyWith(locations: [
            for (final StoryLocation item in world.locations)
              item.id == location.id ? location : item
          ]),
      () => _repository.updateLocation(location));
  Future<void> deleteLocation(String worldId, String id) async => _mutateWorld(
      worldId,
      (World world) => world.copyWith(
          locations: world.locations
              .where((StoryLocation item) =>
                  item.id != id && !_isDescendant(item, id, world.locations))
              .toList()),
      () => _repository.deleteLocation(id));

  Future<void> _mutateWorld(String worldId, World Function(World) update,
          Future<void> Function() persist) async =>
      _guard('update world content', () async {
        final World? world =
            state.worlds.where((World item) => item.id == worldId).firstOrNull;
        if (world == null) throw StateError('World $worldId no longer exists.');
        await persist();
        final World updated = update(world);
        state = state.copyWith(worlds: [
          for (final World item in state.worlds)
            item.id == worldId ? updated : item
        ], autosaveStatus: AutosaveStatus.saved, clearError: true);
      });

  bool _isDescendant(StoryLocation candidate, String ancestorId,
      List<StoryLocation> locations) {
    String? parentId = candidate.parentId;
    final Set<String> visited = {};
    while (parentId != null && visited.add(parentId)) {
      if (parentId == ancestorId) return true;
      parentId = locations
          .where((StoryLocation item) => item.id == parentId)
          .firstOrNull
          ?.parentId;
    }
    return false;
  }

  Future<void> _guard(String action, Future<void> Function() operation) async {
    try {
      await operation();
      unawaited(ref
          .read(appFileLoggerProvider)
          .info('Persistence operation completed: $action.'));
    } catch (error, stackTrace) {
      _logFailure(action, error, stackTrace);
      final String friendlyMessage = switch (action) {
        'create world' =>
          'The world could not be saved to the local database. Check the database file permissions and try again.',
        _ => 'Could not $action. Your existing data is unchanged.',
      };
      state = state.copyWith(
          autosaveStatus: AutosaveStatus.failed, errorMessage: friendlyMessage);
      rethrow;
    }
  }

  WorldRepository get _repository {
    final WorldRepository? repository = ref.read(_repositoryHolderProvider);
    if (repository == null) {
      throw StateError('Repository is not ready.');
    }
    return repository;
  }

  void _logFailure(String action, Object error, StackTrace stackTrace) {
    developer.log('Continuum $action failed (errorType=${error.runtimeType})',
        stackTrace: stackTrace, name: 'Continuum.Workspace');
    unawaited(ref
        .read(appFileLoggerProvider)
        .error('Persistence operation failed: $action', error, stackTrace));
  }
}

final _repositoryHolderProvider =
    StateProvider<WorldRepository?>((ref) => null);
