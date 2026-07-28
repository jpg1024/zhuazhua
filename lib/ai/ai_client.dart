import 'package:dio/dio.dart';

import '../core/config.dart';

class AiClient {
  final AiConfig config;
  final Dio _dio;

  AiClient(this.config)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ));

  bool get ready =>
      config.enabled && config.baseUrl.isNotEmpty && config.model.isNotEmpty;

  /// Calls an OpenAI-compatible /chat/completions endpoint.
  /// Returns null on any failure so callers can fall back to local phrases.
  Future<String?> chat(String systemPrompt, String userPrompt) async {
    if (!ready) return null;
    try {
      final base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
      final url = base.endsWith('/v1')
          ? '$base/chat/completions'
          : '$base/v1/chat/completions';
      final resp = await _dio.post(
        url,
        options: Options(headers: {
          'Content-Type': 'application/json',
          if (config.apiKey.isNotEmpty)
            'Authorization': 'Bearer ${config.apiKey}',
        }),
        data: {
          'model': config.model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          'max_tokens': 120,
          'temperature': 0.9,
        },
      );
      final content =
          resp.data?['choices']?[0]?['message']?['content'] as String?;
      final text = content?.trim();
      if (text == null || text.isEmpty) return null;
      return text.length > 60 ? text.substring(0, 60) : text;
    } catch (_) {
      return null;
    }
  }

  Future<bool> test() async {
    final r = await chat('你是一个测试助手。', '回复"OK"两个字母。');
    return r != null;
  }
}
