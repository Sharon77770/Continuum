import 'dart:io';

import 'model_catalog.dart';

abstract interface class DeviceProbe {
  Future<DeviceCapabilities> detect({required Directory modelsDirectory});
}

abstract interface class ModelManagerRepository {
  Future<List<InstalledModel>> listInstalled();
  Future<void> saveInstalled(InstalledModel model);
  Future<void> removeInstalled(String modelId);
  Future<ModelSelection?> getSelection();
  Future<void> saveSelection(ModelSelection selection);
  Future<void> clearSelection();
  Future<LocalResourceProfile> getLocalResourceProfile();
  Future<void> saveLocalResourceProfile(LocalResourceProfile profile);
}

abstract interface class SecretStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}
