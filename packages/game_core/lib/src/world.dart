/// Creates collision-resistant, type-prefixed identifiers for world content.
String createStableId(String prefix) =>
    '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_nextId++}';

int _nextId = 0;

/// A writer-created world and its editable encyclopedia definitions.
class World {
  const World({
    required this.id,
    required this.name,
    required this.description,
    required this.genre,
    required this.tone,
    this.rules = const [],
    this.loreEntries = const [],
    this.characters = const [],
    this.locations = const [],
    this.playerDefinition = const PlayerDefinition(),
    this.openingDefinition = const OpeningDefinition(),
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final List<String> genre;
  final List<String> tone;
  final List<String> rules;
  final List<LoreEntry> loreEntries;
  final List<StoryCharacter> characters;
  final List<StoryLocation> locations;
  final PlayerDefinition playerDefinition;
  final OpeningDefinition openingDefinition;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  World copyWith({
    String? name,
    String? description,
    List<String>? genre,
    List<String>? tone,
    List<String>? rules,
    List<LoreEntry>? loreEntries,
    List<StoryCharacter>? characters,
    List<StoryLocation>? locations,
    PlayerDefinition? playerDefinition,
    OpeningDefinition? openingDefinition,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      World(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        genre: genre ?? this.genre,
        tone: tone ?? this.tone,
        rules: rules ?? this.rules,
        loreEntries: loreEntries ?? this.loreEntries,
        characters: characters ?? this.characters,
        locations: locations ?? this.locations,
        playerDefinition: playerDefinition ?? this.playerDefinition,
        openingDefinition: openingDefinition ?? this.openingDefinition,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// Writer-authored protagonist details, kept separate from campaign state.
class PlayerDefinition {
  const PlayerDefinition({
    this.name = '',
    this.description = '',
    this.background = '',
    this.traits = const [],
  });
  final String name;
  final String description;
  final String background;
  final List<String> traits;
}

/// Writer-authored starting conditions for a new campaign.
class OpeningDefinition {
  const OpeningDefinition({
    this.startingLocationId,
    this.startingCharacterIds = const [],
    this.situation = '',
  });
  final String? startingLocationId;
  final List<String> startingCharacterIds;
  final String situation;
}

/// A world article whose category remains extensible user-authored text.
class LoreEntry {
  const LoreEntry({
    required this.id,
    required this.title,
    required this.category,
    required this.content,
    this.worldId = '',
    this.createdAt,
    this.updatedAt,
  });
  final String id;
  final String worldId;
  final String title;
  final String category;
  final String content;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

/// A stable world character definition, separate from runtime state.
class StoryCharacter {
  const StoryCharacter({
    required this.id,
    required this.name,
    required this.role,
    required this.description,
    required this.personality,
    required this.background,
    required this.publicInformation,
    required this.secretInformation,
    this.worldId = '',
    this.appearance = '',
    this.portraitReference,
    this.createdAt,
    this.updatedAt,
  });
  final String id;
  final String worldId;
  final String name;
  final String role;
  final String description;
  final String appearance;
  final String personality;
  final String background;
  final String publicInformation;
  final String secretInformation;
  final String? portraitReference;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

/// A stable location definition in a world hierarchy.
class StoryLocation {
  const StoryLocation({
    required this.id,
    required this.name,
    required this.description,
    this.worldId = '',
    this.parentId,
    this.backgroundReference,
    this.createdAt,
    this.updatedAt,
  });
  final String id;
  final String worldId;
  final String name;
  final String description;
  final String? parentId;
  final String? backgroundReference;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}
