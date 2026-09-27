import 'model_catalog.dart';

abstract interface class RuntimeManager {
  RuntimeSnapshot get snapshot;
  Stream<RuntimeSnapshot> get changes;
  Future<Uri> ensureReady(InstalledModel model,
      {LocalResourceProfile resourceProfile = LocalResourceProfile.balanced});
  Future<void> stop();
  Future<void> dispose();
}
