// Comprehensive model serialization tests for all data models.
// Covers: ChatMessage, ChatSession, AppConfig, SamplingConfig,
// CloudModelConfig, ModelInfo, AutomationPermissionStatus.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/data/models/models.dart';

void main() {
  group('ChatMessage', () {
    test('mediaPaths round-trips through JSON', () {
      final msg = ChatMessage(
        role: MessageRole.user,
        content: '描述这张图片',
        mediaPaths: ['/tmp/a.jpg', '/tmp/b.png'],
      );
      final json = msg.toJson();
      expect(json['media_paths'], ['/tmp/a.jpg', '/tmp/b.png']);

      final restored = ChatMessage.fromJson(json);
      expect(restored.mediaPaths, ['/tmp/a.jpg', '/tmp/b.png']);
      expect(restored.content, '描述这张图片');
      expect(restored.role, MessageRole.user);
    });

    test('text-only messages omit media_paths', () {
      final msg = ChatMessage(
        role: MessageRole.assistant,
        content: '你好',
      );
      final json = msg.toJson();
      expect(json.containsKey('media_paths'), isFalse);
      expect(ChatMessage.fromJson(json).mediaPaths, isEmpty);
    });

    test('system role message', () {
      final msg = ChatMessage(
        role: MessageRole.system,
        content: '你是一个助手',
      );
      final json = msg.toJson();
      expect(json['role'], 'system');
      final restored = ChatMessage.fromJson(json);
      expect(restored.role, MessageRole.system);
      expect(restored.content, '你是一个助手');
    });

    test('empty content message', () {
      final msg = ChatMessage(role: MessageRole.assistant, content: '');
      final json = msg.toJson();
      expect(json['content'], '');
      final restored = ChatMessage.fromJson(json);
      expect(restored.content, isEmpty);
    });

    test('null mediaPaths in JSON defaults to empty list', () {
      final json = {'role': 'user', 'content': 'hello'};
      final msg = ChatMessage.fromJson(json);
      expect(msg.mediaPaths, isEmpty);
    });
  });

  group('ChatSession', () {
    test('creates with default values', () {
      final session = ChatSession(
        id: 'test-id',
        title: '',
        messages: [],
        createdAt: DateTime(2024, 1, 1),
      );
      expect(session.id, 'test-id');
      expect(session.title, isEmpty);
      expect(session.messages, isEmpty);
      expect(session.modelId, isNull);
    });

    test('addMessage appends correctly', () {
      final session = ChatSession(
        id: 'test-id',
        title: '',
        messages: [],
        createdAt: DateTime(2024, 1, 1),
      );
      session.addMessage(ChatMessage(role: MessageRole.user, content: 'hi'));
      expect(session.messages.length, 1);
      expect(session.messages.first.content, 'hi');
    });

    test('reset clears messages', () {
      final session = ChatSession(
        id: 'test-id',
        title: '',
        messages: [],
        createdAt: DateTime(2024, 1, 1),
      );
      session.addMessage(ChatMessage(role: MessageRole.user, content: 'hi'));
      session.reset();
      expect(session.messages, isEmpty);
    });

    test('toJson/fromJson round-trips', () {
      final session = ChatSession(
        id: 'test-id',
        title: '测试',
        messages: [],
        createdAt: DateTime(2024, 1, 1),
      )
        ..addMessage(ChatMessage(role: MessageRole.user, content: '测试'))
        ..addMessage(ChatMessage(role: MessageRole.assistant, content: '回复'));
      final json = session.toJson();
      final restored = ChatSession.fromJson(json);
      expect(restored.id, session.id);
      expect(restored.messages.length, 2);
      expect(restored.messages[0].content, '测试');
      expect(restored.messages[1].content, '回复');
    });

    test('toJson with null modelId', () {
      final session = ChatSession(
        id: 'test-id',
        title: '',
        messages: [],
        createdAt: DateTime(2024, 1, 1),
      );
      final json = session.toJson();
      expect(json.containsKey('model_id'), isFalse);
    });

    test('copyWith preserves fields', () {
      final session = ChatSession(
        id: 'test-id',
        title: 'test',
        messages: [],
        createdAt: DateTime(2024, 1, 1),
      );
      final copy = session.copyWith();
      expect(copy.title, 'test');
      expect(copy.id, session.id);
    });
  });

  group('SamplingConfig', () {
    test('default constructor values', () {
      const config = SamplingConfig();
      expect(config.temperature, 0.7);
      expect(config.topK, 40);
      expect(config.maxNewTokens, 1024);
    });

    test('custom constructor values', () {
      const config = SamplingConfig(
        temperature: 0.5,
        topK: 20,
        maxNewTokens: 512,
      );
      expect(config.temperature, 0.5);
      expect(config.topK, 20);
      expect(config.maxNewTokens, 512);
    });

    test('toJson/fromJson round-trip', () {
      const config = SamplingConfig(
        temperature: 0.3,
        topK: 10,
        maxNewTokens: 2048,
      );
      final json = config.toJson();
      expect(json['temperature'], 0.3);
      expect(json['top_k'], 10);
      expect(json['max_new_tokens'], 2048);

      final restored = SamplingConfig.fromJson(json);
      expect(restored.temperature, 0.3);
      expect(restored.topK, 10);
      expect(restored.maxNewTokens, 2048);
    });

    test('fromJson handles missing fields with defaults', () {
      final config = SamplingConfig.fromJson({});
      expect(config.temperature, 0.7);
      expect(config.topK, 40);
      expect(config.maxNewTokens, 1024);
    });
  });

  group('AppConfig', () {
    test('encode/decode preserves active model and sampling', () {
      const config = AppConfig(
        activeModelId: 'Qwen2.5-Omni-7B-MNN',
        systemPrompt: '你是一个助手',
        sampling: SamplingConfig(
          temperature: 0.5,
          topK: 20,
          maxNewTokens: 512,
        ),
      );
      final encoded = config.encode();
      final decoded = AppConfig.decode(encoded);

      expect(decoded.activeModelId, 'Qwen2.5-Omni-7B-MNN');
      expect(decoded.systemPrompt, '你是一个助手');
      expect(decoded.sampling.temperature, 0.5);
      expect(decoded.sampling.topK, 20);
      expect(decoded.sampling.maxNewTokens, 512);
    });

    test('decode empty string returns default config', () {
      final config = AppConfig.decode('');
      expect(config.activeModelId, isNull);
      expect(config.systemPrompt, isEmpty);
      expect(config.sampling.temperature, 0.7);
    });

    test('decode invalid JSON returns default', () {
      final config = AppConfig.decode('not json');
      expect(config.activeModelId, isNull);
    });

    test('toJson/fromJson round-trip', () {
      const config = AppConfig(
        activeModelId: 'test-model',
        systemPrompt: 'test prompt',
        sampling: SamplingConfig(temperature: 0.1),
      );
      final json = config.toJson();
      final restored = AppConfig.fromJson(json);
      expect(restored.activeModelId, 'test-model');
      expect(restored.systemPrompt, 'test prompt');
      expect(restored.sampling.temperature, 0.1);
    });

    test('fromJson handles null fields', () {
      final config =
          AppConfig.fromJson({'active_model_id': null, 'system_prompt': null});
      expect(config.activeModelId, isNull);
      expect(config.systemPrompt, isEmpty);
    });
  });

  group('CloudModelConfig', () {
    test('default constructor', () {
      const config = CloudModelConfig();
      expect(config.provider, 'openai');
      expect(config.apiKey, isEmpty);
      expect(config.baseUrl, 'https://api.openai.com/v1');
      expect(config.model, 'gpt-4o');
    });

    test('toJson/fromJson round-trip', () {
      const config = CloudModelConfig(
        provider: 'anthropic',
        apiKey: 'sk-test',
        baseUrl: 'https://api.anthropic.com',
        model: 'claude-3',
      );
      final json = config.toJson();
      final restored = CloudModelConfig.fromJson(json);
      expect(restored.provider, 'anthropic');
      expect(restored.apiKey, 'sk-test');
      expect(restored.baseUrl, 'https://api.anthropic.com');
      expect(restored.model, 'claude-3');
    });

    test('fromJson handles missing fields', () {
      final config = CloudModelConfig.fromJson({});
      expect(config.provider, 'openai');
      expect(config.baseUrl, 'https://api.openai.com/v1');
    });
  });

  group('ModelInfo', () {
    test('parses omni type correctly', () {
      final json = jsonDecode('''
        {"id":"Qwen2.5-Omni-7B-MNN","name":"Omni","description":"",
         "size_mb":4100,"ram_mb":4500,"quant":"Q4","type":"omni",
         "download_url":"https://example.com","config_filename":"config.json"}
      ''') as Map<String, dynamic>;
      final model = ModelInfo.fromJson(json);
      expect(model.type, ModelType.omni);
      expect(model.id, 'Qwen2.5-Omni-7B-MNN');
      expect(model.sizeMb, 4100);
    });

    test('parses text type correctly', () {
      final json = jsonDecode('''
        {"id":"Qwen3-0.6B-MNN","name":"Qwen3","description":"",
         "size_mb":600,"ram_mb":700,"quant":"Q4","type":"text",
         "download_url":"https://example.com","config_filename":"config.json"}
      ''') as Map<String, dynamic>;
      final model = ModelInfo.fromJson(json);
      expect(model.type, ModelType.text);
      expect(model.id, 'Qwen3-0.6B-MNN');
    });

    test('fromJson handles missing optional fields', () {
      final json = jsonDecode('''
        {"id":"test","name":"Test","description":"","type":"text"}
      ''') as Map<String, dynamic>;
      final model = ModelInfo.fromJson(json);
      expect(model.sizeMb, isNull);
      expect(model.ramMb, isNull);
      expect(model.downloadUrl, isEmpty);
    });
  });

  group('AutomationPermissionStatus', () {
    test('default constructor', () {
      const status = AutomationPermissionStatus();
      expect(status.accessibilityEnabled, false);
      expect(status.shizukuGranted, false);
      expect(status.screenshotGranted, false);
      expect(status.usageStatsGranted, false);
      expect(status.notificationListenerGranted, false);
      expect(status.warningDismissed, false);
    });

    test('toJson/fromJson round-trip', () {
      const status = AutomationPermissionStatus(
        accessibilityEnabled: true,
        shizukuGranted: false,
        screenshotGranted: true,
        usageStatsGranted: false,
        notificationListenerGranted: true,
        warningDismissed: false,
      );
      final json = status.toJson();
      final restored = AutomationPermissionStatus.fromJson(json);
      expect(restored.accessibilityEnabled, true);
      expect(restored.shizukuGranted, false);
      expect(restored.screenshotGranted, true);
      expect(restored.usageStatsGranted, false);
      expect(restored.notificationListenerGranted, true);
      expect(restored.warningDismissed, false);
    });

    test('fromJson handles missing fields', () {
      final status = AutomationPermissionStatus.fromJson({});
      expect(status.accessibilityEnabled, false);
      expect(status.shizukuGranted, false);
    });
  });
}
