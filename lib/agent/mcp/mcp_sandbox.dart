/// Stdio process sandbox for MCP servers.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SandboxConfig {
  final List<String> allowedReadPaths;
  final List<String> allowedWritePaths;
  final bool allowNetwork;
  final Duration maxExecutionTime;
  final int maxOutputBytes;

  const SandboxConfig({
    this.allowedReadPaths = const [],
    this.allowedWritePaths = const [],
    this.allowNetwork = false,
    this.maxExecutionTime = const Duration(seconds: 30),
    this.maxOutputBytes = 1048576,
  });
}

class SandboxedResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  const SandboxedResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
  });
}

class McpSandbox {
  McpSandbox({required SandboxConfig config}) : _config = config;
  final SandboxConfig _config;

  Future<SandboxedResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    try {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: true,
      );
      final stdoutBuf = StringBuffer();
      final stderrBuf = StringBuffer();
      int totalBytes = 0;

      process.stdout
          .transform(utf8.decoder)
          .listen((data) {
        totalBytes += data.length;
        if (totalBytes <= _config.maxOutputBytes) stdoutBuf.write(data);
      });

      process.stderr
          .transform(utf8.decoder)
          .listen((data) => stderrBuf.write(data));

      await process.stdin.close();
      final result = await process.exitCode.timeout(
        _config.maxExecutionTime,
        onTimeout: () {
          process.kill();
          return -1;
        },
      );

      return SandboxedResult(
        exitCode: result,
        stdout: stdoutBuf.toString(),
        stderr: stderrBuf.toString(),
        timedOut: result == -1,
      );
    } on TimeoutException {
      return const SandboxedResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Process timed out',
        timedOut: true,
      );
    } catch (e) {
      return SandboxedResult(
        exitCode: -1,
        stdout: '',
        stderr: 'Sandbox execution failed: $e',
      );
    }
  }

  bool canRead(String path) =>
      _config.allowedReadPaths.isEmpty
          ? false
          : _config.allowedReadPaths.any((p) => path.startsWith(p));

  bool canWrite(String path) =>
      _config.allowedWritePaths.isEmpty
          ? false
          : _config.allowedWritePaths.any((p) => path.startsWith(p));
}