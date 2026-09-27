import 'package:game_core/game_core.dart';

/// Atomically installs the built-in playable world once for a new database.
abstract interface class FirstRunWorldRepository {
  Future<void> seedDefaultWorldIfFirstRun(World world);
}
