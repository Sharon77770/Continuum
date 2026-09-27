import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../novel/domain/campaign_repository.dart';
import '../../novel/domain/language_model_settings.dart';
import '../../library/domain/first_run_world_repository.dart';
import '../domain/world_repository.dart';

/// SQLite adapter. Domain values are mapped at this boundary and never know
/// about database rows or SQL.
class SqliteWorldRepository
    implements
        WorldRepository,
        CampaignRepository,
        LanguageModelSettingsRepository,
        FirstRunWorldRepository {
  SqliteWorldRepository(this._database);

  final Database _database;
  Future<void> close() => _database.close();

  @override
  Future<List<Campaign>> listCampaigns(String worldId) async {
    final List<Map<String, Object?>> rows = await _database.query('campaigns',
        where: 'world_id = ?',
        whereArgs: [worldId],
        orderBy: 'last_played_at DESC');
    return rows.map(_campaignFromRow).toList();
  }

  @override
  Future<Campaign?> getCampaign(String campaignId) async {
    final List<Map<String, Object?>> rows = await _database.query('campaigns',
        where: 'id = ?', whereArgs: [campaignId], limit: 1);
    return rows.isEmpty ? null : _campaignFromRow(rows.single);
  }

  @override
  Future<void> saveCampaign(Campaign campaign) async {
    final DateTime now = DateTime.now().toUtc();
    await _database.insert(
        'campaigns',
        {
          'id': campaign.id,
          'world_id': campaign.worldId,
          'payload': jsonEncode(_campaignToJson(campaign)),
          'updated_at': now.toIso8601String(),
          'last_played_at': campaign.lastPlayedAt.toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> saveLanguageModelSettings(LanguageModelSettings settings) async {
    await _database.insert(
        'language_model_settings',
        {
          'id': 1,
          'base_url': settings.baseUrl,
          'model': settings.model,
          'temperature': settings.temperature,
          'context_limit': settings.contextLimit,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<LanguageModelSettings> getLanguageModelSettings() async {
    final List<Map<String, Object?>> rows = await _database
        .query('language_model_settings', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return const LanguageModelSettings();
    final Map<String, Object?> row = rows.single;
    return LanguageModelSettings(
      baseUrl: row['base_url']! as String,
      model: row['model']! as String,
      temperature: (row['temperature']! as num).toDouble(),
      contextLimit: row['context_limit']! as int,
    );
  }

  Campaign _campaignFromRow(Map<String, Object?> row) => _campaignFromJson(
      jsonDecode(row['payload']! as String) as Map<String, dynamic>);

  Map<String, Object?> _campaignToJson(Campaign campaign) => {
        'schemaVersion': 1,
        'id': campaign.id,
        'worldId': campaign.worldId,
        'name': campaign.name,
        'languageCode': campaign.languageCode,
        'createdAt': campaign.createdAt.toUtc().toIso8601String(),
        'updatedAt': campaign.updatedAt.toUtc().toIso8601String(),
        'lastPlayedAt': campaign.lastPlayedAt.toUtc().toIso8601String(),
        'worldState': {
          'currentLocationId': campaign.worldState.currentLocationId,
          'presentCharacterIds': campaign.worldState.presentCharacterIds,
          'timeDescription': campaign.worldState.timeDescription,
          'atmosphere': campaign.worldState.atmosphere,
          'relevantObjects': campaign.worldState.relevantObjects,
          'facts': campaign.worldState.facts,
          'turnNumber': campaign.worldState.turnNumber,
          'events': campaign.worldState.events
              .map((GameEvent event) => {
                    'id': event.id,
                    'kind': event.kind,
                    'description': event.description,
                  })
              .toList(),
        },
        'currentScene': campaign.currentScene == null
            ? null
            : _sceneToJson(campaign.currentScene!),
        'history': campaign.history.map(_sceneToJson).toList(),
        'characterMemory': campaign.characterMemory
            .map((String id, CharacterMemory memory) => MapEntry(id, {
                  'importantMemories': memory.importantMemories,
                  'knownFacts': memory.knownFacts,
                  'relationship': memory.relationship,
                  'currentEmotion': memory.currentEmotion,
                  'goals': memory.goals,
                  'recentEvents': memory.recentEvents,
                })),
      };

  Campaign _campaignFromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported Campaign schema.');
    }
    final Map<String, dynamic> state =
        json['worldState'] as Map<String, dynamic>;
    final Map<String, dynamic> rawMemory =
        json['characterMemory'] as Map<String, dynamic>;
    return Campaign(
      id: json['id'] as String,
      worldId: json['worldId'] as String,
      name: json['name'] as String,
      languageCode: json['languageCode'] as String? ?? 'en',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      lastPlayedAt: DateTime.parse(json['lastPlayedAt'] as String),
      worldState: WorldState(
        currentLocationId: state['currentLocationId'] as String?,
        presentCharacterIds:
            (state['presentCharacterIds'] as List).cast<String>(),
        timeDescription: state['timeDescription'] as String?,
        atmosphere: state['atmosphere'] as String?,
        relevantObjects:
            (state['relevantObjects'] as List?)?.cast<String>() ?? const [],
        facts: (state['facts'] as Map).cast<String, String>(),
        turnNumber: state['turnNumber'] as int,
        events: (state['events'] as List).map((Object? item) {
          final Map<String, dynamic> event = item! as Map<String, dynamic>;
          return GameEvent(
              id: event['id'] as String,
              kind: event['kind'] as String,
              description: event['description'] as String);
        }).toList(),
      ),
      currentScene: json['currentScene'] == null
          ? null
          : _sceneFromJson(json['currentScene'] as Map<String, dynamic>),
      history: (json['history'] as List)
          .map((Object? item) => _sceneFromJson(item! as Map<String, dynamic>))
          .toList(),
      characterMemory: rawMemory.map((String id, dynamic item) {
        final Map<String, dynamic> memory = item as Map<String, dynamic>;
        return MapEntry(
            id,
            CharacterMemory(
              importantMemories:
                  (memory['importantMemories'] as List).cast<String>(),
              knownFacts: (memory['knownFacts'] as List).cast<String>(),
              relationship: memory['relationship'] as String?,
              currentEmotion: memory['currentEmotion'] as String?,
              goals: (memory['goals'] as List?)?.cast<String>() ?? const [],
              recentEvents:
                  (memory['recentEvents'] as List?)?.cast<String>() ?? const [],
            ));
      }),
    );
  }

  Map<String, Object?> _sceneToJson(SceneTurn scene) => {
        'id': scene.id,
        'narration': scene.narration,
        'dialogue': scene.dialogue
            .map((SceneDialogue line) => {
                  'characterId': line.characterId,
                  'text': line.text,
                })
            .toList(),
        'choices': scene.choices,
        'playerAction': scene.playerAction,
        'createdAt': scene.createdAt.toUtc().toIso8601String(),
      };

  SceneTurn _sceneFromJson(Map<String, dynamic> json) => SceneTurn(
        id: json['id'] as String,
        narration: json['narration'] as String,
        dialogue: (json['dialogue'] as List).map((Object? item) {
          final Map<String, dynamic> line = item! as Map<String, dynamic>;
          return SceneDialogue(
              characterId: line['characterId'] as String,
              text: line['text'] as String);
        }).toList(),
        choices: (json['choices'] as List).cast<String>(),
        playerAction: json['playerAction'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  static Future<void> openSchemaForTesting(Database database) =>
      _createSchema(database, 1);

  static Future<SqliteWorldRepository> open(String databasePath) async {
    sqfliteFfiInit();
    final Database database = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (Database db) async =>
            db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    return SqliteWorldRepository(database);
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''CREATE TABLE app_metadata (
      key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE worlds (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT NOT NULL,
      genres TEXT NOT NULL, tones TEXT NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      player_name TEXT NOT NULL DEFAULT '', player_description TEXT NOT NULL DEFAULT '',
      player_background TEXT NOT NULL DEFAULT '', player_traits TEXT NOT NULL DEFAULT '',
      opening_location_id TEXT, opening_character_ids TEXT NOT NULL DEFAULT '',
      opening_situation TEXT NOT NULL DEFAULT '')''');
    await db.execute('''CREATE TABLE world_rules (
      id TEXT PRIMARY KEY, world_id TEXT NOT NULL REFERENCES worlds(id) ON DELETE CASCADE,
      position INTEGER NOT NULL, text TEXT NOT NULL, UNIQUE(world_id, position))''');
    await db.execute('''CREATE TABLE lore_entries (
      id TEXT PRIMARY KEY, world_id TEXT NOT NULL REFERENCES worlds(id) ON DELETE CASCADE,
      title TEXT NOT NULL, category TEXT NOT NULL, content TEXT NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE characters (
      id TEXT PRIMARY KEY, world_id TEXT NOT NULL REFERENCES worlds(id) ON DELETE CASCADE,
      name TEXT NOT NULL, role TEXT NOT NULL, description TEXT NOT NULL,
      appearance TEXT NOT NULL, personality TEXT NOT NULL, background TEXT NOT NULL,
      public_information TEXT NOT NULL, secret_information TEXT NOT NULL,
      portrait_asset_id TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE locations (
      id TEXT PRIMARY KEY, world_id TEXT NOT NULL REFERENCES worlds(id) ON DELETE CASCADE,
      name TEXT NOT NULL, description TEXT NOT NULL, parent_location_id TEXT,
      background_asset_id TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      FOREIGN KEY(parent_location_id) REFERENCES locations(id) ON DELETE CASCADE)''');
    await db.execute('CREATE INDEX idx_lore_world ON lore_entries(world_id)');
    await db
        .execute('CREATE INDEX idx_characters_world ON characters(world_id)');
    await db.execute(
        'CREATE INDEX idx_locations_world_parent ON locations(world_id, parent_location_id)');
    await db
        .execute('CREATE INDEX idx_worlds_updated ON worlds(updated_at DESC)');
    await db.execute('''CREATE TRIGGER locations_same_world_insert
      BEFORE INSERT ON locations WHEN NEW.parent_location_id IS NOT NULL
      BEGIN SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM locations p
        WHERE p.id=NEW.parent_location_id AND p.world_id=NEW.world_id)
        THEN RAISE(ABORT, 'location parent must belong to same world') END; END''');
    await db.execute('''CREATE TRIGGER locations_same_world_update
      BEFORE UPDATE OF parent_location_id, world_id ON locations
      WHEN NEW.parent_location_id IS NOT NULL
      BEGIN SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM locations p
        WHERE p.id=NEW.parent_location_id AND p.world_id=NEW.world_id)
        THEN RAISE(ABORT, 'location parent must belong to same world') END; END''');
    await db.execute('''CREATE TRIGGER locations_no_cycle_insert
      BEFORE INSERT ON locations WHEN NEW.parent_location_id IS NOT NULL
      BEGIN SELECT CASE WHEN NEW.parent_location_id=NEW.id
        THEN RAISE(ABORT, 'location cannot parent itself') END; END''');
    await db.execute('''CREATE TRIGGER locations_no_cycle_update
      BEFORE UPDATE OF parent_location_id ON locations
      WHEN NEW.parent_location_id IS NOT NULL
      BEGIN SELECT CASE WHEN NEW.parent_location_id=NEW.id OR EXISTS (
        WITH RECURSIVE descendants(id) AS (
          SELECT id FROM locations WHERE parent_location_id=NEW.id
          UNION ALL SELECT l.id FROM locations l JOIN descendants d ON l.parent_location_id=d.id)
        SELECT 1 FROM descendants WHERE id=NEW.parent_location_id)
        THEN RAISE(ABORT, 'circular location hierarchy') END; END''');
    await db.execute('''CREATE TABLE campaigns (
      id TEXT PRIMARY KEY, world_id TEXT NOT NULL REFERENCES worlds(id) ON DELETE CASCADE,
      payload TEXT NOT NULL, updated_at TEXT NOT NULL, last_played_at TEXT NOT NULL)''');
    await db.execute(
        'CREATE INDEX idx_campaigns_world ON campaigns(world_id, last_played_at DESC)');
    await db.execute('''CREATE TABLE language_model_settings (
      id INTEGER PRIMARY KEY CHECK(id = 1), base_url TEXT NOT NULL, model TEXT NOT NULL,
      temperature REAL NOT NULL, context_limit INTEGER NOT NULL)''');
  }

  static Future<void> _upgradeSchema(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          "ALTER TABLE worlds ADD COLUMN player_name TEXT NOT NULL DEFAULT ''");
      await db.execute(
          "ALTER TABLE worlds ADD COLUMN player_description TEXT NOT NULL DEFAULT ''");
      await db.execute(
          "ALTER TABLE worlds ADD COLUMN player_background TEXT NOT NULL DEFAULT ''");
      await db.execute(
          "ALTER TABLE worlds ADD COLUMN player_traits TEXT NOT NULL DEFAULT ''");
      await db
          .execute('ALTER TABLE worlds ADD COLUMN opening_location_id TEXT');
      await db.execute(
          "ALTER TABLE worlds ADD COLUMN opening_character_ids TEXT NOT NULL DEFAULT ''");
      await db.execute(
          "ALTER TABLE worlds ADD COLUMN opening_situation TEXT NOT NULL DEFAULT ''");
      await db.execute('''CREATE TABLE campaigns (
        id TEXT PRIMARY KEY, world_id TEXT NOT NULL REFERENCES worlds(id) ON DELETE CASCADE,
        payload TEXT NOT NULL, updated_at TEXT NOT NULL, last_played_at TEXT NOT NULL)''');
      await db.execute(
          'CREATE INDEX idx_campaigns_world ON campaigns(world_id, last_played_at DESC)');
      await db.execute('''CREATE TABLE language_model_settings (
        id INTEGER PRIMARY KEY CHECK(id = 1), base_url TEXT NOT NULL, model TEXT NOT NULL,
        temperature REAL NOT NULL, context_limit INTEGER NOT NULL)''');
    }
    if (oldVersion < 3) {
      await db.execute('''CREATE TABLE app_metadata (
        key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
    }
  }

  @override
  Future<void> seedDefaultWorldIfFirstRun(World world) =>
      _database.transaction((Transaction txn) async {
        const String seedKey = 'default_world_seed_v1';
        final List<Map<String, Object?>> seedRows = await txn.query(
            'app_metadata',
            columns: ['value'],
            where: 'key = ?',
            whereArgs: [seedKey],
            limit: 1);
        if (seedRows.isNotEmpty) return;

        final List<Map<String, Object?>> worldCount =
            await txn.rawQuery('SELECT COUNT(*) AS count FROM worlds');
        if ((worldCount.single['count']! as int) > 0) {
          await txn.insert('app_metadata',
              {'key': seedKey, 'value': 'skipped_existing_worlds'});
          return;
        }

        final DateTime now = DateTime.now().toUtc();
        await txn.insert('worlds', _worldValues(world, now, now));
        await _replaceRules(txn, world);
        await _synchronizeLore(txn, world, now);
        await _synchronizeCharacters(txn, world, now);
        await _synchronizeLocations(txn, world, now);
        await txn.insert('app_metadata', {'key': seedKey, 'value': world.id});
      });

  @override
  Future<List<World>> listWorlds() async {
    final List<Map<String, Object?>> rows =
        await _database.query('worlds', orderBy: 'updated_at DESC');
    final List<World> worlds = [];
    for (final Map<String, Object?> row in rows) {
      worlds.add((await getWorld(row['id']! as String))!);
    }
    return worlds;
  }

  @override
  Future<World?> getWorld(String worldId) async {
    final List<Map<String, Object?>> rows = await _database.query('worlds',
        where: 'id = ?', whereArgs: [worldId], limit: 1);
    if (rows.isEmpty) return null;
    final Map<String, Object?> row = rows.single;
    final List<Map<String, Object?>> ruleRows = await _database.query(
        'world_rules',
        where: 'world_id = ?',
        whereArgs: [worldId],
        orderBy: 'position');
    final List<Map<String, Object?>> loreRows = await _database.query(
        'lore_entries',
        where: 'world_id = ?',
        whereArgs: [worldId],
        orderBy: 'created_at');
    final List<Map<String, Object?>> characterRows = await _database.query(
        'characters',
        where: 'world_id = ?',
        whereArgs: [worldId],
        orderBy: 'created_at');
    final List<Map<String, Object?>> locationRows = await _database.query(
        'locations',
        where: 'world_id = ?',
        whereArgs: [worldId],
        orderBy: 'created_at');
    return World(
      id: worldId,
      name: row['name']! as String,
      description: row['description']! as String,
      genre: _decodeStrings(row['genres']! as String),
      tone: _decodeStrings(row['tones']! as String),
      rules: [
        for (final Map<String, Object?> rule in ruleRows)
          rule['text']! as String
      ],
      loreEntries: [
        for (final Map<String, Object?> entry in loreRows) _loreFromRow(entry)
      ],
      characters: [
        for (final Map<String, Object?> character in characterRows)
          _characterFromRow(character)
      ],
      locations: [
        for (final Map<String, Object?> location in locationRows)
          _locationFromRow(location)
      ],
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
      playerDefinition: _playerFromRow(row),
      openingDefinition: _openingFromRow(row),
    );
  }

  @override
  Future<void> createWorld(World world) =>
      _database.transaction((Transaction txn) async {
        final DateTime now = DateTime.now().toUtc();
        await txn.insert('worlds', _worldValues(world, now, now));
        await _replaceRules(txn, world);
        await _synchronizeLore(txn, world, now);
        await _synchronizeCharacters(txn, world, now);
        await _synchronizeLocations(txn, world, now);
      });

  @override
  Future<void> updateWorld(World world) =>
      _database.transaction((Transaction txn) async {
        final DateTime now = DateTime.now().toUtc();
        final int changed = await txn.update(
            'worlds', _worldValues(world, world.createdAt ?? now, now),
            where: 'id = ?', whereArgs: [world.id]);
        if (changed == 0) {
          throw StateError('World ${world.id} no longer exists.');
        }
        await _replaceRules(txn, world);
      });

  @override
  Future<void> updateWorldDraft(World world) =>
      _database.transaction((Transaction txn) async {
        final DateTime now = DateTime.now().toUtc();
        final int changed = await txn.update(
            'worlds', _worldValues(world, world.createdAt ?? now, now),
            where: 'id = ?', whereArgs: [world.id]);
        if (changed == 0) {
          throw StateError('World ${world.id} no longer exists.');
        }
        await _replaceRules(txn, world);
        await _synchronizeLore(txn, world, now);
        await _synchronizeCharacters(txn, world, now);
        await _synchronizeLocations(txn, world, now);
      });

  Future<void> _synchronizeLore(
      Transaction txn, World world, DateTime now) async {
    final List<Map<String, Object?>> rows = await txn.query('lore_entries',
        columns: ['id'], where: 'world_id = ?', whereArgs: [world.id]);
    final Set<String> existing =
        rows.map((Map<String, Object?> row) => row['id']! as String).toSet();
    final Set<String> retained =
        world.loreEntries.map((LoreEntry item) => item.id).toSet();
    for (final String id in existing.difference(retained)) {
      await txn.delete('lore_entries', where: 'id = ?', whereArgs: [id]);
    }
    for (final LoreEntry entry in world.loreEntries) {
      if (existing.contains(entry.id)) {
        await txn.update(
            'lore_entries',
            {
              'title': entry.title,
              'category': entry.category,
              'content': entry.content,
              'updated_at': now.toIso8601String()
            },
            where: 'id = ? AND world_id = ?',
            whereArgs: [entry.id, world.id]);
      } else {
        await txn.insert(
            'lore_entries', _loreValues(entry, world.id, now, now));
      }
    }
  }

  Future<void> _synchronizeCharacters(
      Transaction txn, World world, DateTime now) async {
    final List<Map<String, Object?>> rows = await txn.query('characters',
        columns: ['id'], where: 'world_id = ?', whereArgs: [world.id]);
    final Set<String> existing =
        rows.map((Map<String, Object?> row) => row['id']! as String).toSet();
    final Set<String> retained =
        world.characters.map((StoryCharacter item) => item.id).toSet();
    for (final String id in existing.difference(retained)) {
      await txn.delete('characters', where: 'id = ?', whereArgs: [id]);
    }
    for (final StoryCharacter item in world.characters) {
      if (existing.contains(item.id)) {
        await txn.update('characters',
            {..._characterContent(item), 'updated_at': now.toIso8601String()},
            where: 'id = ? AND world_id = ?', whereArgs: [item.id, world.id]);
      } else {
        await txn.insert(
            'characters', _characterValues(item, world.id, now, now));
      }
    }
  }

  Future<void> _synchronizeLocations(
      Transaction txn, World world, DateTime now) async {
    final List<Map<String, Object?>> rows = await txn.query('locations',
        columns: ['id'], where: 'world_id = ?', whereArgs: [world.id]);
    final Set<String> existing =
        rows.map((Map<String, Object?> row) => row['id']! as String).toSet();
    final Set<String> retained =
        world.locations.map((StoryLocation item) => item.id).toSet();
    for (final StoryLocation location in world.locations
        .where((StoryLocation item) => existing.contains(item.id))) {
      await txn.update('locations',
          {..._locationContent(location), 'updated_at': now.toIso8601String()},
          where: 'id = ? AND world_id = ?', whereArgs: [location.id, world.id]);
    }
    for (final String id in existing.difference(retained)) {
      await txn.delete('locations', where: 'id = ?', whereArgs: [id]);
    }
    final Set<String> inserted = existing.intersection(retained);
    final List<StoryLocation> pending = world.locations
        .where((StoryLocation item) => !existing.contains(item.id))
        .toList();
    while (pending.isNotEmpty) {
      final int readyIndex = pending.indexWhere((StoryLocation item) =>
          item.parentId == null || inserted.contains(item.parentId));
      if (readyIndex < 0) {
        throw StateError('Malformed location hierarchy in ${world.id}.');
      }
      final StoryLocation location = pending.removeAt(readyIndex);
      await txn.insert(
          'locations', _locationValues(location, world.id, now, now));
      inserted.add(location.id);
    }
  }

  @override
  Future<void> deleteWorld(String worldId) async =>
      _database.delete('worlds', where: 'id = ?', whereArgs: [worldId]);

  @override
  Future<World> duplicateWorld(String worldId) async =>
      _database.transaction((Transaction txn) async {
        final World? source = await _getWorld(txn, worldId);
        if (source == null) {
          throw StateError('World $worldId no longer exists.');
        }
        final DateTime now = DateTime.now().toUtc();
        final String newWorldId = createStableId('world');
        final World copy = World(
            id: newWorldId,
            name: '${source.name} Copy',
            description: source.description,
            genre: source.genre,
            tone: source.tone,
            rules: source.rules,
            playerDefinition: source.playerDefinition,
            openingDefinition: source.openingDefinition,
            createdAt: now,
            updatedAt: now);
        await txn.insert('worlds', _worldValues(copy, now, now));
        await _replaceRules(txn, copy);
        for (final LoreEntry entry in source.loreEntries) {
          await txn.insert(
              'lore_entries',
              _loreValues(
                  LoreEntry(
                      id: createStableId('lore'),
                      worldId: newWorldId,
                      title: entry.title,
                      category: entry.category,
                      content: entry.content),
                  newWorldId,
                  now,
                  now));
        }
        for (final StoryCharacter character in source.characters) {
          await txn.insert(
              'characters',
              _characterValues(
                  StoryCharacter(
                      id: createStableId('char'),
                      worldId: newWorldId,
                      name: character.name,
                      role: character.role,
                      description: character.description,
                      appearance: character.appearance,
                      personality: character.personality,
                      background: character.background,
                      publicInformation: character.publicInformation,
                      secretInformation: character.secretInformation,
                      portraitReference: character.portraitReference),
                  newWorldId,
                  now,
                  now));
        }
        final Map<String, String> locationIds = {
          for (final StoryLocation item in source.locations)
            item.id: createStableId('loc')
        };
        final List<StoryLocation> pending = source.locations
            .map((StoryLocation item) => StoryLocation(
                id: locationIds[item.id]!,
                worldId: newWorldId,
                name: item.name,
                description: item.description,
                parentId:
                    item.parentId == null ? null : locationIds[item.parentId],
                backgroundReference: item.backgroundReference))
            .toList();
        final Set<String> inserted = {};
        while (inserted.length < pending.length) {
          final Iterable<StoryLocation> ready = pending.where(
              (StoryLocation item) =>
                  !inserted.contains(item.id) &&
                  (item.parentId == null || inserted.contains(item.parentId)));
          if (ready.isEmpty) {
            throw StateError('Malformed location hierarchy in $worldId.');
          }
          final StoryLocation next = ready.first;
          await txn.insert(
              'locations', _locationValues(next, newWorldId, now, now));
          inserted.add(next.id);
        }
        return copy.copyWith(loreEntries: [
          for (final LoreEntry item in source.loreEntries)
            LoreEntry(
                id: createStableId('lore'),
                worldId: newWorldId,
                title: item.title,
                category: item.category,
                content: item.content)
        ], characters: [
          for (final StoryCharacter item in source.characters)
            StoryCharacter(
                id: createStableId('char'),
                worldId: newWorldId,
                name: item.name,
                role: item.role,
                description: item.description,
                appearance: item.appearance,
                personality: item.personality,
                background: item.background,
                publicInformation: item.publicInformation,
                secretInformation: item.secretInformation,
                portraitReference: item.portraitReference)
        ], locations: pending);
      });

  Future<World?> _getWorld(Transaction txn, String id) async {
    final List<Map<String, Object?>> rows =
        await txn.query('worlds', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final Map<String, Object?> row = rows.single;
    final List<Map<String, Object?>> rules = await txn.query('world_rules',
        where: 'world_id = ?', whereArgs: [id], orderBy: 'position');
    final List<Map<String, Object?>> lore =
        await txn.query('lore_entries', where: 'world_id = ?', whereArgs: [id]);
    final List<Map<String, Object?>> characters =
        await txn.query('characters', where: 'world_id = ?', whereArgs: [id]);
    final List<Map<String, Object?>> locations =
        await txn.query('locations', where: 'world_id = ?', whereArgs: [id]);
    return World(
        id: id,
        name: row['name']! as String,
        description: row['description']! as String,
        genre: _decodeStrings(row['genres']! as String),
        tone: _decodeStrings(row['tones']! as String),
        rules: [
          for (final Map<String, Object?> rule in rules) rule['text']! as String
        ],
        loreEntries: [
          for (final Map<String, Object?> item in lore) _loreFromRow(item)
        ],
        characters: [
          for (final Map<String, Object?> item in characters)
            _characterFromRow(item)
        ],
        locations: [
          for (final Map<String, Object?> item in locations)
            _locationFromRow(item)
        ],
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
        playerDefinition: _playerFromRow(row),
        openingDefinition: _openingFromRow(row));
  }

  @override
  Future<void> createLore(String worldId, LoreEntry entry) async {
    final DateTime now = DateTime.now().toUtc();
    await _database.insert(
        'lore_entries', _loreValues(entry, worldId, now, now));
  }

  @override
  Future<void> updateLore(LoreEntry entry) =>
      _updateEntry('lore_entries', entry.id, {
        'title': entry.title,
        'category': entry.category,
        'content': entry.content
      });
  @override
  Future<void> deleteLore(String entryId) async =>
      _database.delete('lore_entries', where: 'id = ?', whereArgs: [entryId]);

  @override
  Future<void> createCharacter(String worldId, StoryCharacter character) async {
    final DateTime now = DateTime.now().toUtc();
    await _database.insert(
        'characters', _characterValues(character, worldId, now, now));
  }

  @override
  Future<void> updateCharacter(StoryCharacter character) =>
      _updateEntry('characters', character.id, _characterContent(character));
  @override
  Future<void> deleteCharacter(String characterId) async =>
      _database.delete('characters', where: 'id = ?', whereArgs: [characterId]);

  @override
  Future<void> createLocation(String worldId, StoryLocation location) async {
    final DateTime now = DateTime.now().toUtc();
    await _database.insert(
        'locations', _locationValues(location, worldId, now, now));
  }

  @override
  Future<void> updateLocation(StoryLocation location) =>
      _updateEntry('locations', location.id, _locationContent(location));
  @override
  Future<void> deleteLocation(String locationId) async =>
      _database.delete('locations', where: 'id = ?', whereArgs: [locationId]);

  Future<void> _updateEntry(
      String table, String id, Map<String, Object?> values) async {
    values['updated_at'] = DateTime.now().toUtc().toIso8601String();
    final int changed =
        await _database.update(table, values, where: 'id = ?', whereArgs: [id]);
    if (changed == 0) throw StateError('Entry $id no longer exists.');
  }

  static Future<void> _replaceRules(Transaction txn, World world) async {
    await txn
        .delete('world_rules', where: 'world_id = ?', whereArgs: [world.id]);
    for (int index = 0; index < world.rules.length; index++) {
      await txn.insert('world_rules', {
        'id': createStableId('rule'),
        'world_id': world.id,
        'position': index,
        'text': world.rules[index]
      });
    }
  }

  static Map<String, Object?> _worldValues(
          World world, DateTime createdAt, DateTime updatedAt) =>
      {
        'id': world.id,
        'name': world.name.trim(),
        'description': world.description,
        'genres': _encodeStrings(world.genre),
        'tones': _encodeStrings(world.tone),
        'player_name': world.playerDefinition.name,
        'player_description': world.playerDefinition.description,
        'player_background': world.playerDefinition.background,
        'player_traits': _encodeStrings(world.playerDefinition.traits),
        'opening_location_id': world.openingDefinition.startingLocationId,
        'opening_character_ids':
            _encodeStrings(world.openingDefinition.startingCharacterIds),
        'opening_situation': world.openingDefinition.situation,
        'created_at': (world.createdAt ?? createdAt).toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
  static Map<String, Object?> _loreValues(LoreEntry entry, String worldId,
          DateTime createdAt, DateTime updatedAt) =>
      {
        'id': entry.id,
        'world_id': worldId,
        'title': entry.title,
        'category': entry.category,
        'content': entry.content,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
  static Map<String, Object?> _characterContent(StoryCharacter character) => {
        'name': character.name,
        'role': character.role,
        'description': character.description,
        'appearance': character.appearance,
        'personality': character.personality,
        'background': character.background,
        'public_information': character.publicInformation,
        'secret_information': character.secretInformation,
        'portrait_asset_id': character.portraitReference,
      };
  static Map<String, Object?> _characterValues(StoryCharacter character,
          String worldId, DateTime createdAt, DateTime updatedAt) =>
      {
        'id': character.id,
        'world_id': worldId,
        ..._characterContent(character),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
  static Map<String, Object?> _locationContent(StoryLocation location) => {
        'name': location.name,
        'description': location.description,
        'parent_location_id': location.parentId,
        'background_asset_id': location.backgroundReference,
      };
  static Map<String, Object?> _locationValues(StoryLocation location,
          String worldId, DateTime createdAt, DateTime updatedAt) =>
      {
        'id': location.id,
        'world_id': worldId,
        ..._locationContent(location),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
  static LoreEntry _loreFromRow(Map<String, Object?> row) => LoreEntry(
      id: row['id']! as String,
      worldId: row['world_id']! as String,
      title: row['title']! as String,
      category: row['category']! as String,
      content: row['content']! as String,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String));
  static StoryCharacter _characterFromRow(Map<String, Object?> row) =>
      StoryCharacter(
          id: row['id']! as String,
          worldId: row['world_id']! as String,
          name: row['name']! as String,
          role: row['role']! as String,
          description: row['description']! as String,
          appearance: row['appearance']! as String,
          personality: row['personality']! as String,
          background: row['background']! as String,
          publicInformation: row['public_information']! as String,
          secretInformation: row['secret_information']! as String,
          portraitReference: row['portrait_asset_id'] as String?,
          createdAt: DateTime.parse(row['created_at']! as String),
          updatedAt: DateTime.parse(row['updated_at']! as String));
  static StoryLocation _locationFromRow(Map<String, Object?> row) =>
      StoryLocation(
          id: row['id']! as String,
          worldId: row['world_id']! as String,
          name: row['name']! as String,
          description: row['description']! as String,
          parentId: row['parent_location_id'] as String?,
          backgroundReference: row['background_asset_id'] as String?,
          createdAt: DateTime.parse(row['created_at']! as String),
          updatedAt: DateTime.parse(row['updated_at']! as String));
  static PlayerDefinition _playerFromRow(Map<String, Object?> row) =>
      PlayerDefinition(
        name: row['player_name'] as String? ?? '',
        description: row['player_description'] as String? ?? '',
        background: row['player_background'] as String? ?? '',
        traits: _decodeStrings(row['player_traits'] as String? ?? ''),
      );
  static OpeningDefinition _openingFromRow(Map<String, Object?> row) =>
      OpeningDefinition(
        startingLocationId: row['opening_location_id'] as String?,
        startingCharacterIds:
            _decodeStrings(row['opening_character_ids'] as String? ?? ''),
        situation: row['opening_situation'] as String? ?? '',
      );
  static String _encodeStrings(List<String> values) =>
      values.map(Uri.encodeComponent).join('\u001f');
  static List<String> _decodeStrings(String value) => value.isEmpty
      ? []
      : value.split('\u001f').map(Uri.decodeComponent).toList();
}
