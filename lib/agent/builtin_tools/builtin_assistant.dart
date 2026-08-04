part of '../builtin_tools.dart';

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
          sb.writeln(content.length > kContentPreviewMax ? '${content.substring(0, kContentPreviewMax)}\n…(内容过长，截断前 $kContentPreviewMax 字符)' : content);
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
          return ToolResult.ok(result.length > kContentPreviewLong
              ? '${result.substring(0, kContentPreviewLong)}\n…(内容过长，截断前 $kContentPreviewLong 字符)'
              : result);
        } catch (e) {
          return ToolResult.error('HTML 转换失败: $e');
        }
      },
    );

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
        return ToolResult.ok(count == 1 ? '随机数: $result' : '随机数 ($count个): $result');
      },
    );

/// Generates UUID v4.
Tool uuidGeneratorTool() => Tool(
      name: 'uuid_generator',
      description: '生成一个 UUID v4（通用唯一标识符）。',
      schema: {'type': 'object', 'properties': {}},
      handler: (args) async {
        final rng = math.Random();
        String hex(int n) => n.toRadixString(16).padLeft(2, '0');
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