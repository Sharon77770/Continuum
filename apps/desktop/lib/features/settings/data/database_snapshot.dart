/// Read-only development information about the active SQLite database.
class DatabaseSnapshot {
  const DatabaseSnapshot({
    required this.databasePath,
    required this.databaseSizeBytes,
    required this.schemaVersion,
    required this.worldCount,
    required this.characterCount,
    required this.loreCount,
    required this.locationCount,
  });

  final String databasePath;
  final int databaseSizeBytes;
  final int schemaVersion;
  final int worldCount;
  final int characterCount;
  final int loreCount;
  final int locationCount;
}
