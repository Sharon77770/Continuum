import 'dart:convert';
import 'dart:io';

import '../domain/model_catalog.dart';

class DiscoveredModelFile {
  const DiscoveredModelFile({
    required this.repository,
    required this.file,
    required this.sizeBytes,
    required this.sha256,
    required this.license,
    required this.downloadUrl,
    required this.quantization,
  });

  final String repository;
  final String file;
  final int sizeBytes;
  final String? sha256;
  final String license;
  final Uri downloadUrl;
  final String? quantization;

  ModelDescriptor descriptor({ModelQuality quality = ModelQuality.balanced}) =>
      ModelDescriptor(
        id: '$repository::$file',
        displayName: repository.split('/').last,
        description: 'Community GGUF model. Review its model card and license.',
        source: ModelSource.huggingFace,
        repository: repository,
        file: file,
        downloadUrl: downloadUrl,
        downloadSize: sizeBytes,
        approximateMemoryRequirement: (sizeBytes * 1.35).ceil(),
        qualityClass: quality,
        speedClass: ModelSpeed.balanced,
        recommendedFor: 'Check memory needs in the model card',
        license: license,
        licenseUrl: Uri.parse('https://huggingface.co/$repository'),
        sha256: sha256,
        quantization: quantization,
      );
}

class DiscoveredModel {
  const DiscoveredModel({required this.repository, required this.variants});
  final String repository;
  final List<DiscoveredModelFile> variants;

  DiscoveredModelFile fileFor(ModelQuality quality) {
    final List<DiscoveredModelFile> sorted = [...variants]
      ..sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
    if (quality == ModelQuality.fast) return sorted.first;
    if (quality == ModelQuality.higherQuality) return sorted.last;
    return sorted
            .where((DiscoveredModelFile file) => file.quantization == 'Q4_K_M')
            .firstOrNull ??
        sorted[sorted.length ~/ 2];
  }
}

class HuggingFaceCatalog {
  HuggingFaceCatalog({HttpClient? client}) : _client = client ?? HttpClient();
  final HttpClient _client;

  Future<List<DiscoveredModel>> search(String query) async {
    final Uri searchUri = Uri.https('huggingface.co', '/api/models', {
      'search': query.trim(),
      'filter': 'gguf',
      'pipeline_tag': 'text-generation',
      'sort': 'downloads',
      'direction': '-1',
      'limit': '20',
    });
    final List<dynamic> models = await _getJson(searchUri) as List<dynamic>;
    final Map<String, List<DiscoveredModelFile>> grouped = {};
    for (final dynamic item in models.take(12)) {
      if (item is! Map<String, dynamic>) continue;
      final String? repo = item['id'] as String?;
      if (repo == null || !repo.contains('/')) continue;
      final Uri detailUri =
          Uri.https('huggingface.co', '/api/models/$repo', {'blobs': 'true'});
      final Map<String, dynamic> detail =
          await _getJson(detailUri) as Map<String, dynamic>;
      final String license =
          (detail['cardData'] as Map?)?['license'] as String? ?? 'Unknown';
      final List siblings = detail['siblings'] as List? ?? const [];
      for (final dynamic sibling in siblings) {
        if (sibling is! Map<String, dynamic>) continue;
        final String file = sibling['rfilename'] as String? ?? '';
        if (!file.toLowerCase().endsWith('.gguf') ||
            RegExp(r'-\d{5}-of-\d{5}\.gguf$', caseSensitive: false)
                .hasMatch(file)) {
          continue;
        }
        final Object? rawSize =
            sibling['size'] ?? (sibling['lfs'] as Map?)?['size'];
        final int size = rawSize is num ? rawSize.toInt() : 0;
        if (size <= 0) continue;
        final String? hash = (sibling['lfs'] as Map?)?['sha256'] as String?;
        grouped
            .putIfAbsent(repo, () => <DiscoveredModelFile>[])
            .add(DiscoveredModelFile(
              repository: repo,
              file: file,
              sizeBytes: size,
              sha256: hash,
              license: license,
              downloadUrl:
                  Uri.https('huggingface.co', '/$repo/resolve/main/$file'),
              quantization: _quantization(file),
            ));
      }
    }
    final List<DiscoveredModel> results = [
      for (final MapEntry<String, List<DiscoveredModelFile>> entry
          in grouped.entries)
        DiscoveredModel(
          repository: entry.key,
          variants: entry.value
            ..sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes)),
        ),
    ];
    return results;
  }

  Future<dynamic> _getJson(Uri uri) async {
    final HttpClientRequest request =
        await _client.getUrl(uri).timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final HttpClientResponse response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Model search failed (${response.statusCode}).',
          uri: uri);
    }
    return jsonDecode(await utf8.decoder.bind(response).join());
  }

  String? _quantization(String file) {
    final RegExpMatch? match =
        RegExp(r'(Q\d(?:_K_[A-Z]+|_[A-Z]+)?|IQ\d_[A-Z]+)', caseSensitive: false)
            .firstMatch(file);
    return match?.group(0)?.toUpperCase();
  }

  void close() => _client.close(force: true);
}
