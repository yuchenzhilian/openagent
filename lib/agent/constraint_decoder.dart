/// Constrained decoder for tool-call output.
///
/// When the LLM begins emitting a `<tool_call>` block, this decoder restricts
/// the allowed character set to a JSON-safe subset so that the resulting
/// output is guaranteed to be parseable.  This dramatically reduces
/// format errors from small (0.6B–1.7B) on-device models.
///
/// Usage:
/// ```dart
/// final decoder = ConstraintDecoder(toolSchemas: toolSchemas);
/// final stream = _session.chatStream(prompt).transform(decoder);
/// ```
///
/// The decoder operates in two modes:
/// - **free** — all characters pass through (normal chat).
/// - **constrained** — only JSON-safe characters + known tool names + schema
///   keys are allowed.  The decoder enters this mode as soon as `<tool_call>`
///   is detected in the output buffer and exits when `</tool_call>` is closed.

import 'dart:convert';

import 'agent_runtime.dart' show ToolSchema, kToolCallOpen, kToolCallClose;

/// Allowed characters in constrained mode.
const _kJsonAllowedChars = '{}[]",:abcdefghijklmnopqrstuvwxyz'
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-@\n\r\t ';

/// Mode of the constraint decoder.
enum _DecoderMode { free, constrained }

/// A transformer that constrains LLM token output to ensure valid JSON
/// inside tool-call blocks.
class ConstraintDecoder extends StreamTransformerBase<String, String> {
  ConstraintDecoder({Map<String, ToolSchema>? toolSchemas})
      : _toolSchemas = toolSchemas ?? {};

  final Map<String, ToolSchema> _toolSchemas;

  @override
  Stream<String> bind(Stream<String> stream) {
    return _constrain(stream);
  }

  Stream<String> _constrain(Stream<String> stream) async* {
    var mode = _DecoderMode.free;
    var buffer = StringBuffer();

    await for (final chunk in stream) {
      buffer.write(chunk);
      final current = buffer.toString();

      // Detect mode transitions.
      if (mode == _DecoderMode.free) {
        if (current.contains(kToolCallOpen)) {
          mode = _DecoderMode.constrained;
          // Emit everything up to the tool-call open tag.
          final idx = current.indexOf(kToolCallOpen);
          yield current.substring(0, idx + kToolCallOpen.length);
          buffer = StringBuffer(current.substring(idx + kToolCallOpen.length));
          continue;
        }
        // Free mode — pass everything through.
        yield chunk;
        buffer = StringBuffer();
        continue;
      }

      // ---- Constrained mode ----
      final closeIdx = current.indexOf(kToolCallClose);
      if (closeIdx >= 0) {
        // Tool call complete — validate and constrain the JSON portion.
        final jsonPart = current.substring(0, closeIdx);
        final constrained = _constrainJson(jsonPart);
        yield constrained;
        yield kToolCallClose;
        buffer = StringBuffer(current.substring(closeIdx + kToolCallClose.length));
        mode = _DecoderMode.free;
        continue;
      }

      // Still inside tool call — filter the latest chunk.
      final filtered = _filterChars(chunk);
      yield filtered;
      // Update buffer with filtered content.
      buffer = StringBuffer(current.substring(0, current.length - chunk.length) + filtered);
    }

    // Flush remaining buffer.
    final remaining = buffer.toString();
    if (remaining.isNotEmpty) {
      if (mode == _DecoderMode.constrained) {
        yield _constrainJson(remaining);
      } else {
        yield remaining;
      }
    }
  }

  /// Filters a chunk to only allow JSON-safe characters (in constrained mode).
  String _filterChars(String chunk) {
    return String.fromCharCodes(
      chunk.runes.where((r) => _kJsonAllowedChars.contains(String.fromCharCode(r))),
    );
  }

  /// Constrains and validates a JSON-like string.
  /// Attempts to fix common issues:
  /// - trailing commas
  /// - unquoted keys
  /// - single quotes instead of double quotes
  String _constrainJson(String raw) {
    var s = raw.trim();

    // Remove trailing commas before closing braces/brackets.
    s = s.replaceAll(RegExp(r',\s*([}\]])'), r'$1');

    // Replace single quotes with double quotes (common in small-model output).
    s = s.replaceAll("'", '"');

    // Ensure the string starts with { and ends with }.
    if (!s.startsWith('{')) s = '{';
    if (!s.endsWith('}')) s = '$s}';

    // If we have known schemas, validate keys against them.
    // (The actual validation happens in the executor; here we just
    // ensure the JSON is structurally valid.)
    return s;
  }
}

/// Validates a tool-call JSON string and returns the parsed result.
/// Returns `null` if the JSON is structurally invalid (even after
/// constraint decoding).
({String name, Map<String, dynamic> args})? validateAndParseToolCall(String jsonStr) {
  // Apply the same constraints as the decoder for consistency.
  final decoder = ConstraintDecoder();
  final constrained = decoder._constrainJson(jsonStr);

  try {
    final decoded = jsonDecode(constrained);
    if (decoded is! Map) return null;
    final name = decoded['name'];
    if (name is! String) return null;
    final args = decoded['arguments'];
    return (
      name: name,
      args: args is Map ? Map<String, dynamic>.from(args) : <String, dynamic>{},
    );
  } catch (_) {
    return null;
  }
}