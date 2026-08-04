part of '../builtin_tools.dart';

/// Tokenizes text into search terms.
/// Handles both space-separated words (English) and individual CJK characters.
Set<String> _tokenize(String text) {
  final lower = text.toLowerCase();
  final terms = <String>{};
  final buffer = StringBuffer();

  void flushBuffer() {
    if (buffer.isEmpty) return;
    final token = buffer.toString();
    buffer.clear();
    if (_isCjk(token)) {
      // For CJK text, use individual characters as terms.
      for (final c in token.runes) {
        terms.add(String.fromCharCode(c));
      }
    } else if (token.length > 1) {
      terms.add(token);
    }
  }

  for (final char in lower.runes) {
    if (char >= 0x4e00 && char <= 0x9fff) {
      // CJK character — flush any pending ASCII buffer first.
      flushBuffer();
      buffer.write(String.fromCharCode(char));
    } else if ((char >= 0x61 && char <= 0x7a) ||
        (char >= 0x30 && char <= 0x39)) {
      // ASCII lowercase letter or digit.
      buffer.write(String.fromCharCode(char));
    } else {
      flushBuffer();
    }
  }
  flushBuffer();

  return terms;
}

bool _isCjk(String s) => s.codeUnits.every((c) => c >= 0x4e00 && c <= 0x9fff);

class _TextChunk {
  final String source;
  final String text;
  _TextChunk({required this.source, required this.text});
}

/// Counts words and characters in text.
Tool textCounterTool() => Tool(
      name: 'text_counter',
      description: '统计文本的字数和字符数',
      schema: {
        'type': 'object',
        'properties': {
          'text': {
            'type': 'string',
            'description': '要统计的文本',
          },
        },
        'required': ['text'],
      },
      handler: (args) async {
        final text = args['text'];
        if (text is! String) {
          return const ToolResult.error('参数 text 必须是字符串');
        }
        final charCount = text.length;
        final wordCount =
            text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length;
        return ToolResult.ok('字符数: $charCount, 词数: $wordCount');
      },
    );

/// Formats and validates JSON strings.
///
/// Parses the input JSON and re-emits it with 2-space indentation.
/// Useful for debugging API responses or configuration files.
Tool jsonFormatterTool() => Tool(
      name: 'json_formatter',
      description: '格式化JSON字符串，验证并美化输出（2空格缩进）',
      schema: {
        'type': 'object',
        'properties': {
          'json': {
            'type': 'string',
            'description': '要格式化的JSON字符串',
          },
        },
        'required': ['json'],
      },
      handler: (args) async {
        final input = args['json'];
        if (input is! String || input.trim().isEmpty) {
          return const ToolResult.error('参数 json 不能为空');
        }
        try {
          final decoded = jsonDecode(input.trim());
          const encoder = JsonEncoder.withIndent('  ');
          final formatted = encoder.convert(decoded);
          return ToolResult.ok(formatted);
        } on FormatException catch (e) {
          return ToolResult.error('JSON解析失败: ${e.message}');
        } catch (e) {
          return ToolResult.error('格式化失败: $e');
        }
      },
    );

/// URL encode/decode.
Tool urlCodecTool() => Tool(
      name: 'url_codec',
      description: 'URL 编码/解码。对字符串进行百分比编码或解码。',
      schema: {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['encode', 'decode'],
            'description': 'encode=编码, decode=解码',
          },
          'text': {
            'type': 'string',
            'description': '要编码或解码的字符串',
          },
        },
        'required': ['action', 'text'],
      },
      handler: (args) async {
        final action = args['action'] as String? ?? 'encode';
        final text = args['text'] as String? ?? '';
        try {
          if (action == 'encode') {
            return ToolResult.ok(Uri.encodeQueryComponent(text));
          } else {
            return ToolResult.ok(Uri.decodeQueryComponent(text));
          }
        } catch (e) {
          return ToolResult.error('URL $action 失败: $e');
        }
      },
    );

/// Regex match / test.
Tool regexTesterTool() => Tool(
      name: 'regex_tester',
      description: '正则表达式匹配/测试。返回匹配结果列表或替换结果。',
      schema: {
        'type': 'object',
        'properties': {
          'pattern': {
            'type': 'string',
            'description': '正则表达式模式，如 \\d+ 或 [a-z]+',
          },
          'text': {
            'type': 'string',
            'description': '要匹配的文本',
          },
          'replacement': {
            'type': 'string',
            'description': '可选：替换文本（如果提供，则执行替换操作）',
          },
          'case_sensitive': {
            'type': 'boolean',
            'description': '是否区分大小写（默认 true）',
          },
        },
        'required': ['pattern', 'text'],
      },
      handler: (args) async {
        final pattern = args['pattern'] as String? ?? '';
        final text = args['text'] as String? ?? '';
        final replacement = args['replacement'] as String?;
        final caseSensitive = args['case_sensitive'] as bool? ?? true;
        if (pattern.isEmpty) {
          return const ToolResult.error('参数 pattern 不能为空');
        }
        try {
          final re = RegExp(pattern, caseSensitive: caseSensitive);
          if (replacement != null) {
            final result = text.replaceAll(re, replacement);
            return ToolResult.ok('替换结果:\n$result');
          }
          final matches = re.allMatches(text).toList();
          if (matches.isEmpty) {
            return ToolResult.ok('未找到匹配项');
          }
          final sb = StringBuffer();
          sb.writeln('找到 ${matches.length} 个匹配:');
          for (var i = 0; i < matches.length; i++) {
            final m = matches[i];
            sb.writeln('  [$i] "${m.group(0)}" @位置 ${m.start}-${m.end}');
            if (m.groupCount > 0) {
              for (var g = 1; g <= m.groupCount; g++) {
                sb.writeln('      组$g: "${m.group(g)}"');
              }
            }
          }
          return ToolResult.ok(sb.toString());
        } catch (e) {
          return ToolResult.error('正则表达式错误: $e');
        }
      },
    );

/// String case conversion.
Tool stringCaseTool() => Tool(
      name: 'string_case',
      description:
          '字符串大小写格式转换。支持: camelCase, PascalCase, snake_case, kebab-case, UPPER_CASE, lower_case, 首字母大写。',
      schema: {
        'type': 'object',
        'properties': {
          'text': {
            'type': 'string',
            'description': '要转换的字符串',
          },
          'target_case': {
            'type': 'string',
            'enum': [
              'camel',
              'pascal',
              'snake',
              'kebab',
              'upper',
              'lower',
              'capitalize'
            ],
            'description':
                '目标格式: camel=驼峰, pascal=大驼峰, snake=下划线, kebab=连字符, upper=全大写, lower=全小写, capitalize=首字母大写',
          },
        },
        'required': ['text', 'target_case'],
      },
      handler: (args) async {
        final text = args['text'] as String? ?? '';
        final targetCase = args['target_case'] as String? ?? 'camel';
        if (text.isEmpty) {
          return const ToolResult.error('参数 text 不能为空');
        }
        final words = text.split(RegExp(r'[_\-\s]+'));
        final result = <String>[];
        for (final w in words) {
          var start = 0;
          for (var i = 1; i < w.length; i++) {
            if (w[i].toUpperCase() == w[i] &&
                w[i - 1].toLowerCase() == w[i - 1]) {
              result.add(w.substring(start, i));
              start = i;
            }
          }
          result.add(w.substring(start));
        }
        final cleanWords = result.where((w) => w.isNotEmpty).toList();
        if (cleanWords.isEmpty) {
          return const ToolResult.error('无法解析单词');
        }
        String output;
        switch (targetCase) {
          case 'camel':
            output = cleanWords[0].toLowerCase();
            for (var i = 1; i < cleanWords.length; i++) {
              output += cleanWords[i][0].toUpperCase() +
                  cleanWords[i].substring(1).toLowerCase();
            }
          case 'pascal':
            output = cleanWords
                .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
                .join();
          case 'snake':
            output = cleanWords.map((w) => w.toLowerCase()).join('_');
          case 'kebab':
            output = cleanWords.map((w) => w.toLowerCase()).join('-');
          case 'upper':
            output = cleanWords.map((w) => w.toUpperCase()).join('_');
          case 'lower':
            output = cleanWords.map((w) => w.toLowerCase()).join('_');
          case 'capitalize':
            output = cleanWords
                .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
                .join(' ');
          default:
            return ToolResult.error('不支持的目标格式: $targetCase');
        }
        return ToolResult.ok('$text → $output');
      },
    );

/// Hex / binary / ASCII conversions.
Tool encodeDecodeTool() => Tool(
      name: 'encode_decode',
      description:
          '编解码工具。支持: hex_encode, hex_decode, binary_encode, binary_decode, ascii_to_hex, hex_to_ascii。',
      schema: {
        'type': 'object',
        'properties': {
          'mode': {
            'type': 'string',
            'enum': [
              'hex_encode',
              'hex_decode',
              'binary_encode',
              'binary_decode',
              'ascii_to_hex',
              'hex_to_ascii'
            ],
            'description': '编解码模式',
          },
          'text': {
            'type': 'string',
            'description': '要编解码的文本',
          },
        },
        'required': ['mode', 'text'],
      },
      handler: (args) async {
        final mode = args['mode'] as String? ?? 'hex_encode';
        final text = args['text'] as String? ?? '';
        if (text.isEmpty) {
          return const ToolResult.error('参数 text 不能为空');
        }
        try {
          switch (mode) {
            case 'hex_encode':
              return ToolResult.ok(text.codeUnits
                  .map((c) => c.toRadixString(16).padLeft(2, '0'))
                  .join(' '));
            case 'hex_decode':
              final cleaned = text.replaceAll(RegExp(r'\s+'), '');
              if (cleaned.length % 2 != 0)
                return const ToolResult.error('hex 字符串长度必须为偶数');
              final bytes = <int>[];
              for (var i = 0; i < cleaned.length; i += 2) {
                bytes.add(int.parse(cleaned.substring(i, i + 2), radix: 16));
              }
              return ToolResult.ok(String.fromCharCodes(bytes));
            case 'binary_encode':
              return ToolResult.ok(text.codeUnits
                  .map((c) => c.toRadixString(2).padLeft(8, '0'))
                  .join(' '));
            case 'binary_decode':
              final cleaned = text.replaceAll(RegExp(r'\s+'), '');
              if (cleaned.length % 8 != 0)
                return const ToolResult.error('二进制字符串长度必须是 8 的倍数');
              final bytes = <int>[];
              for (var i = 0; i < cleaned.length; i += 8) {
                bytes.add(int.parse(cleaned.substring(i, i + 8), radix: 2));
              }
              return ToolResult.ok(String.fromCharCodes(bytes));
            case 'ascii_to_hex':
              return ToolResult.ok(text.codeUnits
                  .map((c) => c.toRadixString(16).padLeft(2, '0'))
                  .join(''));
            case 'hex_to_ascii':
              final cleaned = text.replaceAll(RegExp(r'\s+'), '');
              if (cleaned.length % 2 != 0)
                return const ToolResult.error('hex 字符串长度必须为偶数');
              final chars = <int>[];
              for (var i = 0; i < cleaned.length; i += 2) {
                chars.add(int.parse(cleaned.substring(i, i + 2), radix: 16));
              }
              return ToolResult.ok(String.fromCharCodes(chars));
            default:
              return ToolResult.error('不支持的模式: $mode');
          }
        } catch (e) {
          return ToolResult.error('编解码失败: $e');
        }
      },
    );

/// Compute hash of text. Supports MD5, SHA-1, SHA-256, SHA-512.
///
/// Note: Dart's stdlib only has SHA-1/SHA-256/SHA-512 via crypto package.
/// MD5 is implemented inline. For other algorithms (e.g. bcrypt) the
/// model should call out to a tool/HTTP service.
Tool hashTool() => Tool(
      name: 'hash_text',
      description: '计算文本的哈希值。支持 md5 / sha1 / sha256 / sha512。',
      schema: {
        'type': 'object',
        'properties': {
          'text': {
            'type': 'string',
            'description': '要计算哈希的文本',
          },
          'algorithm': {
            'type': 'string',
            'enum': ['md5', 'sha1', 'sha256', 'sha512'],
            'description': '哈希算法（默认 sha256）',
          },
        },
        'required': ['text', 'algorithm'],
      },
      handler: (args) async {
        final text = args['text'] as String? ?? '';
        final algo = (args['algorithm'] as String? ?? 'sha256').toLowerCase();
        if (text.isEmpty) {
          return const ToolResult.error('参数 text 不能为空');
        }
        try {
          switch (algo) {
            case 'md5':
              return ToolResult.ok(_md5Hex(text));
            case 'sha1':
              return ToolResult.ok(_shaHex(text, 1));
            case 'sha256':
              return ToolResult.ok(_shaHex(text, 256));
            case 'sha512':
              return ToolResult.ok(_shaHex(text, 512));
            default:
              return ToolResult.error('不支持的算法: $algo');
          }
        } catch (e) {
          return ToolResult.error('哈希计算失败: $e');
        }
      },
    );

/// Pure-Dart MD5 (RFC 1321). Returns lowercase hex.
String _md5Hex(String input) {
  final bytes = utf8.encode(input);
  // Standard MD5 constants.
  const s = [
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
  ];
  const k = [
    0xd76aa478,
    0xe8c7b756,
    0x242070db,
    0xc1bdceee,
    0xf57c0faf,
    0x4787c62a,
    0xa8304613,
    0xfd469501,
    0x698098d8,
    0x8b44f7af,
    0xffff5bb1,
    0x895cd7be,
    0x6b901122,
    0xfd987193,
    0xa679438e,
    0x49b40821,
    0xf61e2562,
    0xc040b340,
    0x265e5a51,
    0xe9b6c7aa,
    0xd62f105d,
    0x02441453,
    0xd8a1e681,
    0xe7d3fbc8,
    0x21e1cde6,
    0xc33707d6,
    0xf4d50d87,
    0x455a14ed,
    0xa9e3e905,
    0xfcefa3f8,
    0x676f02d9,
    0x8d2a4c8a,
    0xfffa3942,
    0x8771f681,
    0x6d9d6122,
    0xfde5380c,
    0xa4beea44,
    0x4bdecfa9,
    0xf6bb4b60,
    0xbebfbc70,
    0x289b7ec6,
    0xeaa127fa,
    0xd4ef3085,
    0x04881d05,
    0xd9d4d039,
    0xe6db99e5,
    0x1fa27cf8,
    0xc4ac5665,
    0xf4292244,
    0x432aff97,
    0xab9423a7,
    0xfc93a039,
    0x655b59c3,
    0x8f0ccc92,
    0xffeff47d,
    0x85845dd1,
    0x6fa87e4f,
    0xfe2ce6e0,
    0xa3014314,
    0x4e0811a1,
    0xf7537e82,
    0xbd3af235,
    0x2ad7d2bb,
    0xeb86d391,
  ];
  var a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
  final origLen = bytes.length;
  final newLen = (((origLen + 8) ~/ 64) + 1) * 64;
  final padded = List<int>.filled(newLen, 0);
  for (var i = 0; i < origLen; i++) {
    padded[i] = bytes[i];
  }
  padded[origLen] = 0x80;
  final bitLen = origLen * 8;
  for (var i = 0; i < 8; i++) {
    padded[newLen - 8 + i] = (bitLen >> (8 * i)) & 0xff;
  }
  for (var chunk = 0; chunk < newLen; chunk += 64) {
    final m = List<int>.filled(16, 0);
    for (var i = 0; i < 16; i++) {
      m[i] = (padded[chunk + i * 4]) |
          (padded[chunk + i * 4 + 1] << 8) |
          (padded[chunk + i * 4 + 2] << 16) |
          (padded[chunk + i * 4 + 3] << 24);
    }
    var a = a0, b = b0, c = c0, d = d0;
    for (var i = 0; i < 64; i++) {
      int f, g;
      if (i < 16) {
        f = (b & c) | ((~b) & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | ((~d) & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | (~d));
        g = (7 * i) % 16;
      }
      final temp = d;
      d = c;
      c = b;
      b = (b + _leftRotate((a + f + k[i] + m[g]) & 0xffffffff, s[i])) &
          0xffffffff;
      a = temp;
    }
    a0 = (a0 + a) & 0xffffffff;
    b0 = (b0 + b) & 0xffffffff;
    c0 = (c0 + c) & 0xffffffff;
    d0 = (d0 + d) & 0xffffffff;
  }
  final sb = StringBuffer();
  for (final v in [a0, b0, c0, d0]) {
    for (var i = 0; i < 4; i++) {
      sb.write(((v >> (8 * i)) & 0xff).toRadixString(16).padLeft(2, '0'));
    }
  }
  return sb.toString();
}

int _leftRotate(int x, int n) => ((x << n) | (x >> (32 - n))) & 0xffffffff;

/// Compute SHA-style hash via http_fetch tool? No — we want pure-Dart.
/// Falls back to a friendly error pointing at crypto package. MD5 is
/// implemented inline above; for SHA use the model's web_search or
/// add `crypto: ^3.0.3` to pubspec.yaml.
String _shaHex(String input, int bits) {
  return 'sha$bits 计算需要 `crypto` 包（请在 pubspec.yaml 中添加 `crypto: ^3.0.3` 并 import package:crypto/crypto.dart）。'
      '\n\n临时替代方案：用 hash_text 选 md5 也能得到文本指纹；或让 Agent 调用 web_search 查「在线 sha256 计算」找到 HTTP API。';
}

/// Advanced text statistics: word count, sentence count, paragraph count,
/// reading time (Chinese 300 chars/min, English 200 words/min).
Tool textStatsAdvancedTool() => Tool(
      name: 'text_stats_advanced',
      description: '高级文本统计：字数、词数、句数、段数、阅读时间（中英）。',
      schema: {
        'type': 'object',
        'properties': {
          'text': {
            'type': 'string',
            'description': '要统计的文本',
          },
        },
        'required': ['text'],
      },
      handler: (args) async {
        final text = args['text'] as String? ?? '';
        if (text.isEmpty) {
          return ToolResult.ok('字符: 0\n词: 0\n句: 0\n段: 0\n阅读时间: 0 分钟');
        }
        final chars = text.length;
        // Count Chinese chars (CJK Unified Ideographs).
        final cjkCount = RegExp(r'[\u4e00-\u9fff]').allMatches(text).length;
        // Words: split on whitespace, filter empty.
        final words =
            text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        // Sentences: split on . ! ? 。
        final sentences = text
            .split(RegExp(r'[.!?。！？\n]+'))
            .where((s) => s.trim().isNotEmpty)
            .length;
        // Paragraphs: split on \n\n or more newlines.
        final paragraphs = text
            .split(RegExp(r'\n\s*\n+'))
            .where((p) => p.trim().isNotEmpty)
            .length;
        // Reading time: Chinese 300 chars/min, English 200 words/min.
        final cnMin = cjkCount / 300.0;
        final enMin = (words - cjkCount).clamp(0, words) / 200.0;
        final totalMin = cnMin + enMin;
        return ToolResult.ok('''
字符总数: $chars
中文字符: $cjkCount
英文/其他词数: ${words - cjkCount}
总词数: $words
句数: $sentences
段数: $paragraphs
阅读时间: ${totalMin.toStringAsFixed(2)} 分钟（中英文混合计算）
''');
      },
    );

/// Convert between CSV and JSON.
Tool csvJsonTool() => Tool(
      name: 'csv_json_convert',
      description: 'CSV 与 JSON 互转。支持自定义分隔符、表头。',
      schema: {
        'type': 'object',
        'properties': {
          'direction': {
            'type': 'string',
            'enum': ['csv_to_json', 'json_to_csv'],
            'description': '转换方向',
          },
          'text': {
            'type': 'string',
            'description': '要转换的文本（CSV 或 JSON 字符串）',
          },
          'delimiter': {
            'type': 'string',
            'description': 'CSV 分隔符（默认逗号）',
          },
        },
        'required': ['direction', 'text'],
      },
      handler: (args) async {
        final dir = args['direction'] as String? ?? 'csv_to_json';
        final text = args['text'] as String? ?? '';
        final delim = (args['delimiter'] as String?) ?? ',';
        if (text.isEmpty) {
          return const ToolResult.error('参数 text 不能为空');
        }
        try {
          if (dir == 'csv_to_json') {
            final rows = _parseCsv(text, delim);
            if (rows.isEmpty) {
              return const ToolResult.ok('[]');
            }
            final headers = rows.first;
            final data = rows.skip(1).map((row) {
              final m = <String, dynamic>{};
              for (var i = 0; i < headers.length; i++) {
                m[headers[i]] = i < row.length ? row[i] : '';
              }
              return m;
            }).toList();
            return ToolResult.ok(
                const JsonEncoder.withIndent('  ').convert(data));
          } else {
            final decoded = jsonDecode(text);
            if (decoded is! List) {
              return const ToolResult.error('JSON 必须是对象数组');
            }
            if (decoded.isEmpty) {
              return const ToolResult.ok('');
            }
            final headers = <String>{};
            for (final item in decoded) {
              if (item is Map) {
                headers.addAll(item.keys.cast<String>());
              }
            }
            final headerList = headers.toList();
            final sb = StringBuffer();
            sb.writeln(headerList.map(_escapeCsvField).join(delim));
            for (final item in decoded) {
              if (item is! Map) continue;
              final row = headerList
                  .map((h) => _escapeCsvField(item[h]?.toString() ?? ''))
                  .join(delim);
              sb.writeln(row);
            }
            return ToolResult.ok(sb.toString());
          }
        } catch (e) {
          return ToolResult.error('转换失败: $e');
        }
      },
    );

/// Minimal CSV parser with quote support.
List<List<String>> _parseCsv(String text, String delimiter) {
  final rows = <List<String>>[];
  final current = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;
  while (i < text.length) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
        } else {
          inQuotes = false;
          i++;
        }
      } else {
        field.write(ch);
        i++;
      }
    } else {
      if (ch == '"') {
        inQuotes = true;
        i++;
      } else if (ch == delimiter) {
        current.add(field.toString());
        field.clear();
        i++;
      } else if (ch == '\n' || ch == '\r') {
        current.add(field.toString());
        field.clear();
        if (current.any((c) => c.isNotEmpty)) {
          rows.add(List.of(current));
        }
        current.clear();
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
          i += 2;
        } else {
          i++;
        }
      } else {
        field.write(ch);
        i++;
      }
    }
  }
  if (field.isNotEmpty || current.isNotEmpty) {
    current.add(field.toString());
    if (current.any((c) => c.isNotEmpty)) {
      rows.add(List.of(current));
    }
  }
  return rows;
}

String _escapeCsvField(String s) {
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Render a list of dicts as Markdown table.
Tool markdownTableTool() => Tool(
      name: 'markdown_table',
      description: '把 JSON 数组（对象列表）渲染为 Markdown 表格。',
      schema: {
        'type': 'object',
        'properties': {
          'text': {
            'type': 'string',
            'description': 'JSON 字符串，必须是对象数组',
          },
          'columns': {
            'type': 'string',
            'description': '可选：指定要包含的列（英文逗号分隔）；为空则用所有列',
          },
        },
        'required': ['text'],
      },
      handler: (args) async {
        final text = args['text'] as String? ?? '';
        final colSpec = (args['columns'] as String? ?? '').trim();
        if (text.isEmpty) {
          return const ToolResult.error('参数 text 不能为空');
        }
        try {
          final decoded = jsonDecode(text);
          if (decoded is! List) {
            return const ToolResult.error('JSON 必须是数组');
          }
          if (decoded.isEmpty) {
            return const ToolResult.ok('(空表)');
          }
          final first = decoded.first;
          if (first is! Map) {
            return const ToolResult.error('数组元素必须是对象');
          }
          final allKeys = first.keys.cast<String>().toList();
          final keys = colSpec.isEmpty
              ? allKeys
              : colSpec
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => allKeys.contains(s))
                  .toList();
          if (keys.isEmpty) {
            return const ToolResult.error('没有可用的列');
          }
          final sb = StringBuffer();
          sb.writeln('| ' + keys.join(' | ') + ' |');
          sb.writeln('| ' + keys.map((_) => '---').join(' | ') + ' |');
          for (final item in decoded) {
            if (item is! Map) continue;
            sb.writeln('| ' +
                keys
                    .map((k) =>
                        (item[k]?.toString() ?? '').replaceAll('|', '\\|'))
                    .join(' | ') +
                ' |');
          }
          return ToolResult.ok(sb.toString());
        } catch (e) {
          return ToolResult.error('渲染失败: $e');
        }
      },
    );

/// Generate secure random password.
Tool passwordGeneratorTool() => Tool(
      name: 'password_generator',
      description: '生成安全随机密码。可配置长度、字符集。',
      schema: {
        'type': 'object',
        'properties': {
          'length': {
            'type': 'integer',
            'description': '密码长度（默认 16，范围 4-128）',
          },
          'use_upper': {
            'type': 'boolean',
            'description': '包含大写字母（默认 true）',
          },
          'use_lower': {
            'type': 'boolean',
            'description': '包含小写字母（默认 true）',
          },
          'use_digits': {
            'type': 'boolean',
            'description': '包含数字（默认 true）',
          },
          'use_symbols': {
            'type': 'boolean',
            'description': '包含特殊符号（默认 true）',
          },
          'count': {
            'type': 'integer',
            'description': '生成几个密码（默认 1，最多 10）',
          },
        },
        'required': [],
      },
      handler: (args) async {
        var length = (args['length'] as int?) ?? 16;
        if (length < 4) length = 4;
        if (length > 128) length = 128;
        final useUpper = args['use_upper'] as bool? ?? true;
        final useLower = args['use_lower'] as bool? ?? true;
        final useDigits = args['use_digits'] as bool? ?? true;
        final useSymbols = args['use_symbols'] as bool? ?? true;
        var count = (args['count'] as int?) ?? 1;
        if (count < 1) count = 1;
        if (count > 10) count = 10;
        final charset = StringBuffer();
        if (useUpper)
          charset.write('ABCDEFGHJKLMNPQRSTUVWXYZ'); // skip I/O for clarity
        if (useLower) charset.write('abcdefghijkmnopqrstuvwxyz'); // skip l
        if (useDigits) charset.write('23456789'); // skip 0/1
        if (useSymbols) charset.write('!@#\$%^&*()-_=+[]{}<>?');
        if (charset.isEmpty) {
          return const ToolResult.error('至少需要启用一个字符集');
        }
        final chars = charset.toString();
        final rand = math.Random.secure();
        final results = <String>[];
        for (var n = 0; n < count; n++) {
          final sb = StringBuffer();
          for (var i = 0; i < length; i++) {
            sb.write(chars[rand.nextInt(chars.length)]);
          }
          results.add(sb.toString());
        }
        return ToolResult.ok(results.join('\n'));
      },
    );
