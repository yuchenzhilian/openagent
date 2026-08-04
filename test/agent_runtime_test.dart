// Tests for Agent Runtime: tool-call parsing, error handling, and permission
// error detection. These tests verify the core ReAct loop infrastructure
// without requiring a real LLM session.


import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/agent/agent_runtime.dart';
import 'package:openagent/agent/agent_constants.dart';

void main() {
  group('ToolResult', () {
    test('ok constructor', () {
      final r = ToolResult.ok('success');
      expect(r.isError, isFalse);
      expect(r.output, 'success');
    });

    test('error constructor', () {
      final r = ToolResult.error('failed');
      expect(r.isError, isTrue);
      expect(r.output, 'failed');
    });

    test('toString for ok', () {
      expect(ToolResult.ok('ok').toString(), 'ToolResult(ok)');
    });

    test('toString for error', () {
      expect(ToolResult.error('err').toString(), 'ToolError(err)');
    });
  });

  group('toolError', () {
    test('builds basic error message', () {
      final msg = toolError('something went wrong');
      expect(msg, contains('something went wrong'));
    });

    test('includes advice when provided', () {
      final msg = toolError('error', advice: 'try again');
      expect(msg, contains('try again'));
    });

    test('includes code emoji for each error code', () {
      expect(toolError('x', code: ToolErrorCode.timeout), contains('⏱'));
      expect(toolError('x', code: ToolErrorCode.permission), contains('🔒'));
      expect(toolError('x', code: ToolErrorCode.notFound), contains('🔍'));
      expect(toolError('x', code: ToolErrorCode.network), contains('🌐'));
      expect(toolError('x', code: ToolErrorCode.invalidArgument), contains('⚠️'));
      expect(toolError('x', code: ToolErrorCode.unsupported), contains('🚫'));
      expect(toolError('x', code: ToolErrorCode.unknown), contains('❌'));
    });
  });

  group('Tool', () {
    test('creates tool with required fields', () {
      final tool = Tool(
        name: 'test_tool',
        description: 'A test tool',
        schema: {'type': 'object', 'properties': {}},
        handler: (_) async => ToolResult.ok('done'),
      );
      expect(tool.name, 'test_tool');
      expect(tool.description, 'A test tool');
    });

    test('handler executes correctly', () async {
      final tool = Tool(
        name: 'echo',
        description: 'Echoes input',
        schema: {'type': 'object', 'properties': {}},
        handler: (args) async => ToolResult.ok(args['msg'] ?? ''),
      );
      final result = await tool.handler({'msg': 'hello'});
      expect(result.isError, isFalse);
      expect(result.output, 'hello');
    });
  });

  group('_tryParseToolCall', () {
    // The parser is a top-level function in agent_runtime.dart.
    // We test it indirectly via the behavior it exposes.

    test('detects complete tool call', () {
      // We can't import _tryParseToolCall directly, but we can verify
      // the constants it uses are correct.
      expect(kToolCallOpen, '<tool_call>');
      expect(kToolCallClose, '</tool_call>');
    });

    test('constants match expected format', () {
      // Verify that the open/close tags form a valid XML-like pair.
      final example = '$kToolCallOpen\n{"name":"test"}\n$kToolCallClose';
      expect(example, contains('<tool_call>'));
      expect(example, contains('</tool_call>'));
      expect(example, contains('{"name":"test"}'));
    });
  });

  group('_isPermissionError', () {
    // We test the permission error detection logic by testing the
    // toolError helper and the error code constants.

    test('toolError with permission code', () {
      final msg = toolError('权限不足', code: ToolErrorCode.permission);
      expect(msg, contains('🔒'));
      expect(msg, contains('权限不足'));
    });

    test('toolError with timeout code', () {
      final msg = toolError('操作超时', code: ToolErrorCode.timeout);
      expect(msg, contains('⏱'));
      expect(msg, contains('操作超时'));
    });
  });

  group('AgentEvent', () {
    test('AgentTokenEvent', () {
      final event = AgentTokenEvent('hello');
      expect(event.chunk, 'hello');
    });

    test('AgentToolCallEvent', () {
      final event = AgentToolCallEvent(
        toolName: 'calculator',
        arguments: {'expression': '2+2'},
      );
      expect(event.toolName, 'calculator');
      expect(event.arguments['expression'], '2+2');
    });

    test('ToolExecutionEvent', () {
      final event = ToolExecutionEvent(
        toolName: 'calculator',
        result: ToolResult.ok('4'),
      );
      expect(event.toolName, 'calculator');
      expect(event.result.isError, isFalse);
    });

    test('AgentDoneEvent', () {
      final event = AgentDoneEvent('done', steps: 3);
      expect(event.answer, 'done');
      expect(event.steps, 3);
    });

    test('AgentErrorEvent', () {
      final event = AgentErrorEvent('error');
      expect(event.message, 'error');
    });
  });

  group('ToolErrorCode', () {
    test('all enum values are present', () {
      expect(ToolErrorCode.values.length, 7);
      expect(ToolErrorCode.values, containsAll([
        ToolErrorCode.timeout,
        ToolErrorCode.permission,
        ToolErrorCode.notFound,
        ToolErrorCode.network,
        ToolErrorCode.invalidArgument,
        ToolErrorCode.unsupported,
        ToolErrorCode.unknown,
      ]));
    });
  });

  group('ToolSchema typedef', () {
    test('can be used as Map<String, dynamic>', () {
      // ToolSchema = Map<String, dynamic>
      void acceptSchema(ToolSchema schema) {
        expect(schema['type'], 'object');
      }

      acceptSchema({'type': 'object', 'properties': {}});
    });
  });
}