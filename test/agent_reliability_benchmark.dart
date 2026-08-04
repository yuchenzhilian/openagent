// Agent reliability benchmark (Direction 4 Step 5).
// Measures tool call format correctness, error recovery rate, and intent classification accuracy.
import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/agent/constraint_decoder.dart';
import 'package:openagent/agent/intent_classifier.dart';
import 'package:openagent/agent/tool_validator.dart';
import 'package:openagent/agent/agent_runtime.dart';
import 'package:openagent/agent/agent_constants.dart';
import 'dart:async';
import 'dart:convert';

Future<String> _runDecoder(
    StreamTransformerBase<String, String> decoder, List<String> chunks) async {
  final controller = StreamController<String>();
  final stream = controller.stream.transform(decoder);
  final result = StringBuffer();
  final sub = stream.listen((s) => result.write(s));
  for (final chunk in chunks) {
    controller.sink.add(chunk);
  }
  await controller.sink.close();
  await sub.cancel();
  return result.toString();
}

void main() {
  group('Constrained Decoding Benchmark', () {
    test('100 valid tool calls - format correctness', () async {
      int validCount = 0;
      for (int i = 0; i < 100; i++) {
        final input = [
          'some text ',
          '<tool_call>',
          '{"name":"tool_$i","arguments":{"value":$i}}',
          '</tool_call>',
          ' done',
        ];
        final output = await _runDecoder(ConstraintDecoder(), input);
        final jsonStart = output.indexOf(kToolCallOpen) + kToolCallOpen.length;
        final jsonEnd = output.indexOf(kToolCallClose);
        if (jsonStart > 0 && jsonEnd > jsonStart) {
          final json = output.substring(jsonStart, jsonEnd).trim();
          try {
            jsonDecode(json);
            validCount++;
          } catch (_) {}
        }
      }
      // Expect at least 95% format correctness.
      expect(validCount, greaterThanOrEqualTo(95));
    });

    test('edge cases - empty args, special chars, long values', () async {
      final longStr = 'a' * 1000;
      final cases = [
        ['<tool_call>', '{"name":"t","arguments":{}}', '</tool_call>'],
        [
          '<tool_call>',
          '{"name":"t","arguments":{"k":"v@#\$%"}}',
          '</tool_call>'
        ],
        [
          '<tool_call>',
          '{"name":"t","arguments":{"k":"$longStr"}}',
          '</tool_call>'
        ],
      ];
      for (final input in cases) {
        final output = await _runDecoder(ConstraintDecoder(), input);
        final jsonStart = output.indexOf(kToolCallOpen) + kToolCallOpen.length;
        final jsonEnd = output.indexOf(kToolCallClose);
        expect(jsonStart, greaterThan(0));
        expect(jsonEnd, greaterThan(jsonStart));
        final json = output.substring(jsonStart, jsonEnd).trim();
        expect(() => jsonDecode(json), returnsNormally);
      }
    });
  });

  group('Intent Classification Accuracy', () {
    final classifier = IntentClassifier();

    test('math expressions (10 cases)', () {
      final cases = [
        '2+2',
        '3*5',
        'sqrt(16)',
        'calculate 10% of 50',
        'what is 2^8',
        '100 / 4',
        'sin(30)',
        'log(100)',
        'abs(-5)',
        '25.5 * 3'
      ];
      for (final c in cases) {
        expect(classifier.classify(c).category, IntentCategory.mathCalc,
            reason: 'Failed for: $c');
      }
    });

    test('date/time queries (10 cases)', () {
      final cases = [
        'what time is it',
        'current date',
        'today',
        '几点了',
        '今天星期几',
        'now',
        'what day is it',
        '现在几点',
        '日期',
        'time now'
      ];
      for (final c in cases) {
        expect(classifier.classify(c).category, IntentCategory.dateTime,
            reason: 'Failed for: $c');
      }
    });

    test('Android automation (10 cases)', () {
      final cases = [
        '打开微信',
        'click the settings button',
        '发送短信给张三',
        '打开抖音',
        'swipe down',
        '拍照',
        '截图',
        '关闭蓝牙',
        'open app com.test',
        'scroll to bottom'
      ];
      for (final c in cases) {
        expect(
            classifier.classify(c).category, IntentCategory.androidAutomation,
            reason: 'Failed for: $c');
      }
    });

    test('general chat (10 cases)', () {
      final cases = [
        'Hello',
        'How are you?',
        '你好',
        '谢谢',
        '再见',
        'Nice to meet you',
        'What do you think?',
        '好的',
        '是的',
        '确实如此'
      ];
      for (final c in cases) {
        expect(classifier.classify(c).category, IntentCategory.generalChat,
            reason: 'Failed for: $c');
      }
    });
  });

  group('ToolValidator Schema Validation', () {
    final validator = ToolValidator();
    Tool makeTool(Map<String, dynamic> schema) => Tool(
        name: 'test',
        description: 'test',
        schema: schema,
        handler: (_) async => const ToolResult.ok('ok'));

    test('required field detection', () {
      final tool = makeTool({
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'email': {'type': 'string'},
        },
        'required': ['name', 'email']
      });
      expect(validator.validate(tool, {'name': 'a', 'email': 'b'}).isValid,
          isTrue);
      expect(validator.validate(tool, {'name': 'a'}).isValid, isFalse);
      expect(validator.validate(tool, {}).isValid, isFalse);
    });

    test('type coercion', () {
      final tool = makeTool({
        'type': 'object',
        'properties': {
          'count': {'type': 'integer'},
          'ratio': {'type': 'number'},
          'flag': {'type': 'boolean'},
        }
      });
      expect(
          validator
              .validate(tool, {'count': 5, 'ratio': 0.5, 'flag': true}).isValid,
          isTrue);
      expect(validator.validate(tool, {'count': 5.5}).isValid, isFalse);
      expect(validator.validate(tool, {'flag': 'true'}).isValid, isFalse);
    });

    test('error recovery - invalid argument returns proper error', () {
      final result = validator.toErrorResult(
        const ValidationResult(isValid: false, errorMessage: '参数 "name" 应为字符串'),
      );
      expect(result.isError, isTrue);
      expect(result.output, contains('name'));
    });
  });
}
