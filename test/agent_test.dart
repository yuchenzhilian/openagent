import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/agent/builtin_tools.dart';

void main() {
  group('CalculatorTool', () {
    final tool = calculatorTool();

    test('basic arithmetic', () async {
      expect((await tool.handler({'expression': '2+3'})).output, '5.0');
      expect((await tool.handler({'expression': '10-4'})).output, '6.0');
      expect((await tool.handler({'expression': '6*7'})).output, '42.0');
      expect((await tool.handler({'expression': '20/4'})).output, '5.0');
    });

    test('operator precedence', () async {
      expect((await tool.handler({'expression': '2+3*4'})).output, '14.0');
      expect((await tool.handler({'expression': '(2+3)*4'})).output, '20.0');
    });

    test('math functions', () async {
      final sqrtResult = await tool.handler({'expression': 'sqrt(144)'});
      expect(double.parse(sqrtResult.output), closeTo(12.0, 0.001));

      final sinResult = await tool.handler({'expression': 'sin(0)'});
      expect(double.parse(sinResult.output), closeTo(0.0, 0.001));
    });

    test('unary minus', () async {
      expect((await tool.handler({'expression': '-5'})).output, '-5.0');
      expect((await tool.handler({'expression': '-(3+2)'})).output, '-5.0');
    });

    test('empty expression returns error', () async {
      final result = await tool.handler({'expression': ''});
      expect(result.isError, isTrue);
    });

    test('invalid expression returns error', () async {
      final result = await tool.handler({'expression': '2+'});
      expect(result.isError, isTrue);
    });

    test('missing parameter returns error', () async {
      final result = await tool.handler({});
      expect(result.isError, isTrue);
    });
  });

  group('DateTimeTool', () {
    final tool = dateTimeTool();

    test('returns current date time', () async {
      final result = await tool.handler({});
      expect(result.isError, isFalse);
      expect(result.output, contains('年'));
      expect(result.output, contains('月'));
      expect(result.output, contains('日'));
      expect(RegExp(r'\d{2}:\d{2}:\d{2}').hasMatch(result.output), isTrue);
    });
  });

  group('TextCounterTool', () {
    final tool = textCounterTool();

    test('counts characters and words', () async {
      final result = await tool.handler({'text': 'hello world foo'});
      expect(result.isError, isFalse);
      expect(result.output, contains('字符数: 15'));
      expect(result.output, contains('词数: 3'));
    });

    test('empty text', () async {
      final result = await tool.handler({'text': ''});
      expect(result.output, contains('字符数: 0'));
    });

    test('non-string parameter returns error', () async {
      final result = await tool.handler({'text': 123});
      expect(result.isError, isTrue);
    });
  });

  group('UnitConverterTool', () {
    final tool = unitConverterTool();

    test('length conversion', () async {
      final r1 = await tool.handler({'value': 100, 'from': 'cm', 'to': 'm'});
      expect(double.parse(r1.output), closeTo(1.0, 0.001));

      final r2 = await tool.handler({'value': 1, 'from': 'km', 'to': 'm'});
      expect(double.parse(r2.output), closeTo(1000.0, 0.001));

      final r3 = await tool.handler({'value': 1, 'from': 'mile', 'to': 'km'});
      expect(double.parse(r3.output), closeTo(1.6093, 0.01));
    });

    test('weight conversion', () async {
      final r1 = await tool.handler({'value': 1, 'from': 'kg', 'to': 'g'});
      expect(double.parse(r1.output), closeTo(1000.0, 0.001));

      final r2 = await tool.handler({'value': 1, 'from': 'lb', 'to': 'kg'});
      expect(double.parse(r2.output), closeTo(0.4536, 0.001));
    });

    test('temperature conversion', () async {
      final r1 = await tool.handler({'value': 0, 'from': 'C', 'to': 'F'});
      expect(double.parse(r1.output), closeTo(32.0, 0.001));

      final r2 = await tool.handler({'value': 100, 'from': 'C', 'to': 'K'});
      expect(double.parse(r2.output), closeTo(373.15, 0.01));

      final r3 = await tool.handler({'value': 212, 'from': 'F', 'to': 'C'});
      expect(double.parse(r3.output), closeTo(100.0, 0.001));
    });

    test('incompatible units return error', () async {
      final result = await tool.handler({'value': 1, 'from': 'm', 'to': 'kg'});
      expect(result.isError, isTrue);
    });

    test('missing parameter returns error', () async {
      final result = await tool.handler({'from': 'm', 'to': 'cm'});
      expect(result.isError, isTrue);
    });
  });

  group('KnowledgeSearchTool', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kb_test_');
      // Create test documents.
      await File('${tempDir.path}/flutter.txt').writeAsString(
        'Flutter is a UI toolkit by Google.\n\n'
        'It uses Dart language and supports cross-platform development.\n\n'
        'Hot reload is a key feature of Flutter.',
      );
      await File('${tempDir.path}/mnn.txt').writeAsString(
        'MNN is a lightweight deep learning engine.\n\n'
        'It supports Android and iOS with GPU acceleration.\n\n'
        'MNN-LLM provides on-device large language model inference.',
      );
      await File('${tempDir.path}/chinese.txt').writeAsString(
        'MNN是一个轻量级的深度学习引擎。\n\n'
        '它支持Android和iOS平台的GPU加速。\n\n'
        'MNN-LLM提供端侧大语言模型推理能力。',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('finds relevant content', () async {
      final tool = knowledgeSearchTool(tempDir);
      final result = await tool.handler({'query': 'Flutter cross-platform'});
      expect(result.isError, isFalse);
      expect(result.output, contains('Flutter'));
      expect(result.output, contains('cross-platform'));
    });

    test('finds Chinese content', () async {
      final tool = knowledgeSearchTool(tempDir);
      final result = await tool.handler({'query': '深度学习引擎'});
      expect(result.isError, isFalse, reason: 'Error: ${result.output}');
      expect(result.output, contains('MNN'));
    });

    test('returns error for no match', () async {
      final tool = knowledgeSearchTool(tempDir);
      final result = await tool.handler({'query': 'xyzabc123'});
      expect(result.isError, isTrue);
    });

    test('returns error for empty query', () async {
      final tool = knowledgeSearchTool(tempDir);
      final result = await tool.handler({'query': ''});
      expect(result.isError, isTrue);
    });

    test('returns error for non-existent directory', () async {
      final tool = knowledgeSearchTool(Directory('/nonexistent/path'));
      final result = await tool.handler({'query': 'test'});
      expect(result.isError, isTrue);
    });

    test('returns error for empty knowledge base', () async {
      final emptyDir = await Directory.systemTemp.createTemp('empty_kb_');
      try {
        final tool = knowledgeSearchTool(emptyDir);
        final result = await tool.handler({'query': 'test'});
        expect(result.isError, isTrue);
      } finally {
        await emptyDir.delete(recursive: true);
      }
    });
  });

  group('JsonFormatterTool', () {
    final tool = jsonFormatterTool();

    test('formats valid JSON', () async {
      final result = await tool.handler({'json': '{"b":2,"a":1}'});
      expect(result.isError, isFalse);
      expect(result.output, contains('"a"'));
      expect(result.output, contains('"b"'));
    });

    test('formats nested JSON', () async {
      final result =
          await tool.handler({'json': '{"user":{"name":"Alice","age":30}}'});
      expect(result.isError, isFalse);
      expect(result.output, contains('"user"'));
      expect(result.output, contains('"Alice"'));
    });

    test('formats JSON array', () async {
      final result = await tool.handler({'json': '[1,2,3]'});
      expect(result.isError, isFalse);
      expect(result.output, contains('1'));
      expect(result.output, contains('2'));
      expect(result.output, contains('3'));
    });

    test('returns error for invalid JSON', () async {
      final result = await tool.handler({'json': '{invalid}'});
      expect(result.isError, isTrue);
    });

    test('returns error for empty input', () async {
      final result = await tool.handler({'json': ''});
      expect(result.isError, isTrue);
    });
  });

  group('builtinTools', () {
    test('returns all built-in tools', () {
      final tools = builtinTools();
      expect(tools.length, greaterThanOrEqualTo(25));
      expect(
          tools.map((t) => t.name).toList(),
          containsAll([
            'calculator',
            'datetime',
            'text_counter',
            'unit_converter',
            'json_formatter',
            'web_search',
            'http_fetch',
            'html_to_text',
            'random_number',
            'uuid',
            'base64_codec',
            'color_converter',
            'timer',
            'weather',
            'ip_info',
            'text_template',
            'agent_analyze_and_plan',
            'url_codec',
            'regex_tester',
            'string_case',
            'encode_decode',
            'hash',
            'text_stats_advanced',
            'csv_json',
            'markdown_table',
            'password_generator',
            'date_calculator'
          ]));
    });
  });
}
