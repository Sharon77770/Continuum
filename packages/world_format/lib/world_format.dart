import 'dart:convert';

import 'package:game_core/game_core.dart';

/// Encodes and validates portable, versioned Continuum scenario files.
class ScenarioPackCodec {
  const ScenarioPackCodec();

  static const String format = 'continuum-scenario';
  static const int currentVersion = 1;

  /// Converts an authored World into a human-readable JSON scenario file.
  String encode(World world) => const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': currentVersion,
        'world': _worldToJson(world),
      });

  /// Decodes a scenario file and rejects unsupported or malformed data.
  World decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Scenario file is not valid JSON: ${error.message}');
    }
    final Map<String, Object?> pack = _object(decoded, 'scenario');
    if (pack['format'] != format) {
      throw const FormatException('This is not a Continuum scenario file.');
    }
    if (pack['version'] != currentVersion) {
      throw FormatException(
          'Unsupported scenario version: ${pack['version']}.');
    }
    return _worldFromJson(_object(pack['world'], 'world'));
  }

  Map<String, Object?> _worldToJson(World world) => {
        'id': world.id,
        'name': world.name,
        'description': world.description,
        'genre': world.genre,
        'tone': world.tone,
        'rules': world.rules,
        'loreEntries': [
          for (final LoreEntry entry in world.loreEntries)
            {
              'id': entry.id,
              'title': entry.title,
              'category': entry.category,
              'content': entry.content,
            }
        ],
        'characters': [
          for (final StoryCharacter character in world.characters)
            {
              'id': character.id,
              'name': character.name,
              'role': character.role,
              'description': character.description,
              'appearance': character.appearance,
              'personality': character.personality,
              'background': character.background,
              'publicInformation': character.publicInformation,
              'secretInformation': character.secretInformation,
            }
        ],
        'locations': [
          for (final StoryLocation location in world.locations)
            {
              'id': location.id,
              'name': location.name,
              'description': location.description,
              'parentId': location.parentId,
            }
        ],
        'playerDefinition': {
          'name': world.playerDefinition.name,
          'description': world.playerDefinition.description,
          'background': world.playerDefinition.background,
          'traits': world.playerDefinition.traits,
        },
        'openingDefinition': {
          'startingLocationId': world.openingDefinition.startingLocationId,
          'startingCharacterIds': world.openingDefinition.startingCharacterIds,
          'situation': world.openingDefinition.situation,
        },
      };

  World _worldFromJson(Map<String, Object?> json) {
    final String worldId = _string(json, 'id');
    if (worldId.trim().isEmpty) {
      throw const FormatException('Scenario world ID cannot be empty.');
    }
    final List<LoreEntry> loreEntries = [
      for (final Object? item in _list(json, 'loreEntries'))
        _loreEntry(_object(item, 'lore entry')),
    ];
    final List<StoryCharacter> characters = [
      for (final Object? item in _list(json, 'characters'))
        _character(_object(item, 'character'), worldId),
    ];
    final List<StoryLocation> locations = [
      for (final Object? item in _list(json, 'locations'))
        _location(_object(item, 'location'), worldId),
    ];
    final Map<String, Object?> opening =
        _object(json['openingDefinition'], 'openingDefinition');
    final String? startingLocationId =
        _optionalString(opening, 'startingLocationId');
    final List<String> startingCharacterIds =
        _strings(opening, 'startingCharacterIds');
    _validateReferences(
        loreEntries, characters, locations, startingLocationId,
        startingCharacterIds);
    final String name = _string(json, 'name');
    if (name.trim().isEmpty) {
      throw const FormatException('Scenario world name cannot be empty.');
    }
    return World(
      id: worldId,
      name: name,
      description: _string(json, 'description'),
      genre: _strings(json, 'genre'),
      tone: _strings(json, 'tone'),
      rules: _strings(json, 'rules'),
      loreEntries: loreEntries,
      characters: characters,
      locations: locations,
      playerDefinition: _playerDefinition(
          _object(json['playerDefinition'], 'playerDefinition')),
      openingDefinition: OpeningDefinition(
        startingLocationId: startingLocationId,
        startingCharacterIds: startingCharacterIds,
        situation: _string(opening, 'situation'),
      ),
    );
  }

  LoreEntry _loreEntry(Map<String, Object?> json) => LoreEntry(
        id: _string(json, 'id'),
        title: _string(json, 'title'),
        category: _string(json, 'category'),
        content: _string(json, 'content'),
      );

  StoryCharacter _character(Map<String, Object?> json, String worldId) =>
      StoryCharacter(
        id: _string(json, 'id'),
        worldId: worldId,
        name: _string(json, 'name'),
        role: _string(json, 'role'),
        description: _string(json, 'description'),
        appearance: _string(json, 'appearance'),
        personality: _string(json, 'personality'),
        background: _string(json, 'background'),
        publicInformation: _string(json, 'publicInformation'),
        secretInformation: _string(json, 'secretInformation'),
      );

  StoryLocation _location(Map<String, Object?> json, String worldId) =>
      StoryLocation(
        id: _string(json, 'id'),
        worldId: worldId,
        name: _string(json, 'name'),
        description: _string(json, 'description'),
        parentId: _optionalString(json, 'parentId'),
      );

  PlayerDefinition _playerDefinition(Map<String, Object?> json) =>
      PlayerDefinition(
        name: _string(json, 'name'),
        description: _string(json, 'description'),
        background: _string(json, 'background'),
        traits: _strings(json, 'traits'),
      );

  void _validateReferences(
    List<LoreEntry> loreEntries,
    List<StoryCharacter> characters,
    List<StoryLocation> locations,
    String? startingLocationId,
    List<String> startingCharacterIds,
  ) {
    if (!_hasUniqueNonemptyIds(loreEntries.map((item) => item.id))) {
      throw const FormatException('Scenario contains duplicate lore IDs.');
    }
    final List<String> locationIdList =
        locations.map((item) => item.id).toList();
    final List<String> characterIdList =
        characters.map((item) => item.id).toList();
    final Set<String> locationIds = locationIdList.toSet();
    final Set<String> characterIds = characterIdList.toSet();
    if (!_hasUniqueNonemptyIds(locationIdList) ||
        !_hasUniqueNonemptyIds(characterIdList)) {
      throw const FormatException('Scenario contains duplicate content IDs.');
    }
    final Map<String, StoryLocation> locationsById = {
      for (final StoryLocation location in locations) location.id: location,
    };
    for (final StoryLocation location in locations) {
      if (location.parentId != null && !locationIds.contains(location.parentId)) {
        throw FormatException('Location "${location.name}" has an unknown parent.');
      }
      final Set<String> ancestors = <String>{location.id};
      String? parentId = location.parentId;
      while (parentId != null) {
        if (!ancestors.add(parentId)) {
          throw const FormatException('Scenario contains a location cycle.');
        }
        parentId = locationsById[parentId]?.parentId;
      }
    }
    if (startingLocationId != null && !locationIds.contains(startingLocationId)) {
      throw const FormatException('Opening references an unknown location.');
    }
    if (startingCharacterIds.any((String id) => !characterIds.contains(id))) {
      throw const FormatException('Opening references an unknown character.');
    }
  }

  bool _hasUniqueNonemptyIds(Iterable<String> ids) {
    final List<String> values = ids.toList();
    return values.every((String id) => id.trim().isNotEmpty) &&
        values.toSet().length == values.length;
  }

  Map<String, Object?> _object(Object? value, String field) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
    throw FormatException('Scenario field "$field" must be an object.');
  }

  String _string(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is String) return value;
    throw FormatException('Scenario field "$field" must be text.');
  }

  String? _optionalString(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value == null || value is String) return value as String?;
    throw FormatException('Scenario field "$field" must be text or null.');
  }

  List<String> _strings(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is List && value.every((Object? item) => item is String)) {
      return value.cast<String>();
    }
    throw FormatException('Scenario field "$field" must be a text list.');
  }

  List<Object?> _list(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is List) return value;
    throw FormatException('Scenario field "$field" must be a list.');
  }
}
