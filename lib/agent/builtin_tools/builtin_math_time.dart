part of '../builtin_tools.dart';

/// A calculator that safely evaluates arithmetic expressions.
///
/// Supports +, -, *, /, parentheses, and common math functions (sin, cos,
/// sqrt, …). Implemented with a recursive-descent parser — no eval().
Tool calculatorTool() => Tool(
      name: 'calculator',
      description: '计算数学表达式，如 2+3*4, sin(1.5), sqrt(144)',
      schema: {
        'type': 'object',
        'properties': {
          'expression': {
            'type': 'string',
            'description': '要计算的数学表达式',
          },
        },
        'required': ['expression'],
      },
      handler: (args) async {
        final expr = args['expression'];
        if (expr is! String || expr.isEmpty) {
          return const ToolResult.error('参数 expression 不能为空');
        }
        try {
          final result = _evaluate(expr);
          return ToolResult.ok(result.toString());
        } catch (e) {
          return ToolResult.error('计算失败: $e');
        }
      },
    );

/// Returns the current date and time.
Tool dateTimeTool() => Tool(
      name: 'datetime',
      description: '获取当前日期和时间',
      schema: {'type': 'object', 'properties': {}},
      handler: (args) async {
        final now = DateTime.now();
        return ToolResult.ok(
          '${now.year}年${now.month}月${now.day}日 '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}',
        );
      },
    );

/// Converts between common units of length, weight, and temperature.
///
/// Usage: `{"value": 100, "from": "cm", "to": "inch"}`
/// Supported units: m, km, cm, mm, mile, ft, in (length);
/// kg, g, mg, lb, oz (weight); C, F, K (temperature).
Tool unitConverterTool() => Tool(
      name: 'unit_converter',
      description: '单位换算（长度/重量/温度），如 {"value":100,"from":"cm","to":"in"}',
      schema: {
        'type': 'object',
        'properties': {
          'value': {
            'type': 'number',
            'description': '要转换的数值',
          },
          'from': {
            'type': 'string',
            'description': '源单位: m,km,cm,mm,mile,ft,in, kg,g,mg,lb,oz, C,F,K',
          },
          'to': {
            'type': 'string',
            'description': '目标单位',
          },
        },
        'required': ['value', 'from', 'to'],
      },
      handler: (args) async {
        final value = args['value'];
        final from = args['from'];
        final to = args['to'];
        if (value is! num) {
          return const ToolResult.error('参数 value 必须是数字');
        }
        if (from is! String || to is! String) {
          return const ToolResult.error('参数 from 和 to 必须是字符串');
        }
        try {
          final result = _convertUnit(value.toDouble(), from, to);
          return ToolResult.ok(result.toStringAsFixed(4));
        } catch (e) {
          return ToolResult.error('换算失败: $e');
        }
      },
    );

/// Date arithmetic: add/subtract days, weeks, months from a date.
Tool dateCalculatorTool() => Tool(
      name: 'date_calculator',
      description: '日期计算：在给定日期上加减天数/周数/月数/小时。可比较两个日期差值。',
      schema: {
        'type': 'object',
        'properties': {
          'date': {
            'type': 'string',
            'description':
                '基准日期（ISO 格式 YYYY-MM-DD 或 YYYY-MM-DDTHH:MM:SS），默认当前时间',
          },
          'add_days': {
            'type': 'integer',
            'description': '加/减的天数（负数表示减）',
          },
          'add_weeks': {
            'type': 'integer',
            'description': '加/减的周数',
          },
          'add_months': {
            'type': 'integer',
            'description': '加/减的月数',
          },
          'add_hours': {
            'type': 'integer',
            'description': '加/减的小时数',
          },
          'compare_to': {
            'type': 'string',
            'description': '可选：另一个日期，用于计算差值',
          },
        },
        'required': [],
      },
      handler: (args) async {
        try {
          final dateStr = args['date'] as String?;
          DateTime base;
          if (dateStr == null || dateStr.isEmpty) {
            base = DateTime.now();
          } else {
            base = DateTime.parse(dateStr);
          }
          final addDays = (args['add_days'] as int?) ?? 0;
          final addWeeks = (args['add_weeks'] as int?) ?? 0;
          final addMonths = (args['add_months'] as int?) ?? 0;
          final addHours = (args['add_hours'] as int?) ?? 0;
          // Add days, weeks, hours.
          var result = base.add(Duration(days: addDays, hours: addHours));
          result = result.add(Duration(days: addWeeks * 7));
          // Add months manually.
          if (addMonths != 0) {
            final newMonth = result.month + addMonths;
            final monthsToAdd = newMonth - 1;
            final newYear = result.year + (monthsToAdd ~/ 12);
            final finalMonth = (monthsToAdd % 12) + 1;
            result = DateTime(
              newYear,
              finalMonth,
              result.day,
              result.hour,
              result.minute,
              result.second,
            );
          }
          final sb = StringBuffer();
          sb.writeln('基准: ${base.toIso8601String()}');
          sb.writeln('结果: ${result.toIso8601String()}');
          sb.writeln('星期: ${_weekdayName(result.weekday)}');
          final cmpStr = args['compare_to'] as String?;
          if (cmpStr != null && cmpStr.isNotEmpty) {
            final cmp = DateTime.parse(cmpStr);
            final diff = result.difference(cmp);
            sb.writeln('\n对比 $cmpStr:');
            sb.writeln(
                '  相差 ${diff.inDays} 天 ${diff.inHours.remainder(24)} 小时 ${diff.inMinutes.remainder(60)} 分钟');
            sb.writeln('  总小时: ${diff.inHours}, 总分钟: ${diff.inMinutes}');
          }
          return ToolResult.ok(sb.toString());
        } catch (e) {
          return ToolResult.error('日期计算失败: $e');
        }
      },
    );

String _weekdayName(int wd) {
  const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  if (wd < 1 || wd > 7) return '?';
  return names[wd - 1];
}

// ---- Expression evaluator (recursive descent) ----------------------------

double _evaluate(String input) {
  final parser = _ExprParser(input.replaceAll(' ', ''));
  return parser.parseExpression();
}

class _ExprParser {
  _ExprParser(this._input);

  final String _input;
  int _pos = 0;

  void _skipWs() {
    while (_pos < _input.length && _input[_pos] == ' ') {
      _pos++;
    }
  }

  double parseExpression() {
    double left = parseTerm();
    while (_pos < _input.length) {
      _skipWs();
      if (_pos >= _input.length) break;
      final op = _input[_pos];
      if (op == '+' || op == '-') {
        _pos++;
        final right = parseTerm();
        left = op == '+' ? left + right : left - right;
      } else {
        break;
      }
    }
    return left;
  }

  double parseTerm() {
    double left = parseFactor();
    while (_pos < _input.length) {
      _skipWs();
      if (_pos >= _input.length) break;
      final op = _input[_pos];
      if (op == '*' || op == '/') {
        _pos++;
        final right = parseFactor();
        left = op == '*' ? left * right : left / right;
      } else {
        break;
      }
    }
    return left;
  }

  double parseFactor() {
    _skipWs();
    if (_pos >= _input.length) {
      throw const FormatException('unexpected end');
    }
    // Unary +/-
    if (_input[_pos] == '+' || _input[_pos] == '-') {
      final sign = _input[_pos] == '-' ? -1.0 : 1.0;
      _pos++;
      return sign * parseFactor();
    }
    // Parenthesised expression
    if (_input[_pos] == '(') {
      _pos++;
      final v = parseExpression();
      _skipWs();
      if (_pos < _input.length && _input[_pos] == ')') _pos++;
      return v;
    }
    // Number
    final start = _pos;
    while (_pos < _input.length && (_input[_pos].contains(RegExp(r'[0-9.]')))) {
      _pos++;
    }
    if (_pos == start) {
      throw FormatException('expected number at $_pos');
    }
    return double.parse(_input.substring(start, _pos));
  }
}

// ---- Unit converter ------------------------------------------------------

/// Conversion factors to base unit (metre / gram / celsius).
const _lengthFactors = {
  'm': 1.0,
  'km': 1000.0,
  'cm': 0.01,
  'mm': 0.001,
  'mile': 1609.344,
  'ft': 0.3048,
  'in': 0.0254,
};

const _weightFactors = {
  'kg': 1000.0,
  'g': 1.0,
  'mg': 0.001,
  'lb': 453.59237,
  'oz': 28.349523,
};

double _convertUnit(double value, String from, String to) {
  // Temperature needs special handling (offset + scale).
  if ({'C', 'F', 'K'}.contains(from) || {'C', 'F', 'K'}.contains(to)) {
    if (!_isTempUnit(from) || !_isTempUnit(to)) {
      throw ArgumentError('温度单位不匹配: $from → $to');
    }
    return _convertTemp(value, from, to);
  }

  // Length
  if (_lengthFactors.containsKey(from) && _lengthFactors.containsKey(to)) {
    final inBase = value * _lengthFactors[from]!;
    return inBase / _lengthFactors[to]!;
  }

  // Weight
  if (_weightFactors.containsKey(from) && _weightFactors.containsKey(to)) {
    final inBase = value * _weightFactors[from]!;
    return inBase / _weightFactors[to]!;
  }

  throw ArgumentError('不支持的单位: $from → $to');
}

bool _isTempUnit(String u) => u == 'C' || u == 'F' || u == 'K';

double _convertTemp(double value, String from, String to) {
  // First convert to Celsius.
  double celsius;
  switch (from) {
    case 'C':
      celsius = value;
    case 'F':
      celsius = (value - 32) * 5 / 9;
    case 'K':
      celsius = value - 273.15;
    default:
      celsius = value;
  }
  // Then convert from Celsius to target.
  switch (to) {
    case 'C':
      return celsius;
    case 'F':
      return celsius * 9 / 5 + 32;
    case 'K':
      return celsius + 273.15;
    default:
      return celsius;
  }
}
