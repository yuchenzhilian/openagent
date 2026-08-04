// Tests for additional built-in tools: web, HTTP, utility tools.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/agent/builtin_tools.dart';

void main() {
  group('RandomNumberTool', () {
    final tool = randomNumberTool();

    test('generates random number within range', () async {
      final result = await tool.handler({'min': 1, 'max': 10});
      expect(result.isError, isFalse);
      expect(result.output, contains('随机数'));
    });

    test('generates multiple numbers', () async {
      final result = await tool.handler({'min': 0, 'max': 100, 'count': 5});
      expect(result.isError, isFalse);
      expect(result.output, contains('5个'));
    });

    test('min > max returns error', () async {
      final result = await tool.handler({'min': 10, 'max': 1});
      expect(result.isError, isTrue);
    });

    test('empty args uses defaults', () async {
      final result = await tool.handler({});
      expect(result.isError, isFalse);
    });
  });

  group('UuidGeneratorTool', () {
    final tool = uuidGeneratorTool();

    test('generates valid UUID v4 format', () async {
      final result = await tool.handler({});
      expect(result.isError, isFalse);
      final uuid = result.output;
      // UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
      expect(
          uuid,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });
  });

  group('Base64CodecTool', () {
    final tool = base64CodecTool();

    test('encodes text', () async {
      final result = await tool.handler({'action': 'encode', 'text': 'hello'});
      expect(result.isError, isFalse);
      expect(result.output, isNotEmpty);
    });

    test('decodes text', () async {
      final encoded = base64Encode(utf8.encode('hello'));
      final result = await tool.handler({'action': 'decode', 'text': encoded});
      expect(result.isError, isFalse);
      expect(result.output, 'hello');
    });

    test('invalid action returns error', () async {
      final result = await tool.handler({'action': 'invalid', 'text': 'test'});
      expect(result.isError, isTrue);
    });

    test('empty text returns error', () async {
      final result = await tool.handler({'action': 'encode', 'text': ''});
      expect(result.isError, isTrue);
    });
  });

  group('UrlCodecTool', () {
    final tool = urlCodecTool();

    test('encodes URL', () async {
      final result =
          await tool.handler({'action': 'encode', 'text': 'hello world'});
      expect(result.isError, isFalse);
      expect(result.output, 'hello+world');
    });

    test('decodes URL', () async {
      final result =
          await tool.handler({'action': 'decode', 'text': 'hello+world'});
      expect(result.isError, isFalse);
      expect(result.output, 'hello world');
    });
  });

  group('HashTool', () {
    final tool = hashTool();

    test('computes MD5 hash', () async {
      final result = await tool.handler({'text': 'hello', 'algorithm': 'md5'});
      expect(result.isError, isFalse);
      expect(result.output.length, 32);
    });

    test('computes SHA256 hash', () async {
      final result =
          await tool.handler({'text': 'hello', 'algorithm': 'sha256'});
      expect(result.isError, isFalse);
    });

    test('empty text returns error', () async {
      final result = await tool.handler({'text': '', 'algorithm': 'md5'});
      expect(result.isError, isTrue);
    });
  });

  group('ColorConverterTool', () {
    final tool = colorConverterTool();

    test('converts hex to rgb', () async {
      final result =
          await tool.handler({'value': '#FF8800', 'from': 'hex', 'to': 'rgb'});
      expect(result.isError, isFalse);
      expect(result.output, contains('rgb'));
    });

    test('converts rgb to hex', () async {
      final result = await tool
          .handler({'value': 'rgb(255,136,0)', 'from': 'rgb', 'to': 'hex'});
      expect(result.isError, isFalse);
      expect(result.output, contains('#'));
    });

    test('invalid value returns error', () async {
      final result =
          await tool.handler({'value': 'invalid', 'from': 'hex', 'to': 'rgb'});
      expect(result.isError, isTrue);
    });
  });

  group('TextTemplateTool', () {
    final tool = textTemplateTool();

    test('renders template with variables', () async {
      final result = await tool.handler({
        'template': '你好，{name}！今天是{date}。',
        'variables': {'name': '张三', 'date': '2026-08-03'},
      });
      expect(result.isError, isFalse);
      expect(result.output, '你好，张三！今天是2026-08-03。');
    });

    test('empty template returns error', () async {
      final result = await tool.handler({
        'template': '',
        'variables': {'name': 'test'},
      });
      expect(result.isError, isTrue);
    });
  });

  group('PasswordGeneratorTool', () {
    final tool = passwordGeneratorTool();

    test('generates password with default length', () async {
      final result = await tool.handler({});
      expect(result.isError, isFalse);
      expect(result.output.length, greaterThanOrEqualTo(16));
    });

    test('generates password with custom length', () async {
      final result = await tool.handler({'length': 8});
      expect(result.isError, isFalse);
    });

    test('respects character set options', () async {
      final result = await tool.handler({'use_symbols': false, 'length': 10});
      expect(result.isError, isFalse);
    });
  });

  group('CsvJsonTool', () {
    final tool = csvJsonTool();

    test('converts CSV to JSON', () async {
      final result = await tool.handler({
        'direction': 'csv_to_json',
        'text': 'name,age\nAlice,30\nBob,25',
      });
      expect(result.isError, isFalse);
      expect(result.output, contains('Alice'));
      expect(result.output, contains('Bob'));
    });

    test('converts JSON to CSV', () async {
      final result = await tool.handler({
        'direction': 'json_to_csv',
        'text': '[{"name":"Alice","age":30},{"name":"Bob","age":25}]',
      });
      expect(result.isError, isFalse);
      expect(result.output, contains('Alice'));
      expect(result.output, contains('Bob'));
    });

    test('empty text returns error', () async {
      final result =
          await tool.handler({'direction': 'csv_to_json', 'text': ''});
      expect(result.isError, isTrue);
    });
  });

  group('MarkdownTableTool', () {
    final tool = markdownTableTool();

    test('renders JSON array as table', () async {
      final result = await tool.handler({
        'text': '[{"name":"Alice","age":30},{"name":"Bob","age":25}]',
      });
      expect(result.isError, isFalse);
      expect(result.output, contains('| name'));
      expect(result.output, contains('| ---'));
      expect(result.output, contains('Alice'));
    });

    test('empty text returns error', () async {
      final result = await tool.handler({'text': ''});
      expect(result.isError, isTrue);
    });
  });

  group('StringCaseTool', () {
    final tool = stringCaseTool();

    test('converts to camelCase', () async {
      final result =
          await tool.handler({'text': 'hello world', 'target_case': 'camel'});
      expect(result.isError, isFalse);
      expect(result.output, contains('helloWorld'));
    });

    test('converts to snake_case', () async {
      final result =
          await tool.handler({'text': 'hello world', 'target_case': 'snake'});
      expect(result.isError, isFalse);
      expect(result.output, contains('hello_world'));
    });
  });

  group('EncodeDecodeTool', () {
    final tool = encodeDecodeTool();

    test('hex encode', () async {
      final result = await tool.handler({'mode': 'hex_encode', 'text': 'ABC'});
      expect(result.isError, isFalse);
      expect(result.output, '41 42 43');
    });

    test('hex decode', () async {
      final result =
          await tool.handler({'mode': 'hex_decode', 'text': '41 42 43'});
      expect(result.isError, isFalse);
      expect(result.output, 'ABC');
    });

    test('empty text returns error', () async {
      final result = await tool.handler({'mode': 'hex_encode', 'text': ''});
      expect(result.isError, isTrue);
    });
  });

  group('TextStatsAdvancedTool', () {
    final tool = textStatsAdvancedTool();

    test('counts text stats', () async {
      final result = await tool.handler({'text': 'Hello world. How are you?'});
      expect(result.isError, isFalse);
      expect(result.output, contains('字符总数'));
      expect(result.output, contains('句数'));
    });

    test('empty text returns zero stats', () async {
      final result = await tool.handler({'text': ''});
      expect(result.isError, isFalse);
      expect(result.output, contains('字符: 0'));
    });
  });

  group('DateCalculatorTool', () {
    final tool = dateCalculatorTool();

    test('adds days to date', () async {
      final result = await tool.handler({'date': '2026-01-01', 'add_days': 10});
      expect(result.isError, isFalse);
      expect(result.output, contains('2026-01-11'));
    });

    test('handles empty date (uses current time)', () async {
      final result = await tool.handler({'add_days': 0});
      expect(result.isError, isFalse);
    });

    test('compares two dates', () async {
      final result = await tool.handler({
        'date': '2026-01-10',
        'compare_to': '2026-01-01',
      });
      expect(result.isError, isFalse);
      expect(result.output, contains('9 天'));
    });
  });

  group('RegexTesterTool', () {
    final tool = regexTesterTool();

    test('finds matches', () async {
      final result =
          await tool.handler({'pattern': '\\d+', 'text': 'abc123def456'});
      expect(result.isError, isFalse);
      expect(result.output, contains('2 个匹配'));
    });

    test('performs replacement', () async {
      final result = await tool
          .handler({'pattern': '\\d+', 'text': 'abc123', 'replacement': 'X'});
      expect(result.isError, isFalse);
      expect(result.output, contains('abcX'));
    });

    test('no match returns appropriate message', () async {
      final result = await tool.handler({'pattern': '\\d+', 'text': 'abc'});
      expect(result.isError, isFalse);
      expect(result.output, contains('未找到匹配项'));
    });
  });
}
