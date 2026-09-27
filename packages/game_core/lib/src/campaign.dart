import 'world_state.dart';

/// A persisted playthrough, independent of later edits to its source World.
class Campaign {
  const Campaign({
    required this.id,
    required this.worldId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.lastPlayedAt,
    required this.worldState,
    this.languageCode = 'en',
    this.currentScene,
    this.history = const [],
    this.characterMemory = const {},
  });

  final String id;
  final String worldId;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastPlayedAt;
  final WorldState worldState;
  final String languageCode;
  final SceneTurn? currentScene;
  final List<SceneTurn> history;
  final Map<String, CharacterMemory> characterMemory;

  Campaign copyWith({
    DateTime? updatedAt,
    DateTime? lastPlayedAt,
    WorldState? worldState,
    String? languageCode,
    SceneTurn? currentScene,
    List<SceneTurn>? history,
    Map<String, CharacterMemory>? characterMemory,
  }) =>
      Campaign(
        id: id,
        worldId: worldId,
        name: name,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
        worldState: worldState ?? this.worldState,
        languageCode: languageCode ?? this.languageCode,
        currentScene: currentScene ?? this.currentScene,
        history: history ?? this.history,
        characterMemory: characterMemory ?? this.characterMemory,
      );
}

/// One validated, committed scene in a campaign.
class SceneTurn {
  const SceneTurn({
    required this.id,
    required this.narration,
    required this.dialogue,
    required this.choices,
    required this.playerAction,
    required this.createdAt,
  });
  final String id;
  final String narration;
  final List<SceneDialogue> dialogue;
  final List<String> choices;
  final String? playerAction;
  final DateTime createdAt;
}

class SceneDialogue {
  const SceneDialogue({required this.characterId, required this.text});
  final String characterId;
  final String text;
}

class CharacterMemory {
  const CharacterMemory(
      {this.importantMemories = const [],
      this.knownFacts = const [],
      this.relationship,
      this.currentEmotion,
      this.goals = const [],
      this.recentEvents = const []});
  final List<String> importantMemories;
  final List<String> knownFacts;
  final String? relationship;
  final String? currentEmotion;
  final List<String> goals;
  final List<String> recentEvents;
}
