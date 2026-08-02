// Basic model serialization tests — verify ChatMessage round-trips mediaPaths
// and AppConfig encodes/decodes correctly. These don't require a native MNN
// build, so they can run in any CI environment.
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
    });

    test('parses text type correctly', () {
      final json = jsonDecode('''
        {"id":"Qwen3-0.6B-MNN","name":"Qwen3","description":"",
         "size_mb":600,"ram_mb":700,"quant":"Q4","type":"text",
         "download_url":"https://example.com","config_filename":"config.json"}
      ''') as Map<String, dynamic>;
      final model = ModelInfo.fromJson(json);
      expect(model.type, ModelType.text);
    });
  });
}
