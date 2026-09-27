import 'dart:io';

import 'package:continuum_desktop/features/models/data/model_manager_repository.dart';
import 'package:continuum_desktop/features/models/domain/model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory modelsDirectory;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('continuum-model-repository-');
    modelsDirectory = Directory('${temporaryDirectory.path}/models');
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test('restores installed models and Story Model selection from manifest',
      () async {
    final File modelFile = File('${modelsDirectory.path}/story.gguf');
    await modelFile.parent.create(recursive: true);
    await modelFile.writeAsBytes(const <int>[71, 71, 85, 70]);
    final InstalledModel model = InstalledModel(
      id: 'local-story',
      displayName: 'Local Story',
      fileName: 'story.gguf',
      path: modelFile.path,
      sizeBytes: 4,
      source: ModelSource.localImport,
      repository: 'Local import',
      license: 'Unknown',
      qualityClass: ModelQuality.balanced,
      speedClass: ModelSpeed.balanced,
      contextSize: 4096,
      sha256: 'test-hash',
      importedAt: DateTime.utc(2026),
    );
    final JsonModelManagerRepository firstRun =
        JsonModelManagerRepository(modelsDirectory);
    await firstRun.saveInstalled(model);
    await firstRun.saveSelection(const ModelSelection(
      kind: ModelProviderKind.local,
      modelId: 'local-story',
      displayName: 'Local Story',
    ));
    expect(await firstRun.getLocalResourceProfile(),
        LocalResourceProfile.balanced);
    await firstRun.saveLocalResourceProfile(LocalResourceProfile.performance);

    final JsonModelManagerRepository afterRestart =
        JsonModelManagerRepository(modelsDirectory);
    expect((await afterRestart.listInstalled()).map((item) => item.id),
        ['local-story']);
    expect((await afterRestart.getSelection())?.modelId, 'local-story');
    expect(await afterRestart.getLocalResourceProfile(),
        LocalResourceProfile.performance);

    await afterRestart.removeInstalled('local-story');
    expect(await modelFile.exists(), isFalse);
    expect(await afterRestart.getSelection(), isNull);
  });
}
