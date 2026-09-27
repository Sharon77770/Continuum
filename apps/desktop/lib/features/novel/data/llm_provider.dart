import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/language_model_settings.dart';

/// Transport contract for compatible chat-completion endpoints.
abstract interface class LlmProvider {
  Future<List<String>> listModels(LanguageModelSettings settings,
      {String? apiKey});
  Stream<String> stream(String prompt, LanguageModelSettings settings,
      {String? apiKey,
      int? maxTokens,
      String? systemPrompt,
      bool jsonMode = false});
  Future<void> healthCheck(LanguageModelSettings settings, {String? apiKey});
  void cancelCurrentRequest();
}

/// OpenAI-compatible `/models` and `/chat/completions` HTTP adapter.
class OpenAiCompatibleProvider implements LlmProvider {
  OpenAiCompatibleProvider({HttpClient? client})
      : _client = client ?? HttpClient();
  final HttpClient _client;
  HttpClientRequest? _activeRequest;
  void close() => _client.close(force: true);

  @override
  void cancelCurrentRequest() {
    final HttpClientRequest? request = _activeRequest;
    if (request != null) {
      request.abort(const LlmException('Generation cancelled.'));
    }
  }

  Uri _uri(String baseUrl, String path) =>
      Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/$path');

  Map<String, String> _headers(String? apiKey) => {
        HttpHeaders.contentTypeHeader: 'application/json',
        if (apiKey != null && apiKey.trim().isNotEmpty)
          HttpHeaders.authorizationHeader: 'Bearer ${apiKey.trim()}',
      };

  @override
  Future<List<String>> listModels(LanguageModelSettings settings,
          {String? apiKey}) =>
      fetchModels(settings, apiKey: apiKey);

  Future<List<String>> fetchModels(LanguageModelSettings settings,
      {String? apiKey}) async {
    final HttpClientRequest request = await _client
        .getUrl(_uri(settings.baseUrl, 'models'))
        .timeout(const Duration(seconds: 20));
    for (final MapEntry<String, String> header in _headers(apiKey).entries) {
      request.headers.set(header.key, header.value);
    }
    final HttpClientResponse response =
        await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LlmException(_friendlyStatus(response.statusCode),
          statusCode: response.statusCode);
    }
    final Map<String, dynamic> decoded =
        jsonDecode(await utf8.decoder.bind(response).join())
            as Map<String, dynamic>;
    return (decoded['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> item) => item['id'] as String)
        .toList();
  }

  @override
  Stream<String> stream(String prompt, LanguageModelSettings settings,
      {String? apiKey,
      int? maxTokens,
      String? systemPrompt,
      bool jsonMode = false}) async* {
    final List<int> body = utf8.encode(jsonEncode({
      'model': settings.model,
      'temperature': settings.temperature,
      'max_tokens': maxTokens ?? (settings.contextLimit ~/ 8).clamp(64, 512),
      'stream': true,
      if (jsonMode) 'response_format': {'type': 'json_object'},
      'messages': [
        if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
          {'role': 'system', 'content': systemPrompt.trim()},
        {'role': 'user', 'content': prompt}
      ],
    }));
    const int maxAttempts = 4;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      bool receivedContent = false;
      try {
        final HttpClientRequest request = await _client
            .postUrl(_uri(settings.baseUrl, 'chat/completions'))
            .timeout(const Duration(seconds: 20));
        _activeRequest = request;
        // Local inference servers often close SSE keep-alive connections between
        // turns. Avoid reusing a stale socket for the next generation request.
        request.persistentConnection = false;
        for (final MapEntry<String, String> header
            in _headers(apiKey).entries) {
          request.headers.set(header.key, header.value);
        }
        request.add(body);
        final HttpClientResponse response =
            await request.close().timeout(const Duration(minutes: 3));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw LlmException(_friendlyStatus(response.statusCode),
              statusCode: response.statusCode);
        }
        await for (final String line in response
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (!line.startsWith('data:')) continue;
          final String payload = line.substring(5).trim();
          if (payload.isEmpty || payload == '[DONE]') continue;
          try {
            final Map<String, dynamic> event =
                jsonDecode(payload) as Map<String, dynamic>;
            final Object? upstreamError = event['error'];
            if (upstreamError is Map) {
              final int? statusCode = _upstreamStatusCode(upstreamError);
              throw LlmException(
                statusCode == null
                    ? 'The language model provider returned an error.'
                    : _friendlyStatus(statusCode),
                statusCode: statusCode,
              );
            }
            final List choices = event['choices'] as List? ?? const [];
            if (choices.isNotEmpty) {
              final Map delta = choices.first['delta'] as Map? ?? const {};
              final Object? content = delta['content'];
              if (content is String) {
                receivedContent = true;
                yield content;
              }
            }
          } on FormatException {
            throw const LlmException(
                'The model returned an invalid streaming response.');
          }
        }
        return;
      } on LlmException catch (error) {
        if (receivedContent ||
            !_isRetryable(error) ||
            attempt == maxAttempts - 1) {
          rethrow;
        }
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      } finally {
        _activeRequest = null;
      }
    }
  }

  bool _isRetryable(LlmException error) =>
      error.statusCode == 408 ||
      error.statusCode == 429 ||
      (error.statusCode != null && error.statusCode! >= 500);

  int? _upstreamStatusCode(Map<Object?, Object?> error) {
    final Object? code = error['code'] ?? error['status'];
    if (code is int) return code;
    final String? codeText = code is String ? code : null;
    final int? numericCode = codeText == null ? null : int.tryParse(codeText);
    if (numericCode != null) return numericCode;
    return switch (codeText?.toUpperCase()) {
      'UNAVAILABLE' => HttpStatus.serviceUnavailable,
      'INTERNAL' => HttpStatus.internalServerError,
      'RESOURCE_EXHAUSTED' => HttpStatus.tooManyRequests,
      'DEADLINE_EXCEEDED' => HttpStatus.gatewayTimeout,
      'UNAUTHENTICATED' => HttpStatus.unauthorized,
      'PERMISSION_DENIED' => HttpStatus.forbidden,
      'SERVICE_UNAVAILABLE' => HttpStatus.serviceUnavailable,
      'API_ERROR' => HttpStatus.internalServerError,
      'RATE_LIMIT_EXCEEDED' => HttpStatus.tooManyRequests,
      'TOO_MANY_REQUESTS' => HttpStatus.tooManyRequests,
      _ => null,
    };
  }

  @override
  Future<void> healthCheck(LanguageModelSettings settings,
      {String? apiKey}) async {
    List<String> models = const <String>[];
    try {
      models = await fetchModels(settings, apiKey: apiKey);
    } on LlmException catch (error) {
      if (error.statusCode != HttpStatus.notFound) rethrow;
    }
    if (settings.model.trim().isEmpty) {
      throw const LlmException('Choose a model name first.');
    }
    if (models.isNotEmpty && !models.contains(settings.model)) {
      throw const LlmException('The selected model is not available.');
    }
    final String result = await stream(
      'Reply with exactly {"ok":true}.',
      settings,
      apiKey: apiKey,
      maxTokens: 64,
    ).timeout(const Duration(minutes: 3)).join();
    if (result.trim().isEmpty) {
      throw const LlmException('The model returned an empty response.');
    }
  }

  String _friendlyStatus(int status) => switch (status) {
        401 || 403 => 'Authentication failed. Check the API key.',
        404 => 'The endpoint or model was not found.',
        413 => 'The request is too large for this endpoint.',
        _ => 'The language model endpoint returned HTTP $status.',
      };
}

/// Human-readable provider failure without credentials or stack details.
class LlmException implements Exception {
  const LlmException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
