import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/agent/agent_runtime.dart';

/// Creates a [Tool] with a simple handler that returns a fixed string.
Tool mockTool(String name, {String output = 'ok', bool isError = false}) {
  return Tool(
    name: name,
    description: 'Mock tool: $name',
    schema: {'type': 'object', 'properties': {}},
    handler: (_) async => isError
        ? ToolResult.error(output)
        : ToolResult.ok(output),
  );
}

/// Creates a [Tool] that throws [TimeoutException] after [delay].
Tool mockTimeoutTool(String name, {int delayMs = 100}) {
  return Tool(
    name: name,
    description: 'Timeout tool: $name',
    schema: {'type': 'object', 'properties': {}},
    handler: (_) async {
      await Future.delayed(Duration(milliseconds: delayMs));
      throw TimeoutException('timed out');
    },
  );
}

/// Creates a temporary directory with some test files.
Future<Directory> createTempDir() async {
  return await Directory.systemTemp.createTemp('openagent_test_');
}

/// Asserts that a [ToolResult] is successful with content matching [predicate].
void expectOk(ToolResult result, Object Function(String output) matcher) {
  expect(result.isError, isFalse, reason: 'Expected OK but got error: ${result.output}');
  expect(result.output, matcher);
}

/// Asserts that a [ToolResult] is an error.
void expectError(ToolResult result, [Object? matcher]) {
  expect(result.isError, isTrue, reason: 'Expected error but got: ${result.output}');
  if (matcher != null) {
    expect(result.output, matcher);
  }
}