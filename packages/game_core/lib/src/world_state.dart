import 'game_event.dart';

/// Runtime facts owned by a campaign, never by the writer's World definition.
class WorldState {
  const WorldState({
    this.currentLocationId,
    this.presentCharacterIds = const [],
    this.timeDescription,
    this.atmosphere,
    this.relevantObjects = const [],
    this.facts = const {},
    this.events = const [],
    this.turnNumber = 0,
  });
  final String? currentLocationId;
  final List<String> presentCharacterIds;
  final String? timeDescription;
  final String? atmosphere;
  final List<String> relevantObjects;
  final Map<String, String> facts;
  final List<GameEvent> events;
  final int turnNumber;
}
