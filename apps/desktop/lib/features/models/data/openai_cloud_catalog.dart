import 'dart:convert';
import 'dart:io';

abstract interface class CloudModelCatalog {
  Future<List<String>> listModels(String apiKey);
}

class OpenAiCloudCatalog implements CloudModelCatalog {
  OpenAiCloudCatalog({HttpClient? client}) : _client = client ?? HttpClient();
  final HttpClient _client;

  @override
  Future<List<String>> listModels(String apiKey) async {
    final HttpClientRequest request = await _client
        .getUrl(Uri.https('api.openai.com', '/v1/models'))
        .timeout(const Duration(seconds: 20));
    request.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${apiKey.trim()}');
    final HttpClientResponse response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(switch (response.statusCode) {
        401 || 403 => 'The provider could not verify this API key.',
        _ => 'The provider could not be reached. Try again later.',
      });
    }
    final Map<String, dynamic> body =
        jsonDecode(await utf8.decoder.bind(response).join())
            as Map<String, dynamic>;
    final List models = body['data'] as List? ?? const [];
    return models
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> model) => model['id'] as String? ?? '')
        .where((String id) =>
            id.isNotEmpty &&
            !RegExp(r'(audio|transcribe|tts|embedding|image|moderation)',
                    caseSensitive: false)
                .hasMatch(id))
        .toList()
      ..sort();
  }

  void close() => _client.close(force: true);
}

class GeminiCloudCatalog implements CloudModelCatalog {
  GeminiCloudCatalog({HttpClient? client}) : _client = client ?? HttpClient();
  final HttpClient _client;

  @override
  Future<List<String>> listModels(String apiKey) async {
    final HttpClientRequest request = await _client
        .getUrl(Uri.https(
            'generativelanguage.googleapis.com', '/v1beta/openai/models'))
        .timeout(const Duration(seconds: 20));
    request.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${apiKey.trim()}');
    final HttpClientResponse response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(switch (response.statusCode) {
        401 || 403 => 'The provider could not verify this API key.',
        _ => 'The provider could not be reached. Try again later.',
      });
    }
    final Map<String, dynamic> body =
        jsonDecode(await utf8.decoder.bind(response).join())
            as Map<String, dynamic>;
    final List models = body['data'] as List? ?? const [];
    return models
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> model) => model['id'] as String? ?? '')
        .where((String id) => id.isNotEmpty)
        .toList()
      ..sort();
  }

  void close() => _client.close(force: true);
}
