import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/model_catalog.dart';

Future<void> verifyModelChecksum(File file, String expectedSha256) async {
  final String actual = (await sha256.bind(file.openRead()).first).toString();
  if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
    throw const FileSystemException('Model checksum verification failed.');
  }
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

abstract interface class ModelDownloader {
  Future<File> download({
    required Uri uri,
    required File destination,
    required String? expectedSha256,
    required void Function(ModelDownloadProgress progress) onProgress,
    required bool Function() isCancelled,
  });
}

class HttpModelDownloader implements ModelDownloader {
  HttpModelDownloader({HttpClient? client}) : _client = client ?? HttpClient();
  final HttpClient _client;

  @override
  Future<File> download({
    required Uri uri,
    required File destination,
    required String? expectedSha256,
    required void Function(ModelDownloadProgress progress) onProgress,
    required bool Function() isCancelled,
  }) async {
    if (uri.scheme != 'https') {
      throw const HttpException('Model downloads require a secure connection.');
    }
    final File partial = File('${destination.path}.part');
    await destination.parent.create(recursive: true);
    IOSink? sink;
    try {
      final HttpClientRequest request =
          await _client.getUrl(uri).timeout(const Duration(seconds: 30));
      final HttpClientResponse response =
          await request.close().timeout(const Duration(minutes: 2));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Model download failed (${response.statusCode}).');
      }
      final int? total =
          response.contentLength > 0 ? response.contentLength : null;
      int received = 0;
      sink = partial.openWrite();
      await for (final List<int> chunk in response) {
        if (isCancelled()) {
          request.abort();
          throw const DownloadCancelled();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(
            ModelDownloadProgress(receivedBytes: received, totalBytes: total));
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (expectedSha256 != null && expectedSha256.isNotEmpty) {
        await verifyModelChecksum(partial, expectedSha256);
      }
      if (isCancelled()) throw const DownloadCancelled();
      if (await destination.exists()) await destination.delete();
      return await partial.rename(destination.path);
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  void close() => _client.close(force: true);
}
