import 'package:game_core/game_core.dart';

/// Persistence boundary for writer-authored world definitions.
abstract interface class WorldRepository {
  Future<List<World>> listWorlds();
  Future<World?> getWorld(String worldId);
  Future<void> createWorld(World world);
  Future<void> updateWorld(World world);
  Future<void> updateWorldDraft(World world);
  Future<void> deleteWorld(String worldId);
  Future<World> duplicateWorld(String worldId);
  Future<void> createLore(String worldId, LoreEntry entry);
  Future<void> updateLore(LoreEntry entry);
  Future<void> deleteLore(String entryId);
  Future<void> createCharacter(String worldId, StoryCharacter character);
  Future<void> updateCharacter(StoryCharacter character);
  Future<void> deleteCharacter(String characterId);
  Future<void> createLocation(String worldId, StoryLocation location);
  Future<void> updateLocation(StoryLocation location);
  Future<void> deleteLocation(String locationId);
}
