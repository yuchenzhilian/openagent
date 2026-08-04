/// Tool-call schema validator.
///
/// Validates tool arguments against the tool's declared schema before
/// execution.  Catches common LLM errors:
/// - missing required parameters
/// - wrong parameter types (string vs number vs boolean)
/// - values outside allowed range
///
/// This reduces runtime errors and provides meaningful error messages
/// that the LLM can use to self-correct.

import 'agent_runtime.dart' show Tool, ToolResult, toolError, ToolErrorCode;

/// Result of schema validation.
class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  const ValidationResult({required this.isValid, this.errorMessage});

  static const valid = ValidationResult(isValid: true);
}

/// Validates tool arguments against a schema.
class ToolValidator {
  /// Validate [args] against [tool]'s schema.
  /// Returns [ValidationResult.valid] if the arguments are acceptable,
  /// or a [ValidationResult] with an error message otherwise.
  ValidationResult validate(Tool tool, Map<String, dynamic> args) {
    final schema = tool.schema;
    if (schema.isEmpty) {
      return ValidationResult.valid;
    }

    final properties = schema['properties'];
    if (properties is! Map) {
      return ValidationResult.valid;
    }

    final requiredFields = schema['required'];
    final requiredList =
        (requiredFields is List) ? requiredFields.cast<String>() : <String>[];

    // 1. Check required fields.
    for (final field in requiredList) {
      if (!args.containsKey(field) || args[field] == null) {
        return ValidationResult(
          isValid: false,
          errorMessage: '缺少必填参数 "$field"。$field 是必填的，请提供。',
        );
      }
    }

    // 2. Check each argument against its schema property.
    for (final entry in args.entries) {
      final key = entry.key;
      final value = entry.value;
      final propSchema = properties[key];

      if (propSchema is! Map) continue;

      final expectedType = propSchema['type'] as String?;
      if (expectedType == null) continue;

      final typeError = _checkType(key, value, expectedType, propSchema);
      if (typeError != null) {
        return ValidationResult(isValid: false, errorMessage: typeError);
      }

      // 3. Check enum values.
      final enumValues = propSchema['enum'];
      if (enumValues is List && enumValues.isNotEmpty) {
        if (!enumValues.contains(value)) {
          return ValidationResult(
            isValid: false,
            errorMessage:
                '参数 "$key" 的值 "$value" 无效。有效值: ${enumValues.join(", ")}',
          );
        }
      }
    }

    return ValidationResult.valid;
  }

  /// Produce a [ToolResult] error from a [ValidationResult].
  ToolResult toErrorResult(ValidationResult result) {
    return ToolResult.error(
      toolError(
        result.errorMessage ?? '工具参数校验失败',
        code: ToolErrorCode.invalidArgument,
        advice: '请检查参数名和参数值是否正确，必要时参考工具描述。',
      ),
    );
  }

  /// Check that [value] matches the expected [type] from the schema.
  String? _checkType(String key, dynamic value, String type, Map propSchema) {
    switch (type) {
      case 'string':
        if (value is! String) {
          return '参数 "$key" 应为字符串，但收到了 ${value.runtimeType} 类型。';
        }
        // Check maxLength if specified.
        final maxLen = propSchema['maxLength'];
        if (maxLen is int && value.length > maxLen) {
          return '参数 "$key" 过长 (${value.length} > $maxLen)。';
        }
        return null;

      case 'number':
        if (value is! num) {
          return '参数 "$key" 应为数字，但收到了 ${value.runtimeType} 类型。';
        }
        // Check range.
        final minimum = propSchema['minimum'];
        final maximum = propSchema['maximum'];
        if (minimum is num && value < minimum) {
          return '参数 "$key" 的值 $value 小于最小值 $minimum。';
        }
        if (maximum is num && value > maximum) {
          return '参数 "$key" 的值 $value 大于最大值 $maximum。';
        }
        return null;

      case 'integer':
        if (value is! int) {
          return '参数 "$key" 应为整数，但收到了 ${value.runtimeType} 类型。';
        }
        return null;

      case 'boolean':
        if (value is! bool) {
          return '参数 "$key" 应为布尔值 (true/false)，但收到了 ${value.runtimeType} 类型。';
        }
        return null;

      case 'array':
        if (value is! List) {
          return '参数 "$key" 应为数组，但收到了 ${value.runtimeType} 类型。';
        }
        return null;

      case 'object':
        if (value is! Map) {
          return '参数 "$key" 应为对象，但收到了 ${value.runtimeType} 类型。';
        }
        return null;

      default:
        return null; // Unknown type, skip validation.
    }
  }
}
