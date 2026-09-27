import 'package:continuum_desktop/features/world/data/sqlite_world_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late SqliteWorldRepository repository;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    final Database database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            version: 1,
            onConfigure: (Database db) async =>
                db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (Database db, int version) =>
                SqliteWorldRepository.openSchemaForTesting(db)));
    repository = SqliteWorldRepository(database);
  });

  tearDown(() async => repository.close());

  test('world CRUD persists ordered rules and metadata', () async {
    final World world = _world('world_one');
    await repository.createWorld(world);
    expect((await repository.getWorld(world.id))!.rules, ['First', 'Second']);
    await repository.updateWorld(
        world.copyWith(name: 'Renamed', rules: ['Second', 'First']));
    expect((await repository.getWorld(world.id))!.name, 'Renamed');
    expect((await repository.getWorld(world.id))!.rules, ['Second', 'First']);
    await repository.deleteWorld(world.id);
    expect(await repository.getWorld(world.id), isNull);
  });

  test('entity CRUD and world isolation retain stable owner references',
      () async {
    await repository.createWorld(_world('world_one'));
    await repository.createWorld(_world('world_two'));
    final StoryCharacter character = _character('char_one', 'world_one');
    await repository.createCharacter('world_one', character);
    await repository.createLore(
        'world_one',
        const LoreEntry(
            id: 'lore_one',
            title: 'Era',
            category: 'Custom',
            content: 'Notes'));
    final StoryLocation location = _location('loc_one', 'world_one');
    await repository.createLocation('world_one', location);
    final World one = (await repository.getWorld('world_one'))!;
    expect(one.characters.single.worldId, 'world_one');
    expect((await repository.getWorld('world_two'))!.characters, isEmpty);
    await repository
        .updateCharacter(_character('char_one', 'world_one', name: 'Renamed'));
    await repository.updateLore(const LoreEntry(
        id: 'lore_one',
        worldId: 'world_one',
        title: 'New Era',
        category: 'Custom',
        content: 'Revised'));
    await repository.updateLocation(
        _location('loc_one', 'world_one', name: 'Renamed Place'));
    expect((await repository.getWorld('world_one'))!.characters.single.name,
        'Renamed');
    await repository.deleteCharacter('char_one');
    await repository.deleteLore('lore_one');
    await repository.deleteLocation('loc_one');
    expect((await repository.getWorld('world_one'))!.characters, isEmpty);
    expect((await repository.getWorld('world_one'))!.loreEntries, isEmpty);
    expect((await repository.getWorld('world_one'))!.locations, isEmpty);
  });

  test('rejects foreign-world, self-parent and circular location hierarchy',
      () async {
    await repository.createWorld(_world('world_one'));
    await repository.createWorld(_world('world_two'));
    await repository.createLocation(
        'world_one', _location('university', 'world_one'));
    await repository.createLocation(
        'world_one', _location('lab', 'world_one', parentId: 'university'));
    expect(
        () => repository.createLocation('world_two',
            _location('foreign', 'world_two', parentId: 'university')),
        throwsA(anything));
    expect(
        () => repository.updateLocation(
            _location('university', 'world_one', parentId: 'university')),
        throwsA(anything));
    expect(
        () => repository.updateLocation(
            _location('university', 'world_one', parentId: 'lab')),
        throwsA(anything));
  });

  test(
      'draft synchronization saves entity create, rename, delete as one snapshot',
      () async {
    await repository.createWorld(_world('world_one'));
    final World initial = (await repository.getWorld('world_one'))!;
    final World withEntries = initial.copyWith(
      loreEntries: [
        const LoreEntry(
            id: 'lore_one',
            worldId: 'world_one',
            title: 'First',
            category: 'Custom',
            content: 'Body')
      ],
      characters: [_character('char_one', 'world_one')],
      locations: [
        _location('university', 'world_one'),
        _location('lab', 'world_one', parentId: 'university')
      ],
    );
    await repository.updateWorldDraft(withEntries);
    final World renamed = withEntries.copyWith(
      loreEntries: [
        const LoreEntry(
            id: 'lore_one',
            worldId: 'world_one',
            title: 'Renamed',
            category: 'Society',
            content: 'Revised')
      ],
      locations: [
        _location('university', 'world_one', name: 'Campus'),
        _location('lab', 'world_one', name: 'Lab', parentId: 'university')
      ],
    );
    await repository.updateWorldDraft(renamed);
    final World restored = (await repository.getWorld('world_one'))!;
    expect(restored.loreEntries.single.title, 'Renamed');
    expect(
        restored.locations
            .singleWhere((StoryLocation item) => item.id == 'lab')
            .parentId,
        'university');
    await repository.updateWorldDraft(
        renamed.copyWith(loreEntries: [], characters: [], locations: []));
    final World emptied = (await repository.getWorld('world_one'))!;
    expect(emptied.loreEntries, isEmpty);
    expect(emptied.characters, isEmpty);
    expect(emptied.locations, isEmpty);
  });

  test('duplicate remaps every entity id and nested parent reference',
      () async {
    await repository.createWorld(_world('world_source'));
    await repository.createLore(
        'world_source',
        const LoreEntry(
            id: 'lore_source',
            title: 'History',
            category: 'History',
            content: 'Text'));
    await repository.createCharacter(
        'world_source', _character('char_source', 'world_source'));
    await repository.createLocation(
        'world_source', _location('university', 'world_source'));
    await repository.createLocation(
        'world_source',
        _location('laboratory', 'world_source',
            name: 'Laboratory', parentId: 'university'));
    final World copy = await repository.duplicateWorld('world_source');
    final World restored = (await repository.getWorld(copy.id))!;
    expect(restored.id, isNot('world_source'));
    expect(restored.loreEntries.single.id, isNot('lore_source'));
    expect(restored.characters.single.id, isNot('char_source'));
    final StoryLocation copiedLab = restored.locations
        .singleWhere((StoryLocation item) => item.name == 'Laboratory');
    final StoryLocation copiedUniversity = restored.locations
        .singleWhere((StoryLocation item) => item.name == 'University');
    expect(copiedLab.parentId, copiedUniversity.id);
    expect(copiedLab.parentId, isNot('university'));
    await repository.deleteWorld('world_source');
    expect((await repository.getWorld(copy.id))!.locations, hasLength(2));
  });
}

World _world(String id) => World(
    id: id,
    name: 'World',
    description: '',
    genre: const [],
    tone: const [],
    rules: const ['First', 'Second']);
StoryCharacter _character(String id, String worldId, {String name = 'Ari'}) =>
    StoryCharacter(
        id: id,
        worldId: worldId,
        name: name,
        role: 'Lead',
        description: '',
        appearance: '',
        personality: '',
        background: '',
        publicInformation: '',
        secretInformation: '');
StoryLocation _location(String id, String worldId,
        {String name = 'University', String? parentId}) =>
    StoryLocation(
        id: id,
        worldId: worldId,
        name: name,
        description: '',
        parentId: parentId);
