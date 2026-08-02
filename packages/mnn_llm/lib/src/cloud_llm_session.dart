// CloudLlmSession: streams completions from cloud LLM providers via HTTP.
//
// Goal
// ----
// Mirror the MnnLlmSession API so the rest of the app (ChatPage, AgentRuntime)
// can treat cloud and on-device LLMs interchangeably:
//
//   await for (final chunk in session.chatStream('hello')) { print(chunk); }
//
// Supported providers
// -------------------
// Any OpenAI-compatible /v1/chat/completions endpoint (streaming SSE):
//   - OpenAI        (https://api.openai.com/v1/chat/completions)
//   - DeepSeek      (https://api.deepseek.com/v1/chat/completions)
//   - 通义千问 DashScope  OpenAI-compatible mode
//                      (https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions)
//   - 豆包 / 字节跳动火山方舟   OpenAI-compatible
//   - Groq          (https://api.groq.com/openai/v1/chat/completions)
//   - Ollama        (http://localhost:11434/v1/chat/completions, 本地代理)
//   - 自定义 URL    (任意 OpenAI 兼容端点)
//
// Anthropic Claude (Messages API) has a different shape; we provide a thin
// adapter that converts the OpenAI streaming schema to the Anthropic
// streaming schema (event: content_block_delta → data: {delta.text}).
//
// Why pure-Dart http + not a third-party SDK?
// ------------------------------------------
// - No extra dependency
// - Works on every Flutter platform (no platform-specific build flags)
// - Streamed via chunked transfer + manual SSE parser
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Identifies a cloud provider. The URL is a default and can be overridden.
enum CloudProvider {
  openai,
  deepseek,
  qwenDashScope, // 通义千问 DashScope OpenAI-compatible
  doubao, // 豆包 / 字节跳动火山方舟
  groq,
  ollama, // Ollama 本地（127.0.0.1:11434）
  anthropic, // Claude Messages API
  custom, // 任意 OpenAI 兼容 URL
}

/// Configuration for a cloud LLM session.
class CloudLlmConfig {
  CloudLlmConfig({
    required this.provider,
    required this.apiKey,
    required this.model,
    this.baseUrl,
    this.systemPrompt,
    this.temperature = 0.7,
    this.maxTokens = 2048,
    this.topP = 0.9,
    this.requestTimeoutSeconds = 120,
  });

  final CloudProvider provider;
  final String apiKey;
  final String model;

  /// Optional override for the API base URL. When null we use a sensible
  /// default based on [provider].
  final String? baseUrl;
  final String? systemPrompt;
  final double temperature;
  final int maxTokens;
  final double topP;
  final int requestTimeoutSeconds;

  /// Built-in defaults for the public providers. The user can override via
  /// [baseUrl] when they proxy through a gateway or self-host.
  String resolveBaseUrl() {
    if (baseUrl != null && baseUrl!.isNotEmpty) return baseUrl!;
    switch (provider) {
      case CloudProvider.openai:
        return 'https://api.openai.com/v1';
      case CloudProvider.deepseek:
        return 'https://api.deepseek.com/v1';
      case CloudProvider.qwenDashScope:
        return 'https://dashscope.aliyuncs.com/compatible-mode/v1';
      case CloudProvider.doubao:
        return 'https://ark.cn-beijing.volces.com/api/v3';
      case CloudProvider.groq:
        return 'https://api.groq.com/openai/v1';
      case CloudProvider.ollama:
        return 'http://localhost:11434/v1';
      case CloudProvider.anthropic:
        return 'https://api.anthropic.com';
      case CloudProvider.custom:
        return baseUrl ?? '';
    }
  }
}

/// Streams chat completions from a cloud LLM.
class CloudLlmSession {
  CloudLlmSession._(this._config);

  final CloudLlmConfig _config;
  bool _disposed = false;
  HttpClient? _activeClient;
  bool _cancelRequested = false;

  static Future<CloudLlmSession> create(CloudLlmConfig config) async {
    if (config.apiKey.isEmpty &&
        config.provider != CloudProvider.ollama) {
      throw ArgumentError(
          'API key is required for ${config.provider.name}');
    }
    return CloudLlmSession._(config);
  }

  /// Start a streaming chat. Emits text chunks as they arrive. Closes when
  /// the upstream SSE stream ends or [stop] is called.
  Stream<String> chatStream(String prompt) {
    if (_disposed) {
      throw StateError('CloudLlmSession has been disposed');
    }
    _cancelRequested = false;
    final controller = StreamController<String>(sync: true);
    // Run the network call asynchronously.
    _runChat(prompt, controller);
    return controller.stream;
  }

  /// Request cancellation. Safe to call multiple times.
  void stop() {
    _cancelRequested = true;
    try {
      _activeClient?.close(force: true);
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelRequested = true;
    try {
      _activeClient?.close(force: true);
    } catch (_) {}
  }

  // ---- Internal ------------------------------------------------------

  Future<void> _runChat(
      String prompt, StreamController<String> controller) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    _activeClient = client;
    try {
      if (_config.provider == CloudProvider.anthropic) {
        await _runAnthropic(client, prompt, controller);
      } else {
        await _runOpenAiCompat(client, prompt, controller);
      }
    } catch (e, st) {
      if (!_cancelRequested) {
        controller.addError(e, st);
      }
    } finally {
      _activeClient = null;
      try {
        client.close(force: true);
      } catch (_) {}
      await controller.close();
    }
  }

  Future<void> _runOpenAiCompat(
    HttpClient client,
    String prompt,
    StreamController<String> controller,
  ) async {
    final base = _config.resolveBaseUrl();
    final uri = Uri.parse('$base/chat/completions');
    final messages = <Map<String, dynamic>>[];
    if (_config.systemPrompt != null && _config.systemPrompt!.isNotEmpty) {
      messages.add({'role': 'system', 'content': _config.systemPrompt});
    }
    messages.add({'role': 'user', 'content': prompt});

    final body = jsonEncode({
      'model': _config.model,
      'messages': messages,
      'stream': true,
      'temperature': _config.temperature,
      'max_tokens': _config.maxTokens,
      'top_p': _config.topP,
    });

    final req = await client.postUrl(uri);
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    if (_config.apiKey.isNotEmpty) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${_config.apiKey}');
    }
    req.headers.set('Accept-Encoding', 'identity');
    req.add(utf8.encode(body));

    final resp = await req.close();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final err = await resp.transform(utf8.decoder).join();
      throw HttpException(
          'Cloud LLM HTTP ${resp.statusCode}: $err',
          uri: uri);
    }

    // Parse SSE: lines start with "data: ", separated by \n\n.
    // "data: [DONE]" signals end of stream.
    await for (final line
        in resp.transform(utf8.decoder).transform(const LineSplitter())) {
      if (_cancelRequested) break;
      if (line.isEmpty || line.startsWith(':')) continue;
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload == '[DONE]') break;
      try {
        final obj = jsonDecode(payload);
        if (obj is! Map) continue;
        final choices = obj['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final delta = choices.first['delta'];
        if (delta is Map) {
          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            controller.add(content);
          }
        }
      } catch (_) {
        // Skip malformed chunks; the upstream might split mid-unicode.
      }
    }
  }

  Future<void> _runAnthropic(
    HttpClient client,
    String prompt,
    StreamController<String> controller,
  ) async {
    final uri = Uri.parse('${_config.resolveBaseUrl()}/v1/messages');
    final body = jsonEncode({
      'model': _config.model,
      'max_tokens': _config.maxTokens,
      'temperature': _config.temperature,
      'top_p': _config.topP,
      'stream': true,
      if (_config.systemPrompt != null && _config.systemPrompt!.isNotEmpty)
        'system': _config.systemPrompt,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    });

    final req = await client.postUrl(uri);
    req.headers.set('content-type', 'application/json');
    req.headers.set('anthropic-version', '2023-06-01');
    req.headers.set('x-api-key', _config.apiKey);
    if (_config.apiKey.startsWith('sk-ant-')) {
      // Anthropic supports auth via header only; nothing else needed.
    }
    req.add(utf8.encode(body));

    final resp = await req.close();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final err = await resp.transform(utf8.decoder).join();
      throw HttpException('Anthropic HTTP ${resp.statusCode}: $err', uri: uri);
    }

    // Anthropic SSE: event: <type>\ndata: <json>\n\n
    var currentEvent = '';
    await for (final line
        in resp.transform(utf8.decoder).transform(const LineSplitter())) {
      if (_cancelRequested) break;
      if (line.isEmpty) {
        currentEvent = '';
        continue;
      }
      if (line.startsWith('event:')) {
        currentEvent = line.substring(6).trim();
        continue;
      }
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (currentEvent != 'content_block_delta') continue;
      try {
        final obj = jsonDecode(payload);
        if (obj is! Map) continue;
        final delta = obj['delta'];
        if (delta is Map) {
          final text = delta['text'];
          if (text is String && text.isNotEmpty) {
            controller.add(text);
          }
        }
      } catch (_) {}
    }
  }
}

/// Preset configurations for popular providers. Users can clone & edit.
class CloudLlmPresets {
  static List<CloudLlmConfig> all() => [
        CloudLlmConfig(
          provider: CloudProvider.openai,
          apiKey: '',
          model: 'gpt-4o-mini',
        ),
        CloudLlmConfig(
          provider: CloudProvider.deepseek,
          apiKey: '',
          model: 'deepseek-chat',
        ),
        CloudLlmConfig(
          provider: CloudProvider.qwenDashScope,
          apiKey: '',
          model: 'qwen-plus',
        ),
        CloudLlmConfig(
          provider: CloudProvider.doubao,
          apiKey: '',
          model: 'doubao-pro-32k',
        ),
        CloudLlmConfig(
          provider: CloudProvider.groq,
          apiKey: '',
          model: 'llama-3.3-70b-versatile',
        ),
        CloudLlmConfig(
          provider: CloudProvider.ollama,
          apiKey: 'ollama', // Ollama doesn't need a key, but we keep the field.
          model: 'qwen2.5:7b',
        ),
        CloudLlmConfig(
          provider: CloudProvider.anthropic,
          apiKey: '',
          model: 'claude-3-5-sonnet-latest',
        ),
        CloudLlmConfig(
          provider: CloudProvider.custom,
          apiKey: '',
          model: 'your-model-id',
          baseUrl: 'https://your-custom-endpoint.com/v1',
        ),
      ];
}
