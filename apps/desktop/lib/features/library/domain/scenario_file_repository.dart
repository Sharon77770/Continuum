import 'package:game_core/game_core.dart';

/// Reads and writes scenario files through the platform file picker.
abstract interface class ScenarioFileRepository {
  Future<World?> importScenario();
  Future<bool> exportScenario(World world);
}
