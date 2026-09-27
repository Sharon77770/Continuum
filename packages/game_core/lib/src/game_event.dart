/// A recorded occurrence in a future campaign history.
class GameEvent {
  const GameEvent({
    required this.id,
    required this.kind,
    required this.description,
  });
  final String id;
  final String kind;
  final String description;
}
