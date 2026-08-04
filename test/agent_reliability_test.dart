// Tests for Direction 4: ReAct reliability engineering.
import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/agent/constraint_decoder.dart';
import 'package:openagent/agent/intent_classifier.dart';
import 'package:openagent/agent/tool_validator.dart';
import 'package:openagent/agent/agent_runtime.dart';
import 'package:openagent/agent/agent_constants.dart';
import 'dart:async';

Future<String> _runDecoder(StreamTransformerBase<String, String> decoder, List<String> chunks) async {
  final controller = StreamController<String>();
  final stream = controller.stream.transform(decoder);
  final result = StringBuffer();
  final sub = stream.listen((s) => result.write(s));
  for (final chunk in chunks) { controller.sink.add(chunk); }
  await controller.sink.close(); await sub.cancel();
  return result.toString();
}

void main() {
  group('ConstraintDecoder', () {
    test('passes through free text', () async {
      final output = await _runDecoder(ConstraintDecoder(), ['hello', ' world', ' 你好']);
      expect(output, 'hello world 你好');
    });
    test('validates JSON in tool call', () async {
      final output = await _runDecoder(ConstraintDecoder(), ['text ', '<tool_call>', '{"name":"calc","args":{"x":1}}', '</tool_call>']);
      expect(output, contains(kToolCallOpen));
      expect(output, contains(kToolCallClose));
    });
  });

  group('IntentClassifier', () {
    final classifier = IntentClassifier();
    test('math', () => expect(classifier.classify('2+2').category, IntentCategory.mathCalc));
    test('date', () => expect(classifier.classify('what time is it').category, IntentCategory.dateTime));
    test('android', () => expect(classifier.classify('打开微信').category, IntentCategory.androidAutomation));
    test('knowledge', () => expect(classifier.classify('what is ML').category, IntentCategory.knowledgeQuery));
    test('web', () => expect(classifier.classify('search for Flutter').category, IntentCategory.webSearch));
    test('chat', () => expect(classifier.classify('Hello').category, IntentCategory.generalChat));
  });

  group('ToolValidator', () {
    final validator = ToolValidator();
    Tool makeTool(Map<String, dynamic> schema) => Tool(name: 'test', description: 'test', schema: schema, handler: (_) async => const ToolResult.ok('ok'));
    test('required fields', () {
      final tool = makeTool({'type': 'object', 'properties': {'name': {'type': 'string'}}, 'required': ['name']});
      expect(validator.validate(tool, {'name': 'test'}).isValid, isTrue);
      expect(validator.validate(tool, {}).isValid, isFalse);
    });
    test('type checking', () {
      final tool = makeTool({'type': 'object', 'properties': {'age': {'type': 'number', 'minimum': 0}}});
      expect(validator.validate(tool, {'age': 25}).isValid, isTrue);
      expect(validator.validate(tool, {'age': -1}).isValid, isFalse);
    });
    test('enum', () {
      final tool = makeTool({'type': 'object', 'properties': {'c': {'type': 'string', 'enum': ['a', 'b']}}});
      expect(validator.validate(tool, {'c': 'a'}).isValid, isTrue);
      expect(validator.validate(tool, {'c': 'z'}).isValid, isFalse);
    });
  });
}