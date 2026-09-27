import 'dart:convert';

import 'package:game_core/game_core.dart';

/// Structured proposal returned by a narrative provider before game validation.
class NarrativeResult {
  const NarrativeResult({
    required this.narration,
    required this.dialogue,
    required this.choices,
    this.sceneChanges = const {},
    this.npcChanges = const {},
    this.events = const [],
    this.stateChanges = const {},
    this.memoryUpdates = const {},
  });
  final String narration;
  final List<SceneDialogue> dialogue;
  final List<String> choices;

  /// Untrusted proposed scene fields. The application validates IDs before commit.
  final Map<String, Object?> sceneChanges;
  final Map<String, NpcStateChange> npcChanges;
  final List<NarrativeEvent> events;
  final Map<String, String> stateChanges;
  final Map<String, List<String>> memoryUpdates;

  /// Parses version 1 JSON and rejects unknown speakers and malformed fields.
  factory NarrativeResult.parse(String raw, Set<String> knownCharacterIds,
      {int minimumChoices = 2, bool ignoreDialogue = false}) {
    final String cleaned = raw
        .trim()
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
    final String jsonObject = _firstCompleteJsonObject(cleaned) ?? cleaned;
    final Object? decoded = jsonDecode(jsonObject);
    if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
      throw const FormatException('Unsupported narrative schema.');
    }
    final Object? rawNarration = decoded['narration'];
    final Object? rawDialogue = decoded['dialogue'];
    final Object? rawChoices = decoded['choices'];
    if (rawNarration is! String || rawNarration.trim().isEmpty) {
      throw const FormatException('Narrative narration is missing or empty.');
    }
    if (rawDialogue != null && rawDialogue is! List) {
      throw const FormatException(
          'Narrative dialogue must be an array when provided.');
    }
    if (rawChoices is! List ||
        rawChoices.length < minimumChoices ||
        rawChoices.length > 5) {
      throw FormatException(
          'Narrative choices must contain $minimumChoices to 5 items; received ${rawChoices is List ? rawChoices.length : 'a non-array value'}.');
    }
    final List<SceneDialogue> dialogue = ignoreDialogue || rawDialogue == null
        ? const <SceneDialogue>[]
        : (rawDialogue as List).map((Object? item) {
            if (item is! Map<String, dynamic> ||
                item['characterId'] is! String ||
                item['text'] is! String ||
                !knownCharacterIds.contains(item['characterId'])) {
              throw const FormatException(
                  'Narrative contains an unknown speaker.');
            }
            return SceneDialogue(
                characterId: item['characterId']! as String,
                text: item['text']! as String);
          }).toList();
    final List<String> choices = rawChoices.map((Object? item) {
      if (item is! String || item.trim().isEmpty)
        throw const FormatException('Narrative choice is invalid.');
      return item.trim();
    }).toList();
    final Object? rawSceneChanges = decoded['sceneChanges'];
    if (rawSceneChanges != null && rawSceneChanges is! Map<String, dynamic>) {
      throw const FormatException('Scene changes are invalid.');
    }
    final Map<String, Object?> sceneChanges = rawSceneChanges == null
        ? const {}
        : Map<String, Object?>.from(rawSceneChanges as Map);
    final Object? locationId = sceneChanges['locationId'];
    final Object? characterIds = sceneChanges['presentCharacterIds'];
    final Object? time = sceneChanges['timeDescription'];
    final Object? atmosphere = sceneChanges['atmosphere'];
    final Object? objects = sceneChanges['relevantObjects'];
    if ((locationId != null && locationId is! String) ||
        (characterIds != null &&
            (characterIds is! List ||
                characterIds.any((Object? id) => id is! String))) ||
        (time != null && time is! String) ||
        (atmosphere != null && atmosphere is! String) ||
        (objects != null &&
            (objects is! List ||
                objects.any((Object? item) => item is! String)))) {
      throw const FormatException('Scene changes are invalid.');
    }
    if (sceneChanges.keys.any((String key) => !const {
          'locationId',
          'presentCharacterIds',
          'timeDescription',
          'atmosphere',
          'relevantObjects'
        }.contains(key))) {
      throw const FormatException('Scene changes contain unsupported fields.');
    }
    final Map<String, NpcStateChange> npcChanges = <String, NpcStateChange>{};
    final Object? rawNpcChanges = decoded['npcChanges'];
    if (rawNpcChanges != null && rawNpcChanges is! List) {
      throw const FormatException('NPC changes are invalid.');
    }
    for (final Object? raw in rawNpcChanges as List? ?? const <Object?>[]) {
      if (raw is! Map<String, dynamic> ||
          raw['characterId'] is! String ||
          !knownCharacterIds.contains(raw['characterId'])) {
        continue;
      }
      final String id = raw['characterId']! as String;
      final Object? relationship = raw['relationship'];
      final Object? emotion = raw['currentEmotion'];
      final Object? goals = raw['goals'];
      final Object? recentEvents = raw['recentEvents'];
      if ((relationship != null && relationship is! String) ||
          (emotion != null && emotion is! String) ||
          (goals != null &&
              (goals is! List ||
                  goals.any((Object? item) => item is! String))) ||
          (recentEvents != null &&
              (recentEvents is! List ||
                  recentEvents.any((Object? item) => item is! String))) ||
          npcChanges.containsKey(id)) {
        // NPC updates are optional, untrusted metadata. Drop a malformed or
        // duplicate update without discarding otherwise usable narration.
        continue;
      }
      npcChanges[id] = NpcStateChange(
        relationship: relationship as String?,
        currentEmotion: emotion as String?,
        goals: (goals as List?)?.cast<String>() ?? const <String>[],
        recentEvents:
            (recentEvents as List?)?.cast<String>() ?? const <String>[],
      );
    }
    final Map<String, String> stateChanges =
        _stringMap(decoded['stateChanges']);
    final List<NarrativeEvent> events = <NarrativeEvent>[];
    final Object? rawEvents = decoded['events'];
    if (rawEvents is List) {
      for (final Object? item in rawEvents) {
        if (item is! Map<String, dynamic> ||
            item['kind'] is! String ||
            item['description'] is! String ||
            (item['kind'] as String).trim().isEmpty ||
            (item['description'] as String).trim().isEmpty) {
          throw const FormatException('Narrative event is invalid.');
        }
        events.add(NarrativeEvent(
            kind: (item['kind'] as String).trim(),
            description: (item['description'] as String).trim()));
      }
    }
    final Map<String, List<String>> memoryUpdates = <String, List<String>>{};
    final Object? rawMemory = decoded['memoryUpdates'];
    if (rawMemory is List) {
      for (final Object? item in rawMemory) {
        if (item is! Map<String, dynamic> ||
            item['characterId'] is! String ||
            !knownCharacterIds.contains(item['characterId']) ||
            item['summary'] is! String) {
          continue;
        }
        final String id = item['characterId']! as String;
        memoryUpdates[id] = [
          ...?memoryUpdates[id],
          (item['summary']! as String).trim()
        ];
      }
    }
    return NarrativeResult(
        narration: rawNarration.trim(),
        dialogue: dialogue,
        choices: choices,
        sceneChanges: sceneChanges,
        npcChanges: npcChanges,
        events: events,
        stateChanges: stateChanges,
        memoryUpdates: memoryUpdates);
  }
}

String? _firstCompleteJsonObject(String value) {
  final int start = value.indexOf('{');
  if (start < 0) return null;
  int depth = 0;
  bool inString = false;
  bool escaped = false;
  for (int index = start; index < value.length; index++) {
    final String character = value[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (character.codeUnitAt(0) == 0x5C) {
        escaped = true;
      } else if (character == '"') {
        inString = false;
      }
      continue;
    }
    if (character == '"') {
      inString = true;
    } else if (character == '{') {
      depth++;
    } else if (character == '}') {
      depth--;
      if (depth == 0) return value.substring(start, index + 1);
    }
  }
  return null;
}

/// Untrusted proposal for one present NPC's persistent social/motivational state.
class NpcStateChange {
  const NpcStateChange({
    this.relationship,
    this.currentEmotion,
    this.goals = const [],
    this.recentEvents = const [],
  });
  final String? relationship;
  final String? currentEmotion;
  final List<String> goals;
  final List<String> recentEvents;
}

Map<String, String> _stringMap(Object? value) {
  if (value == null) return const {};
  if (value is! Map<String, dynamic>)
    throw const FormatException('State changes are invalid.');
  if (value.values.any((Object? item) => item is! String))
    throw const FormatException('State changes are invalid.');
  return value
      .map((String key, Object? item) => MapEntry(key, item! as String));
}

/// A bounded prompt separated into inspectable, deterministic context sections.
class NarrativeContext {
  const NarrativeContext(this.sections);
  final Map<String, String> sections;

  String get systemPrompt => sections['System'] ?? '';

  String get userPrompt => sections.entries
      .where((MapEntry<String, String> entry) => entry.key != 'System')
      .map((MapEntry<String, String> entry) => '[${entry.key}]\n${entry.value}')
      .join('\n\n');

  String get prompt => sections.entries
      .map((MapEntry<String, String> entry) => '[${entry.key}]\n${entry.value}')
      .join('\n\n');
  int get estimatedTokens => _estimateTokens(prompt);
}

/// Conservative multilingual estimate: non-ASCII characters count as two tokens.
int _estimateTokens(String text) {
  final int nonAsciiCharacters =
      RegExp(r'[^\x00-\x7F]').allMatches(text).length;
  final int asciiCharacters = text.length - nonAsciiCharacters;
  return (asciiCharacters / 4 + nonAsciiCharacters * 2).ceil();
}

/// An untrusted event proposal; the application assigns its ID at commit.
class NarrativeEvent {
  const NarrativeEvent({required this.kind, required this.description});
  final String kind;
  final String description;
}

/// Selects only current scene, active characters, bounded lore and recent turns.
class ContextBuilder {
  const ContextBuilder({this.tokenLimit = 4096});
  final int tokenLimit;

  NarrativeContext build(
      {required World world,
      required Campaign campaign,
      required String playerAction,
      bool isOpening = false}) {
    final List<StoryCharacter> activeCharacters = world.characters
        .where((StoryCharacter character) =>
            campaign.worldState.presentCharacterIds.contains(character.id))
        .toList();
    final Map<String, String> sections = <String, String>{
      'System': _systemInstructions(
          isOpening,
          world.playerDefinition.name,
          world.locations
                  .where((StoryLocation item) =>
                      item.id == campaign.worldState.currentLocationId)
                  .map((StoryLocation item) => item.name)
                  .firstOrNull ??
              '',
          activeCharacters
              .map((StoryCharacter character) => character.id)
              .toList()),
      'World': '${world.name}\n${world.description}',
      'Player':
          '${world.playerDefinition.name}: ${world.playerDefinition.description}\nBackground: ${world.playerDefinition.background}\nTraits: ${world.playerDefinition.traits.join(', ')}',
      'Rules': world.rules.join('\n'),
      'Scene State':
          'Turn ${campaign.worldState.turnNumber}\nTime: ${campaign.worldState.timeDescription ?? 'unspecified'}\nAtmosphere: ${campaign.worldState.atmosphere ?? 'unspecified'}\nRelevant objects: ${campaign.worldState.relevantObjects.join('; ')}\nFacts: ${campaign.worldState.facts.entries.map((MapEntry<String, String> entry) => '${entry.key}=${entry.value}').join('; ')}\nRecent events: ${campaign.worldState.events.reversed.take(8).map((GameEvent event) => event.description).join('; ')}',
      'Lore': world.loreEntries
          .take(12)
          .map((LoreEntry item) => '${item.title}: ${item.content}')
          .join('\n'),
      'Location': world.locations
              .where((StoryLocation item) =>
                  item.id == campaign.worldState.currentLocationId)
              .map((StoryLocation item) => '${item.name}: ${item.description}')
              .firstOrNull ??
          '',
      'World location IDs': world.locations
          .map((StoryLocation item) => '${item.id}=${item.name}')
          .join('; '),
      'Characters': activeCharacters
          .map((StoryCharacter item) =>
              '${item.id} ${item.name} (${item.role}): ${item.description}\nBackground: ${item.background}\nPersonality and speaking voice: ${item.personality}\nPublic: ${item.publicInformation}\n[GM ONLY; never reveal directly or let this character know without a plausible discovery] ${item.secretInformation}\nKnown facts for this character: ${(campaign.characterMemory[item.id]?.knownFacts ?? const <String>[]).join('; ')}')
          .join('\n\n'),
      'Memory': campaign.characterMemory.entries
          .where((MapEntry<String, CharacterMemory> item) => activeCharacters
              .any((StoryCharacter character) => character.id == item.key))
          .map((MapEntry<String, CharacterMemory> item) =>
              '${item.key}: relationship=${item.value.relationship ?? 'unknown'}; current emotion=${item.value.currentEmotion ?? 'unknown'}; goals=${item.value.goals.join('; ')}; recent events=${item.value.recentEvents.join('; ')}; important memories=${item.value.importantMemories.join('; ')}')
          .join('\n'),
      'Recent History': campaign.history.reversed
          .take(8)
          .toList()
          .reversed
          .map((SceneTurn item) =>
              '${item.playerAction == null ? '' : 'Player action: ${item.playerAction}\n'}${item.narration}\n${item.dialogue.map((SceneDialogue line) => '${line.characterId}: ${line.text}').join('\n')}\nChoices already offered: ${item.choices.join('; ')}')
          .join('\n\n'),
      isOpening ? 'Opening Situation' : 'Player Intent': playerAction,
    };
    for (final String key in ['Lore', 'Recent History', 'Memory']) {
      while (_estimate(sections) > tokenLimit && sections[key]!.isNotEmpty) {
        sections[key] =
            sections[key]!.substring(0, (sections[key]!.length * .75).floor());
      }
    }
    if (_estimate(sections) > tokenLimit)
      throw StateError('Current world context exceeds the configured limit.');
    return NarrativeContext(Map.unmodifiable(sections));
  }

  int _estimate(Map<String, String> sections) => _estimateTokens(sections
      .entries
      .map((MapEntry<String, String> item) => '[${item.key}]\n${item.value}')
      .join('\n\n'));
}

String _systemInstructions(bool isOpening, String playerName,
    String locationName, List<String> activeCharacterIds) {
  final String dialogueRules = activeCharacterIds.isEmpty
      ? 'No NPCs are present in this scene. Use narration for environmental results and solitary observation; dialogue may be empty. Do not invent a present character.'
      : 'Dialogue is optional; an empty dialogue array is valid. Add NPC dialogue only when it naturally advances the scene, and use only these active character IDs: ${activeCharacterIds.join(', ')}.';
  final String base =
      '''You are the Game Master resolving a living world, not a chatbot continuing prose.
Treat authored world facts, committed campaign facts, and the current scene as canon. Resolve a bounded turn: handle the immediate intent, show its observable consequence and at most one relevant reaction, then return control. Do not complete a chain of future events. For ordinary turns, keep narration to 1-3 concise sentences and dialogue to at most 2 short lines; reserve longer prose for openings and scene transitions.
Never repeat or paraphrase the player's action as narration. Show what changes because of it. Never invent the player's dialogue, voluntary actions, thoughts, feelings, beliefs, consent, refusal, or decisions. Describe only observable details about the player.
Each NPC may use only listed known facts and information they plausibly perceive. GM-only secrets are not known to an NPC until discovered in play. Preserve each NPC's personality and voice; dialogue should sound spoken, concise, and distinct from narration.
Use natural, understated prose in the requested language. Avoid repeated gestures, stock emotional phrases, recap, exposition dumps, translation-like phrasing, and game/AI meta language. Do not repeat scene details unless something changed.
Choices are concrete, plausible actions available in this exact scene. They are suggestions, never mandatory branches or answers. Do not use generic follow-up prompts. State changes record only concrete, observable, durable facts. Keep short exchanges short. Omit unchanged scene/NPC fields, and use empty arrays/objects when there are no updates. A risky declared action may fail or have a partial consequence; do not assume success.
Return one compact JSON object, no markdown. Required fields only: schemaVersion:1, nonempty narration, and choices array with 2 to 5 nonempty strings. The dialogue array of {characterId,text} is optional and may be empty. Include events, stateChanges, memoryUpdates, npcChanges, and sceneChanges only when there is a meaningful update; otherwise omit those keys. Keep update arrays short and omit unchanged fields. npcChanges may contain only durable, observable changes for present characters; never give an NPC unlearned knowledge. sceneChanges accepts locationId, presentCharacterIds, timeDescription, atmosphere, relevantObjects. locationId must be one of the exact authored location IDs listed in context, never a display name; omit it unless the scene changes. Do not add unsupported fields.
$dialogueRules''';
  if (!isOpening) return base;
  return '''$base
This is the opening, not a response to a player action. In the first two sentences, identify the player by the exact authored name "$playerName", name the current location "$locationName", and establish why they are there using their background. Then ground the moment with time, atmosphere, visible people or objects, and one immediate situation or hook through observable details. Do not start in an unexplained crisis or dump encyclopedia lore. End at a calm, playable moment without deciding what the player does.''';
}

/// Lists missing playable authoring fields before campaign creation.
List<String> playableWorldIssues(World world) {
  final List<String> issues = <String>[];
  if (world.playerDefinition.name.trim().isEmpty) issues.add('Player name');
  if (world.locations.every((StoryLocation item) =>
      item.id != world.openingDefinition.startingLocationId))
    issues.add('Starting location');
  if (world.openingDefinition.situation.trim().isEmpty)
    issues.add('Opening situation');
  return issues;
}
