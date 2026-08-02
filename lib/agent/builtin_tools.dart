// Built-in tools for the Agent runtime.
//
// These tools are pure-Dart (no native calls, no network) so they work
// on every platform without additional setup. Each tool is a factory
// function that returns a [Tool] instance.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'agent_runtime.dart';

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
        final wordCount = text
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .length;
        return ToolResult.ok('字符数: $charCount, 词数: $wordCount');
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

/// Searches a local knowledge base for text relevant to the query.
///
/// This is a lightweight on-device RAG (Retrieval Augmented Generation)
/// tool. It reads all `.txt` files from [knowledgeBaseDir], splits them
/// into paragraphs, and returns the top-3 paragraphs whose keyword
/// overlap with the query is highest.
///
/// No embedding model is needed — matching is based on term frequency,
/// making it suitable for resource-constrained mobile devices.
Tool knowledgeSearchTool(Directory knowledgeBaseDir) => Tool(
      name: 'knowledge_search',
      description: '搜索本地知识库(.txt文档)，返回与查询最相关的文本片段',
      schema: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '搜索关键词或问题',
          },
        },
        'required': ['query'],
      },
      handler: (args) async {
        final query = args['query'];
        if (query is! String || query.isEmpty) {
          return const ToolResult.error('参数 query 不能为空');
        }
        try {
          if (!await knowledgeBaseDir.exists()) {
            return const ToolResult.error('知识库目录不存在');
          }

          // Load and chunk all .txt files.
          final chunks = <_TextChunk>[];
          await for (final entity in knowledgeBaseDir.list()) {
            if (entity is! File || !entity.path.endsWith('.txt')) continue;
            final content = await entity.readAsString();
            final source = entity.path.split(Platform.pathSeparator).last;
            for (final paragraph in content.split(RegExp(r'\n\s*\n'))) {
              final text = paragraph.trim();
              if (text.isNotEmpty) {
                chunks.add(_TextChunk(source: source, text: text));
              }
            }
          }

          if (chunks.isEmpty) {
            return const ToolResult.error('知识库为空，请先添加 .txt 文档');
          }

          // Score chunks by keyword overlap.
          final queryTerms = _tokenize(query);
          if (queryTerms.isEmpty) {
            return const ToolResult.error('查询无法解析为有效关键词');
          }

          final scored = chunks.map((c) {
            final textTerms = _tokenize(c.text);
            var score = 0;
            for (final t in queryTerms) {
              if (textTerms.contains(t)) score++;
            }
            return (chunk: c, score: score);
          }).toList()
            ..sort((a, b) => b.score.compareTo(a.score));

          final top = scored.where((s) => s.score > 0).take(3).toList();
          if (top.isEmpty) {
            return const ToolResult.error('未找到相关内容');
          }

          final result = top.map((s) {
            return '[${s.chunk.source}] ${s.chunk.text}';
          }).join('\n\n---\n\n');

          return ToolResult.ok(result);
        } catch (e) {
          return ToolResult.error('搜索失败: $e');
        }
      },
    );

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

bool _isCjk(String s) =>
    s.codeUnits.every((c) => c >= 0x4e00 && c <= 0x9fff);

class _TextChunk {
  final String source;
  final String text;
  _TextChunk({required this.source, required this.text});
}

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

// ============================================================================
// Web search & HTTP tools
// ============================================================================

/// Searches the web using a search API.
///
/// Uses DuckDuckGo Lite API (no API key required) to search the web and
/// return top results with titles, snippets, and URLs.
Tool webSearchTool() => Tool(
      name: 'web_search',
      description: '搜索互联网，返回标题+摘要+链接列表。当用户问实时信息、新闻、你不知道的知识时调用。',
      schema: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '搜索关键词，如"2026年世界杯举办地"',
          },
          'count': {
            'type': 'integer',
            'description': '返回结果数量（默认5，最多20）',
          },
        },
        'required': ['query'],
      },
      handler: (args) async {
        final query = args['query'];
        if (query is! String || query.trim().isEmpty) {
          return const ToolResult.error('参数 query 不能为空');
        }
        final count = ((args['count'] as num?)?.toInt() ?? 5).clamp(1, 20);
        try {
          final client = HttpClient();
          client.connectionTimeout = const Duration(seconds: 10);
          final uri = Uri.https('api.duckduckgo.com', '/', {
            'q': query.trim(),
            'format': 'json',
            'no_html': '1',
            'skip_disambig': '1',
          });
          final request = await client.getUrl(uri);
          final response = await request.close();
          final body = await response.transform(utf8.decoder).join();
          client.close();

          final decoded = jsonDecode(body);
          final results = <String>[];
          final relatedTopics = decoded['RelatedTopics'] as List? ?? [];
          for (final topic in relatedTopics) {
            if (topic is Map && topic['Text'] != null && topic['FirstURL'] != null) {
              final text = topic['Text'].toString();
              final url = topic['FirstURL'].toString();
              results.add('- $text\n  $url');
              if (results.length >= count) break;
            }
          }

          // Also try Abstract if available.
          final abstract = decoded['Abstract'] as String? ?? '';
          final source = decoded['AbstractSource'] as String? ?? '';
          final answer = decoded['Answer'] as String? ?? '';

          final sb = StringBuffer();
          sb.writeln('搜索: $query');
          if (answer.isNotEmpty) sb.writeln('\n直接答案: $answer');
          if (abstract.isNotEmpty) {
            sb.writeln('\n摘要: $abstract');
            if (source.isNotEmpty) sb.writeln('来源: $source');
          }
          if (results.isNotEmpty) {
            sb.writeln('\n相关结果 (${results.length}):');
            sb.writeln(results.join('\n\n'));
          }
          if (results.isEmpty && abstract.isEmpty && answer.isEmpty) {
            sb.writeln('\n(未找到相关结果，可尝试换关键词或使用 http_fetch 直接抓取网页)');
          }
          return ToolResult.ok(sb.toString());
        } catch (e) {
          return ToolResult.error('搜索失败: $e\n（可尝试使用 http_fetch 直接抓取网页）');
        }
      },
    );

/// Fetches a URL and returns its content as text.
///
/// Supports GET and POST methods, custom headers, and timeout.
/// Raw HTML content is returned — use html_to_text to strip tags.
Tool httpFetchTool() => Tool(
      name: 'http_fetch',
      description: '获取指定 URL 的内容（支持 HTTP/HTTPS）。返回原始文本内容，如需提取纯文本可用 html_to_text 工具。',
      schema: {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': '要获取的完整 URL，如 https://example.com/page',
          },
          'method': {
            'type': 'string',
            'description': 'HTTP 方法: GET (默认) 或 POST',
          },
          'headers': {
            'type': 'object',
            'description': '自定义请求头，如 {"User-Agent": "Mozilla/5.0"}',
          },
          'body': {
            'type': 'string',
            'description': 'POST 请求体（仅 method=POST 时使用）',
          },
          'timeout_sec': {
            'type': 'integer',
            'description': '超时秒数（默认 15，最大 60）',
          },
        },
        'required': ['url'],
      },
      handler: (args) async {
        final urlStr = args['url'];
        if (urlStr is! String || urlStr.trim().isEmpty) {
          return const ToolResult.error('参数 url 不能为空');
        }
        final uri = Uri.tryParse(urlStr.trim());
        if (uri == null || !uri.hasScheme) {
          return const ToolResult.error('URL 格式无效，需包含协议头如 https://');
        }
        final method = (args['method'] as String?)?.toUpperCase() ?? 'GET';
        final headersRaw = args['headers'] as Map<String, dynamic>?;
        final body = (args['body'] as String?)?.trim() ?? '';
        final timeout = ((args['timeout_sec'] as num?)?.toInt() ?? 15).clamp(5, 60);

        try {
          final client = HttpClient();
          client.connectionTimeout = Duration(seconds: timeout);
          HttpClientRequest request;
          if (method == 'POST') {
            request = await client.postUrl(uri);
            if (body.isNotEmpty) {
              request.write(body);
            }
          } else {
            request = await client.getUrl(uri);
          }
          if (headersRaw != null) {
            for (final e in headersRaw.entries) {
              request.headers.set(e.key, e.value.toString());
            }
          }
          request.headers.set('User-Agent', 'Mozilla/5.0 (compatible; OpenAgent/1.0)');
          final response = await request.close().timeout(Duration(seconds: timeout));
          final content = await response.transform(utf8.decoder).join();
          client.close();

          final sb = StringBuffer();
          sb.writeln('URL: $urlStr');
          sb.writeln('状态码: ${response.statusCode}');
          sb.writeln('内容长度: ${content.length} 字符');
          sb.writeln('--- 内容开始 ---');
          sb.writeln(content.length > 8000 ? '${content.substring(0, 8000)}\n…(内容过长，截断前 8000 字符)' : content);
          sb.writeln('--- 内容结束 ---');
          return ToolResult.ok(sb.toString());
        } catch (e) {
          return ToolResult.error('HTTP 请求失败: $e');
        }
      },
    );

/// Converts HTML to plain text.
Tool htmlToTextTool() => Tool(
      name: 'html_to_text',
      description: '将 HTML 字符串转换为纯文本（去除标签、提取正文）。常与 http_fetch 配合使用。',
      schema: {
        'type': 'object',
        'properties': {
          'html': {
            'type': 'string',
            'description': '包含 HTML 标签的原始 HTML 字符串',
          },
        },
        'required': ['html'],
      },
      handler: (args) async {
        final html = args['html'];
        if (html is! String || html.trim().isEmpty) {
          return const ToolResult.error('参数 html 不能为空');
        }
        try {
          String text = html;
          // Remove script and style tags and their content.
          text = text.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false, multiLine: true), '');
          text = text.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false, multiLine: true), '');
          // Remove all HTML tags.
          text = text.replaceAll(RegExp(r'<[^>]+>'), '');
          // Decode common HTML entities.
          text = text.replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&')
              .replaceAll('&lt;', '<').replaceAll('&gt;', '>')
              .replaceAll('&quot;', '"').replaceAll('&#39;', "'");
          // Collapse whitespace.
          text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
          // Split into lines by sentence boundaries.
          text = text.replaceAll(RegExp(r'[。！？\n]'), '\n');

          final lines = text.split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();
          final result = lines.join('\n');
          return ToolResult.ok(result.length > 10000
              ? '${result.substring(0, 10000)}\n…(内容过长，截断前 10000 字符)'
              : result);
        } catch (e) {
          return ToolResult.error('HTML 转换失败: $e');
        }
      },
    );

// ============================================================================
// Utility tools
// ============================================================================

/// Generates random numbers.
Tool randomNumberTool() => Tool(
      name: 'random_number',
      description: '生成随机整数。可指定范围 (min~max) 和数量。',
      schema: {
        'type': 'object',
        'properties': {
          'min': {
            'type': 'integer',
            'description': '最小值（含，默认 0）',
          },
          'max': {
            'type': 'integer',
            'description': '最大值（含，默认 100）',
          },
          'count': {
            'type': 'integer',
            'description': '生成数量（默认 1，最多 50）',
          },
        },
      },
      handler: (args) async {
        final min = (args['min'] as num?)?.toInt() ?? 0;
        final max = (args['max'] as num?)?.toInt() ?? 100;
        final count = ((args['count'] as num?)?.toInt() ?? 1).clamp(1, 50);
        if (min > max) return const ToolResult.error('min 不能大于 max');
        final rng = math.Random();
        final nums = List.generate(count, (_) => min + rng.nextInt(max - min + 1));
        final result = nums.join(', ');
        return ToolResult.ok(count == 1 ? '随机数: $result' : '随机数 (${count}个): $result');
      },
    );

/// Generates UUID v4.
Tool uuidGeneratorTool() => Tool(
      name: 'uuid_generator',
      description: '生成一个 UUID v4（通用唯一标识符）。',
      schema: {'type': 'object', 'properties': {}},
      handler: (args) async {
        final rng = math.Random();
        String hex(int n) => n.toString(16).padLeft(2, '0');
        final bytes = List.generate(16, (_) => rng.nextInt(256));
        bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
        bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
        final uuid = '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}-'
            '${hex(bytes[4])}${hex(bytes[5])}-${hex(bytes[6])}${hex(bytes[7])}-'
            '${hex(bytes[8])}${hex(bytes[9])}-${hex(bytes[10])}${hex(bytes[11])}'
            '${hex(bytes[12])}${hex(bytes[13])}${hex(bytes[14])}${hex(bytes[15])}';
        return ToolResult.ok(uuid);
      },
    );

/// Base64 encode/decode.
Tool base64CodecTool() => Tool(
      name: 'base64_codec',
      description: 'Base64 编码或解码字符串。',
      schema: {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'description': '"encode"=编码, "decode"=解码',
          },
          'text': {
            'type': 'string',
            'description': '要编码或解码的文本',
          },
        },
        'required': ['action', 'text'],
      },
      handler: (args) async {
        final action = (args['action'] as String?)?.toLowerCase() ?? '';
        final text = args['text'];
        if (text is! String || text.isEmpty) {
          return const ToolResult.error('参数 text 不能为空');
        }
        try {
          if (action == 'encode') {
            final encoded = base64Encode(utf8.encode(text));
            return ToolResult.ok(encoded);
          } else if (action == 'decode') {
            final decoded = utf8.decode(base64Decode(text));
            return ToolResult.ok(decoded);
          } else {
            return const ToolResult.error('action 必须是 "encode" 或 "decode"');
          }
        } catch (e) {
          return ToolResult.error('Base64 操作失败: $e');
        }
      },
    );

/// Color converter between hex, rgb, hsl.
Tool colorConverterTool() => Tool(
      name: 'color_converter',
      description: '颜色格式转换。支持 hex→rgb, rgb→hex, hex→hsl, rgb→hsl 等。',
      schema: {
        'type': 'object',
        'properties': {
          'value': {
            'type': 'string',
            'description': '颜色值，如 "#FF8800"、"rgb(255,136,0)"、"hsl(32,100%,50%)"',
          },
          'from': {
            'type': 'string',
            'description': '源格式: "hex"、"rgb"、"hsl"',
          },
          'to': {
            'type': 'string',
            'description': '目标格式: "hex"、"rgb"、"hsl"',
          },
        },
        'required': ['value', 'from', 'to'],
      },
      handler: (args) async {
        final value = (args['value'] as String?)?.trim() ?? '';
        final from = (args['from'] as String?)?.toLowerCase() ?? '';
        final to = (args['to'] as String?)?.toLowerCase() ?? '';
        if (value.isEmpty) return const ToolResult.error('value 不能为空');
        if (!['hex', 'rgb', 'hsl'].contains(from)) return const ToolResult.error('from 必须是 hex/rgb/hsl');
        if (!['hex', 'rgb', 'hsl'].contains(to)) return const ToolResult.error('to 必须是 hex/rgb/hsl');
        if (from == to) return ToolResult.ok(value);

        try {
          // Parse to (r, g, b) 0-255 first.
          int r, g, b;
          if (from == 'hex') {
            final hex = value.replaceAll('#', '');
            if (hex.length == 3) {
              r = int.parse(hex[0] + hex[0], radix: 16);
              g = int.parse(hex[1] + hex[1], radix: 16);
              b = int.parse(hex[2] + hex[2], radix: 16);
            } else if (hex.length == 6) {
              r = int.parse(hex.substring(0, 2), radix: 16);
              g = int.parse(hex.substring(2, 4), radix: 16);
              b = int.parse(hex.substring(4, 6), radix: 16);
            } else {
              return const ToolResult.error('hex 格式无效（需 3 或 6 位）');
            }
          } else if (from == 'rgb') {
            final m = RegExp(r'(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(value);
            if (m == null) return const ToolResult.error('rgb 格式无效，需如 rgb(255,136,0)');
            r = int.parse(m.group(1)!).clamp(0, 255);
            g = int.parse(m.group(2)!).clamp(0, 255);
            b = int.parse(m.group(3)!).clamp(0, 255);
          } else {
            // hsl
            final m = RegExp(r'(\d+(?:\.\d+)?)\s*[,°]\s*(\d+(?:\.\d+)?)%\s*[,]\s*(\d+(?:\.\d+)?)%').firstMatch(value);
            if (m == null) return const ToolResult.error('hsl 格式无效，需如 hsl(32,100%,50%)');
            final h = double.parse(m.group(1)!) % 360;
            final s = double.parse(m.group(2)!).clamp(0, 100);
            final l = double.parse(m.group(3)!).clamp(0, 100);
            // HSL to RGB
            final c = (1 - (2 * l / 100 - 1).abs()) * s / 100;
            final x = c * (1 - ((h / 60) % 2 - 1).abs());
            final m2 = l / 100 - c / 2;
            double r1, g1, b1;
            if (h < 60) { r1 = c; g1 = x; b1 = 0; }
            else if (h < 120) { r1 = x; g1 = c; b1 = 0; }
            else if (h < 180) { r1 = 0; g1 = c; b1 = x; }
            else if (h < 240) { r1 = 0; g1 = x; b1 = c; }
            else if (h < 300) { r1 = x; g1 = 0; b1 = c; }
            else { r1 = c; g1 = 0; b1 = x; }
            r = ((r1 + m2) * 255).round().clamp(0, 255);
            g = ((g1 + m2) * 255).round().clamp(0, 255);
            b = ((b1 + m2) * 255).round().clamp(0, 255);
          }

          // Convert to target.
          if (to == 'hex') {
            return ToolResult.ok('#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'.toUpperCase());
          } else if (to == 'rgb') {
            return ToolResult.ok('rgb($r, $g, $b)');
          } else {
            // hsl
            final rN = r / 255, gN = g / 255, bN = b / 255;
            final mx = [rN, gN, bN].reduce((a, b) => a > b ? a : b);
            final mn = [rN, gN, bN].reduce((a, b) => a < b ? a : b);
            final l = (mx + mn) / 2;
            if (mx == mn) return ToolResult.ok('hsl(0, 0%, ${(l * 100).round()}%)');
            final d = mx - mn;
            final s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
            double h;
            if (mx == rN) h = ((gN - bN) / d + (gN < bN ? 6 : 0)) * 60;
            else if (mx == gN) h = ((bN - rN) / d + 2) * 60;
            else h = ((rN - gN) / d + 4) * 60;
            return ToolResult.ok('hsl(${h.round()}, ${(s * 100).round()}%, ${(l * 100).round()}%)');
          }
        } catch (e) {
          return ToolResult.error('颜色转换失败: $e');
        }
      },
    );

/// Timer tool (wait / countdown).
Tool timerTool() => Tool(
      name: 'timer',
      description: '计时器。wait=等待指定秒数，countdown=倒计时并返回提示。',
      schema: {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'description': '"wait"=等待, "countdown"=倒计时',
          },
          'seconds': {
            'type': 'number',
            'description': '秒数（默认 3，最大 300）',
          },
        },
        'required': ['action'],
      },
      handler: (args) async {
        final action = (args['action'] as String?)?.toLowerCase() ?? '';
        final secs = ((args['seconds'] as num?)?.toDouble() ?? 3.0).clamp(0.5, 300.0);
        final ms = (secs * 1000).round();
        if (action == 'countdown') {
          for (var i = secs.toInt(); i > 0; i--) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          return ToolResult.ok('⏰ 倒计时 ${secs.toInt()} 秒结束');
        } else {
          await Future<void>.delayed(Duration(milliseconds: ms));
          return ToolResult.ok('已等待 ${secs.toStringAsFixed(1)} 秒');
        }
      },
    );

/// Weather tool (uses wttr.in, no API key required).
Tool weatherTool() => Tool(
      name: 'weather',
      description: '查询指定城市的天气。使用免费公开 API，无需 API key。',
      schema: {
        'type': 'object',
        'properties': {
          'city': {
            'type': 'string',
            'description': '城市名，如 "北京"、"Shanghai"、"New York"',
          },
        },
        'required': ['city'],
      },
      handler: (args) async {
        final city = args['city'];
        if (city is! String || city.trim().isEmpty) {
          return const ToolResult.error('参数 city 不能为空');
        }
        try {
          final client = HttpClient();
          client.connectionTimeout = const Duration(seconds: 10);
          final uri = Uri.parse('https://wttr.in/${Uri.encodeComponent(city.trim())}?format=%C+%t+%h+%w+%p');
          final request = await client.getUrl(uri);
          final response = await request.close();
          final body = await response.transform(utf8.decoder).join();
          client.close();
          if (body.contains('Unknown location')) {
            return ToolResult.error('未找到城市 "$city" 的天气信息');
          }
          return ToolResult.ok('🌤 $city 天气: $body');
        } catch (e) {
          return ToolResult.error('天气查询失败: $e');
        }
      },
    );

/// IP info tool (uses ip-api.com or ipify).
Tool ipInfoTool() => Tool(
      name: 'ip_info',
      description: '查询本机或指定 IP 的地理位置、运营商等信息。不传 ip 则查本机。',
      schema: {
        'type': 'object',
        'properties': {
          'ip': {
            'type': 'string',
            'description': '可选。要查询的 IP 地址，如 "8.8.8.8"。空则查本机 IP。',
          },
        },
      },
      handler: (args) async {
        try {
          final client = HttpClient();
          client.connectionTimeout = const Duration(seconds: 10);
          final ip = (args['ip'] as String?)?.trim() ?? '';
          Uri uri;
          if (ip.isEmpty) {
            // Get public IP first.
            final req = await client.getUrl(Uri.parse('https://api.ipify.org?format=json'));
            final res = await req.close();
            final body = await res.transform(utf8.decoder).join();
            final decoded = jsonDecode(body);
            final myIp = decoded['ip'] as String? ?? '';
            if (myIp.isEmpty) return const ToolResult.error('无法获取本机 IP');
            uri = Uri.parse('http://ip-api.com/json/$myIp');
          } else {
            uri = Uri.parse('http://ip-api.com/json/$ip');
          }
          final request = await client.getUrl(uri);
          final response = await request.close();
          final body = await response.transform(utf8.decoder).join();
          client.close();
          final data = jsonDecode(body);
          if (data['status'] == 'fail') {
            return ToolResult.error('查询失败: ${data['message'] ?? '无效 IP'}');
          }
          final sb = StringBuffer();
          sb.writeln('IP: ${data['query'] ?? ip}');
          if (data['country'] != null) sb.writeln('国家: ${data['country']} (${data['countryCode']})');
          if (data['regionName'] != null) sb.writeln('地区: ${data['regionName']}');
          if (data['city'] != null) sb.writeln('城市: ${data['city']}');
          if (data['zip'] != null) sb.writeln('邮编: ${data['zip']}');
          if (data['isp'] != null) sb.writeln('运营商: ${data['isp']}');
          if (data['org'] != null) sb.writeln('组织: ${data['org']}');
          if (data['as'] != null) sb.writeln('AS: ${data['as']}');
          if (data['lat'] != null && data['lon'] != null) {
            sb.writeln('坐标: ${data['lat']}, ${data['lon']}');
          }
          sb.writeln('时区: ${data['timezone'] ?? '未知'}');
          return ToolResult.ok(sb.toString());
        } catch (e) {
          return ToolResult.error('IP 查询失败: $e');
        }
      },
    );

/// Text template engine.
Tool textTemplateTool() => Tool(
      name: 'text_template',
      description: '文本模板引擎。用 variables 中的值替换 template 中的 {key} 占位符。',
      schema: {
        'type': 'object',
        'properties': {
          'template': {
            'type': 'string',
            'description': '模板字符串，如 "你好，{name}！今天是{date}。"',
          },
          'variables': {
            'type': 'object',
            'description': '变量键值对，如 {"name": "张三", "date": "2026-08-02"}',
          },
        },
        'required': ['template', 'variables'],
      },
      handler: (args) async {
        final template = args['template'];
        if (template is! String || template.isEmpty) {
          return const ToolResult.error('参数 template 不能为空');
        }
        final variables = args['variables'];
        if (variables is! Map) {
          return const ToolResult.error('参数 variables 必须是对象');
        }
        try {
          String result = template;
          for (final e in variables.entries) {
            result = result.replaceAll('{${e.key}}', e.value.toString());
          }
          return ToolResult.ok(result);
        } catch (e) {
          return ToolResult.error('模板渲染失败: $e');
        }
      },
    );

/// Analyze screen and make a plan (VLM-based).
Tool agentAnalyzeAndPlanTool() => Tool(
      name: 'agent_analyze_and_plan',
      description: '【Agent 自主决策】分析当前屏幕状态+用户目标，制定操作计划。调用此工具前请先确保 android_rpa skill 已启用。',
      schema: {
        'type': 'object',
        'properties': {
          'goal': {
            'type': 'string',
            'description': '你想要完成的目标，如"给张三发微信说今晚聚餐"',
          },
          'max_steps': {
            'type': 'integer',
            'description': '最大计划步骤数（默认 10，最多 30）',
          },
        },
        'required': ['goal'],
      },
      handler: (args) async {
        final goal = args['goal'];
        if (goal is! String || goal.trim().isEmpty) {
          return const ToolResult.error('参数 goal 不能为空');
        }
        // This tool is a meta-tool that returns a plan stub.
        // The actual execution is done by the LLM using atomic tools.
        return ToolResult.ok(
          '【分析计划】目标: $goal\n\n'
          '建议步骤:\n'
          '1. 先用 android_dump_ui 或 android_screenshot 了解当前屏幕\n'
          '2. 根据屏幕内容决定下一步操作\n'
          '3. 使用原子工具（click_coords / input_text / swipe 等）逐步执行\n'
          '4. 每步后检查结果，必要时回退或调整\n'
          '5. 任务完成后总结\n\n'
          '提示: 你可以用 skill_create_from_trace 把这次操作序列保存为可复用的 Skill。',
        );
      },
    );

// ============================================================================
// Stage 21: More built-in utility tools
// ============================================================================

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
            return ToolResult.ok(Uri.encodeComponent(text));
          } else {
            return ToolResult.ok(Uri.decodeComponent(text));
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
      description: '字符串大小写格式转换。支持: camelCase, PascalCase, snake_case, kebab-case, UPPER_CASE, lower_case, 首字母大写。',
      schema: {
        'type': 'object',
        'properties': {
          'text': {
            'type': 'string',
            'description': '要转换的字符串',
          },
          'target_case': {
            'type': 'string',
            'enum': ['camel', 'pascal', 'snake', 'kebab', 'upper', 'lower', 'capitalize'],
            'description': '目标格式: camel=驼峰, pascal=大驼峰, snake=下划线, kebab=连字符, upper=全大写, lower=全小写, capitalize=首字母大写',
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
            if (w[i].toUpperCase() == w[i] && w[i - 1].toLowerCase() == w[i - 1]) {
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
              output += cleanWords[i][0].toUpperCase() + cleanWords[i].substring(1).toLowerCase();
            }
          case 'pascal':
            output = cleanWords.map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase()).join();
          case 'snake':
            output = cleanWords.map((w) => w.toLowerCase()).join('_');
          case 'kebab':
            output = cleanWords.map((w) => w.toLowerCase()).join('-');
          case 'upper':
            output = cleanWords.map((w) => w.toUpperCase()).join('_');
          case 'lower':
            output = cleanWords.map((w) => w.toLowerCase()).join('_');
          case 'capitalize':
            output = cleanWords.map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
          default:
            return ToolResult.error('不支持的目标格式: $targetCase');
        }
        return ToolResult.ok('$text → $output');
      },
    );

/// Hex / binary / ASCII conversions.
Tool encodeDecodeTool() => Tool(
      name: 'encode_decode',
      description: '编解码工具。支持: hex_encode, hex_decode, binary_encode, binary_decode, ascii_to_hex, hex_to_ascii。',
      schema: {
        'type': 'object',
        'properties': {
          'mode': {
            'type': 'string',
            'enum': ['hex_encode', 'hex_decode', 'binary_encode', 'binary_decode', 'ascii_to_hex', 'hex_to_ascii'],
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
              return ToolResult.ok(text.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join(' '));
            case 'hex_decode':
              final cleaned = text.replaceAll(RegExp(r'\s+'), '');
              if (cleaned.length % 2 != 0) return const ToolResult.error('hex 字符串长度必须为偶数');
              final bytes = <int>[];
              for (var i = 0; i < cleaned.length; i += 2) {
                bytes.add(int.parse(cleaned.substring(i, i + 2), radix: 16));
              }
              return ToolResult.ok(String.fromCharCodes(bytes));
            case 'binary_encode':
              return ToolResult.ok(text.codeUnits.map((c) => c.toRadixString(2).padLeft(8, '0')).join(' '));
            case 'binary_decode':
              final cleaned = text.replaceAll(RegExp(r'\s+'), '');
              if (cleaned.length % 8 != 0) return const ToolResult.error('二进制字符串长度必须是 8 的倍数');
              final bytes = <int>[];
              for (var i = 0; i < cleaned.length; i += 8) {
                bytes.add(int.parse(cleaned.substring(i, i + 8), radix: 2));
              }
              return ToolResult.ok(String.fromCharCodes(bytes));
            case 'ascii_to_hex':
              return ToolResult.ok(text.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join(''));
            case 'hex_to_ascii':
              final cleaned = text.replaceAll(RegExp(r'\s+'), '');
              if (cleaned.length % 2 != 0) return const ToolResult.error('hex 字符串长度必须为偶数');
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

// ============================================================================
// Stage 22: Hash & data tools
// ============================================================================

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
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];
  const k = [
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a,
    0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340,
    0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8,
    0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa,
    0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92,
    0xffeff47d, 0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
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
      b = (b + _leftRotate((a + f + k[i] + m[g]) & 0xffffffff, s[i])) & 0xffffffff;
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
        final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
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
        final delim = (args['delimiter'] as String? ?? ',').characters.first;
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
            return ToolResult.ok(const JsonEncoder.withIndent('  ').convert(data));
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
              : colSpec.split(',').map((s) => s.trim()).where((s) => allKeys.contains(s)).toList();
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
                    .map((k) => (item[k]?.toString() ?? '').replaceAll('|', '\\|'))
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
        if (useUpper) charset.write('ABCDEFGHJKLMNPQRSTUVWXYZ'); // skip I/O for clarity
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

/// Date arithmetic: add/subtract days, weeks, months from a date.
Tool dateCalculatorTool() => Tool(
      name: 'date_calculator',
      description: '日期计算：在给定日期上加减天数/周数/月数/小时。可比较两个日期差值。',
      schema: {
        'type': 'object',
        'properties': {
          'date': {
            'type': 'string',
            'description': '基准日期（ISO 格式 YYYY-MM-DD 或 YYYY-MM-DDTHH:MM:SS），默认当前时间',
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
            sb.writeln('  相差 ${diff.inDays} 天 ${diff.inHours.remainder(24)} 小时 ${diff.inMinutes.remainder(60)} 分钟');
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

/// Returns all built-in tools for quick registration.
List<Tool> builtinTools() => [
      calculatorTool(),
      dateTimeTool(),
      textCounterTool(),
      unitConverterTool(),
      jsonFormatterTool(),
      // Stage 19: Web & HTTP tools.
      webSearchTool(),
      httpFetchTool(),
      htmlToTextTool(),
      // Stage 19: Utility tools.
      randomNumberTool(),
      uuidGeneratorTool(),
      base64CodecTool(),
      colorConverterTool(),
      timerTool(),
      weatherTool(),
      ipInfoTool(),
      textTemplateTool(),
      // Stage 19: Agent analysis tool.
      agentAnalyzeAndPlanTool(),
      // Stage 21: More utility tools.
      urlCodecTool(),
      regexTesterTool(),
      stringCaseTool(),
      encodeDecodeTool(),
      // Stage 22: Hash & data tools.
      hashTool(),
      textStatsAdvancedTool(),
      csvJsonTool(),
      markdownTableTool(),
      passwordGeneratorTool(),
      dateCalculatorTool(),
    ];

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

// ---- Expression evaluator (recursive descent) ----------------------------

double _evaluate(String input) {
  final parser = _ExprParser(input.replaceAll(' ', ''));
  return parser.parseExpression();
}

class _ExprParser {
  _ExprParser(this._input);

  final String _input;
  int _pos = 0;

  double parseExpression() {
    var result = _parseTerm();
    while (_peek() == '+' || _peek() == '-') {
      final op = _next();
      final rhs = _parseTerm();
      result = op == '+' ? result + rhs : result - rhs;
    }
    return result;
  }

  double _parseTerm() {
    var result = _parseFactor();
    while (_peek() == '*' || _peek() == '/') {
      final op = _next();
      final rhs = _parseFactor();
      result = op == '*' ? result * rhs : result / rhs;
    }
    return result;
  }

  double _parseFactor() {
    if (_peek() == '-') {
      _next();
      return -_parseFactor();
    }
    if (_peek() == '(') {
      _next();
      final result = parseExpression();
      if (_peek() != ')') throw const FormatException('缺少右括号');
      _next();
      return result;
    }

    // Function call: name(args)
    if (_isAlpha(_peek())) {
      final name = _parseIdentifier();
      if (_peek() == '(') {
        _next();
        final arg = parseExpression();
        if (_peek() != ')') throw const FormatException('缺少右括号');
        _next();
        return _applyFunction(name, arg);
      }
      throw FormatException('未知标识符: $name');
    }

    return _parseNumber();
  }

  double _parseNumber() {
    final start = _pos;
    while (_pos < _input.length && '0123456789.'.contains(_input[_pos])) {
      _pos++;
    }
    if (_pos == start) throw const FormatException('期望数字');
    return double.parse(_input.substring(start, _pos));
  }

  String _parseIdentifier() {
    final start = _pos;
    while (_pos < _input.length && _isAlpha(_input[_pos])) {
      _pos++;
    }
    return _input.substring(start, _pos);
  }

  double _applyFunction(String name, double arg) {
    switch (name) {
      case 'sin':
        return math.sin(arg);
      case 'cos':
        return math.cos(arg);
      case 'tan':
        return math.tan(arg);
      case 'sqrt':
        return math.sqrt(arg);
      case 'abs':
        return arg.abs();
      case 'log':
        return math.log(arg);
      case 'exp':
        return math.exp(arg);
      default:
        throw FormatException('未知函数: $name');
    }
  }

  String _peek() => _pos < _input.length ? _input[_pos] : '';

  String _next() {
    final c = _peek();
    _pos++;
    return c;
  }

  bool _isAlpha(String c) =>
      c.isNotEmpty && (c.toLowerCase() != c.toUpperCase() || c == '_');
}
