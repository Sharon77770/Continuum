import 'dart:io';

import 'package:continuum_desktop/features/models/data/model_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('model checksum verification accepts matching content', () async {
    final Directory temp =
        await Directory.systemTemp.createTemp('continuum-model-hash-');
    addTearDown(() => temp.delete(recursive: true));
    final File file = File('${temp.path}/model.gguf');
    await file.writeAsString('valid model bytes');
    final String expected = sha256.convert(await file.readAsBytes()).toString();
    await expectLater(verifyModelChecksum(file, expected), completes);
  });

  test('checksum mismatch fails verification', () async {
    final Directory temp =
        await Directory.systemTemp.createTemp('continuum-model-hash-');
    addTearDown(() => temp.delete(recursive: true));
    final File file = File('${temp.path}/model.gguf');
    await file.writeAsString('tampered model bytes');
    await expectLater(
      verifyModelChecksum(file, '0' * 64),
      throwsA(isA<FileSystemException>().having(
          (FileSystemException error) => error.message,
          'message',
          contains('checksum'))),
    );
  });
}
