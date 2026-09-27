import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../domain/model_catalog.dart';
import '../domain/model_manager_repository.dart' as contract;

class JsonModelManagerRepository implements contract.ModelManagerRepository {
  JsonModelManagerRepository(this.modelsDirectory);

  final Directory modelsDirectory;
  File get _manifest => File(path.join(modelsDirectory.path, 'index.json'));

  Future<Map<String, Object?>> _read() async {
    if (!await _manifest.exists()) {
      return <String, Object?>{'models': <Object?>[]};
    }
    try {
      return jsonDecode(await _manifest.readAsString()) as Map<String, Object?>;
    } on FormatException {
      return <String, Object?>{'models': <Object?>[]};
    }
  }

  Future<void> _write(Map<String, Object?> json) async {
    await modelsDirectory.create(recursive: true);
    await _manifest.writeAsString(
        const JsonEncoder.withIndent('  ').convert(json),
        flush: true);
  }

  @override
  Future<List<InstalledModel>> listInstalled() async {
    final Map<String, Object?> data = await _read();
    final List values = data['models'] as List? ?? const [];
    final List<InstalledModel> models = <InstalledModel>[];
    for (final Object? value in values) {
      if (value is! Map) continue;
      try {
        final InstalledModel model =
            InstalledModel.fromJson(Map<String, Object?>.from(value));
        if (await File(model.path).exists()) models.add(model);
      } catch (_) {
        continue;
      }
    }
    return models;
  }

  @override
  Future<void> saveInstalled(InstalledModel model) async {
    final Map<String, Object?> data = await _read();
    final List<InstalledModel> existing = await listInstalled();
    await _write(<String, Object?>{
      ...data,
      'models': <Object?>[
        for (final InstalledModel item in existing)
          if (item.id != model.id) item.toJson(),
        model.toJson(),
      ],
    });
  }

  @override
  Future<void> removeInstalled(String modelId) async {
    final List<InstalledModel> models = await listInstalled();
    final InstalledModel? removed =
        models.where((InstalledModel model) => model.id == modelId).firstOrNull;
    if (removed != null && path.isWithin(modelsDirectory.path, removed.path)) {
      final File file = File(removed.path);
      if (await file.exists()) await file.delete();
    }
    final Map<String, Object?> data = await _read();
    await _write(<String, Object?>{
      ...data,
      'models': <Object?>[
        for (final InstalledModel model in models)
          if (model.id != modelId) model.toJson(),
      ],
      if ((await getSelection())?.modelId == modelId) 'selection': null,
    });
  }

  @override
  Future<ModelSelection?> getSelection() async {
    final Object? raw = (await _read())['selection'];
    if (raw is! Map) return null;
    try {
      return ModelSelection.fromJson(Map<String, Object?>.from(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveSelection(ModelSelection selection) async => _write({
        ...await _read(),
        'selection': selection.toJson(),
      });

  @override
  Future<void> clearSelection() async => _write({
        ...await _read(),
        'selection': null,
      });

  @override
  Future<LocalResourceProfile> getLocalResourceProfile() async {
    final Object? raw = (await _read())['localResourceProfile'];
    if (raw is! String) return LocalResourceProfile.balanced;
    return LocalResourceProfile.values
            .where((LocalResourceProfile value) => value.name == raw)
            .firstOrNull ??
        LocalResourceProfile.balanced;
  }

  @override
  Future<void> saveLocalResourceProfile(LocalResourceProfile profile) async =>
      _write({...await _read(), 'localResourceProfile': profile.name});
}
