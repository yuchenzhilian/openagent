part of '../android_tools.dart';

// ============================================================================
// H8 开放通用工具：不硬编码流程，交给 (LLM + VLM) 自主决策
// 目标：让模型自己判断"做什么"和"怎么做"，我们只提供原子能力和开放接口
// ============================================================================

/// ——— H8-1: 长按屏幕坐标（弹出菜单/选中文字/拖拽等场景）———
Tool _longPressTool(AndroidAutomationService s) => Tool(
      name: 'android_long_press',
      description:
          '长按屏幕指定坐标 (x,y)。用于：弹出右键菜单、选中文字、拖放图标、游戏里蓄力等场景。'
          '默认长按 800ms，可自定义时长。',
      schema: _props({
        'x': {'type': 'integer', 'description': '横坐标像素值'},
        'y': {'type': 'integer', 'description': '纵坐标像素值'},
        'duration_ms': {
          'type': 'integer',
          'description': '长按持续毫秒数 (默认 800，拖东西可调 1500~3000)',
        },
      }, required: [
        'x',
        'y'
      ]),
      handler: (args) async {
        final x = args['x'] as int?;
        final y = args['y'] as int?;
        if (x == null || y == null) {
          return const ToolResult.error('缺少参数 x 或 y');
        }
        final dur = (args['duration_ms'] as num?)?.toInt() ?? 800;
        final ok = await s.longPress(x, y, durationMs: dur);
        return ok
            ? ToolResult.ok('已长按坐标 ($x,$y) 持续 ${dur}ms')
            : const ToolResult.error('长按失败 (可能无障碍/Shizuku 权限未开启)');
      },
    );

/// ——— H8-2: 剪贴板读写（复制/粘贴数据，让模型自由搬运文字）———
Tool _clipboardTool(AndroidAutomationService s) => Tool(
      name: 'android_clipboard',
      description:
          '读或写系统剪贴板。操作场景：从 App A 复制文字 → 粘贴到 App B；'
          '把一大段中文先写入剪贴板 → 再到输入框长按粘贴 (避开中文输入法不兼容问题)。',
      schema: _props({
        'action': {
          'type': 'string',
          'description': 'get=读取剪贴板内容返回给你；set=写入指定文字到剪贴板',
        },
        'text': {
          'type': 'string',
          'description': '当 action=set 时必填：要写入剪贴板的文字内容',
        },
      }, required: [
        'action'
      ]),
      handler: (args) async {
        final action = (args['action'] as String? ?? '').toLowerCase();
        if (action == 'get') {
          final content = await s.getClipboard();
          return content.isEmpty
              ? const ToolResult.ok('剪贴板当前为空')
              : ToolResult.ok('剪贴板内容:\n$content');
        }
        if (action == 'set') {
          final text = args['text'] as String?;
          if (text == null || text.isEmpty) {
            return const ToolResult.error('action=set 时参数 text 不能为空');
          }
          final ok = await s.setClipboard(text);
          return ok
              ? ToolResult.ok('已写入剪贴板 (${text.length} 字)')
              : const ToolResult.error('写剪贴板失败 (可改用 input_text 直接输入)');
        }
        return const ToolResult.error('action 必须是 get 或 set');
      },
    );

/// ——— H8-3: 自定义路径手势（画任意曲线：解锁图案 / 画签名 / 拖拽多个点 / 游戏技能方向）———
Tool _customGestureTool(AndroidAutomationService s) => Tool(
      name: 'android_custom_gesture',
      description:
          '按你给的坐标点数组画一条连续手势路径。用途：手机九宫格图案解锁、画签名、'
          '拖动物品跨屏、游戏技能方向摇杆画任意曲线、复杂滑动组合动作等。'
          'points 是数组，每项含 x,y 两个像素坐标；至少要 2 个点 (起点+终点)；想画曲线就多给几个中间点。',
      schema: _props({
        'points': {
          'type': 'array',
          'description':
              '坐标点数组，例: [{"x":100,"y":800},{"x":500,"y":400},{"x":900,"y":800}] → 画一条 V 型手势',
          'items': {
            'type': 'object',
            'properties': {
              'x': {'type': 'integer'},
              'y': {'type': 'integer'},
            },
          },
        },
        'total_duration_ms': {
          'type': 'integer',
          'description': '整条手势总时长毫秒 (默认 500。慢拖/签名可调 1500~3000)',
        },
      }, required: [
        'points'
      ]),
      handler: (args) async {
        final raw = args['points'];
        if (raw is! List || raw.length < 2) {
          return const ToolResult.error('points 必须是包含至少 2 个点的数组');
        }
        final points = <Map<String, int>>[];
        for (final item in raw) {
          if (item is Map) {
            final x = (item['x'] as num?)?.toInt();
            final y = (item['y'] as num?)?.toInt();
            if (x != null && y != null) {
              points.add({'x': x, 'y': y});
            }
          }
        }
        if (points.length < 2) {
          return const ToolResult.error('points 每项必须有合法 x,y (整数)');
        }
        final dur = (args['total_duration_ms'] as num?)?.toInt() ?? 500;
        final ok = await s.customGesture(points, totalDurationMs: dur);
        return ok
            ? ToolResult.ok('已执行自定义手势 (${points.length} 个点, 总时长 ${dur}ms)')
            : const ToolResult.error('自定义手势执行失败');
      },
    );

/// ——— H8-4: 通用 Shell 命令执行（把完整 shell 权限交给模型自由发挥）———
Tool _shellExecTool(AndroidAutomationService s) => Tool(
      name: 'android_shell_exec',
      description:
          '【开放通用权限】直接通过 Shizuku (shell 用户身份) 或 Root 执行任意 Android shell 命令。'
          'L1 无障碍做不到的事 (比如直接改系统设置、模拟设备按键、查看数据库、pm/包管理、'
          'am 发送广播/启动组件、settings put 修改安全设置、iptables/网络管理等) 都可以通过这里自由实现。'
          '⚠ 你作为 AI 请先确认命令安全再执行。高危操作 (如 rm -rf、pm uninstall 系统应用) 先在回答里警告用户。',
      schema: _props({
        'command': {
          'type': 'string',
          'description':
              '任意 Linux/Android shell 命令，可带管道 && || 等。例: svc wifi disable  或  settings put system screen_brightness 128  或  dumpsys activity top | grep ACTIVITY',
        },
        'timeout_sec': {
          'type': 'integer',
          'description': '超时秒数 (默认 30，复杂命令可调大)',
        },
      }, required: [
        'command'
      ]),
      handler: (args) async {
        final cmd = args['command'] as String?;
        if (cmd == null || cmd.trim().isEmpty) {
          return const ToolResult.error('command 不能为空');
        }
        final r = await s.gshell(cmd);
        final sb = StringBuffer();
        sb.writeln('命令: $cmd');
        sb.writeln('执行成功: ${r.ok}, exitCode=${r.exitCode}');
        if (r.stdout.isNotEmpty) sb.writeln('--- stdout ---\n${r.stdout}');
        if (r.stderr.isNotEmpty) sb.writeln('--- stderr ---\n${r.stderr}');
        return (r.ok && r.exitCode == 0)
            ? ToolResult.ok(sb.toString())
            : ToolResult.error(sb.toString());
      },
    );

/// ——— H8-5: VLM 自由视觉分析 + 原始回答 ———
Tool _visionFreeAnalyzeTool(
  AndroidAutomationService s,
  Future<String> Function(String imagePath, String question) visionAnalyze,
) =>
    Tool(
      name: 'android_vision_ask',
      description:
          '【多模态核心·开放】截图当前手机屏幕，然后你 (LLM) 可以向 Omni VLM 提任意开放问题，'
          'VLM 会按自己的理解自由回答 (不限制输出格式、不一定返回 JSON)，返回的完整回答直接给你 (LLM) 读，'
          '你再基于 VLM 的回答自己判断下一步调用哪个工具 (click_coords / swipe / custom_gesture / shell…)。'
          '⚠ 这个工具和 android_game_auto_vlm_loop 的区别：本工具不解析回答、不自动执行任何动作、'
          '100% 由你 (LLM+VLM) 自主决策，不会被代码层的硬编码规则干扰。',
      schema: _props({
        'question': {
          'type': 'string',
          'description':
              '【你自己的问题】向多模态模型问任意问题。',
        },
        'auto_screenshot': {
          'type': 'boolean',
          'description':
              'true=先自动截图再提问 (默认, 99% 情况用这个)；false=你已经截过图只想复用上次结果',
        },
      }, required: [
        'question'
      ]),
      handler: (args) async {
        final q = args['question'] as String?;
        if (q == null || q.trim().isEmpty) {
          return const ToolResult.error('请输入你要问 VLM 的问题 (question 参数)');
        }
        final autoShot = args['auto_screenshot'] as bool? ?? true;
        String? img;
        if (autoShot) {
          img = await s.takeScreenshot();
          if (img == null) {
            return const ToolResult.error('截图失败 (请确认已授予截屏权限或开启 Root)');
          }
        } else {
          img = await s.takeScreenshot();
        }
        final answer = await visionAnalyze(img!, q);
        final sb = StringBuffer('✅ VLM 开放回答 (未解析, 由你 LLM 自主理解)\n');
        sb.writeln('你提问: $q');
        sb.writeln('截图路径: $img');
        sb.writeln('--- VLM 原始回答 ---\n$answer');
        return ToolResult.ok(sb.toString());
      },
    );

// ============================================================================
// H10 开放原子能力：无任何流程硬编码，100% 由 (LLM+VLM) 自由组合
// ============================================================================

/// ——— H10-1: 发送任意 Android Intent ———
Tool _sendIntentTool(AndroidAutomationService s) => Tool(
      name: 'android_send_intent',
      description:
          '【最开放·原子】发送任意 Android Intent，100% 自由度。',
      schema: _props({
        'action': {'type': 'string', 'description': 'Intent Action'},
        'data': {'type': 'string', 'description': 'Intent Data URI'},
        'type': {'type': 'string', 'description': 'MIME Type'},
        'component': {'type': 'string', 'description': '直接指定组件包名/类名'},
        'package': {'type': 'string', 'description': '限制只在某包名内解析'},
        'categories': {
          'type': 'array',
          'description': 'Intent Categories 列表',
          'items': {'type': 'string'},
        },
        'extras_string': {
          'type': 'object',
          'description': '字符串额外参数 (key→value)',
          'additionalProperties': {'type': 'string'},
        },
        'extras_int': {
          'type': 'object',
          'description': '整数额外参数 key→int',
          'additionalProperties': {'type': 'integer'},
        },
        'extras_bool': {
          'type': 'object',
          'description': '布尔额外参数 key→bool',
          'additionalProperties': {'type': 'boolean'},
        },
        'wait_for_result': {
          'type': 'boolean',
          'description': 'true=等待启动结果并返回',
        },
      }),
      handler: (args) async {
        Map<String, String> parseMapStr(dynamic v) {
          if (v is! Map) return <String, String>{};
          return Map<String, String>.fromEntries(
            v.entries.where((e) => e.value is String).map((e) => MapEntry(e.key as String, e.value as String)),
          );
        }
        Map<String, int> parseMapInt(dynamic v) {
          if (v is! Map) return <String, int>{};
          return Map<String, int>.fromEntries(
            v.entries
                .where((e) => e.value is num)
                .map((e) => MapEntry(e.key as String, (e.value as num).toInt())),
          );
        }
        Map<String, bool> parseMapBool(dynamic v) {
          if (v is! Map) return <String, bool>{};
          return Map<String, bool>.fromEntries(
            v.entries.where((e) => e.value is bool).map((e) => MapEntry(e.key as String, e.value as bool)),
          );
        }

        final r = await s.sendIntent(
          action: args['action'] as String?,
          data: args['data'] as String?,
          type: args['type'] as String?,
          component: args['component'] as String?,
          package: args['package'] as String?,
          waitForResult: args['wait_for_result'] as bool? ?? false,
          categories: (args['categories'] as List?)?.whereType<String>().toList(),
          extrasString: parseMapStr(args['extras_string']),
          extrasInt: parseMapInt(args['extras_int']),
          extrasBool: parseMapBool(args['extras_bool']),
        );
        final sb = StringBuffer('Intent 执行 ${(r.ok && r.exitCode == 0) ? '成功' : '失败 (exit=${r.exitCode})'}\n');
        if (r.stdout.isNotEmpty) sb.writeln('stdout:\n${r.stdout}');
        if (r.stderr.isNotEmpty) sb.writeln('stderr:\n${r.stderr}');
        return (r.ok && r.exitCode == 0)
            ? ToolResult.ok(sb.toString())
            : ToolResult.error(sb.toString());
      },
    );

/// ——— H10-2: 文件系统 ———
Tool _fileTool(AndroidAutomationService s) => Tool(
      name: 'android_file',
      description:
          '【开放原子】文件系统任意操作：读文本文件、写文本文件、列出目录内容、删除文件/目录、检查是否存在。',
      schema: _props({
        'op': {
          'type': 'string',
          'description': '操作类型：read=读文件 | write=写文件 (覆盖) | append=追加写 | list=列目录 | delete=删文件/目录 | exists=查存在',
        },
        'path': {
          'type': 'string',
          'description': '文件或目录的绝对路径',
        },
        'content': {
          'type': 'string',
          'description': 'op=write 或 op=append 时必填：要写入的文本内容',
        },
      }, required: [
        'op',
        'path'
      ]),
      handler: (args) async {
        final op = (args['op'] as String? ?? '').toLowerCase();
        final path = (args['path'] as String? ?? '').trim();
        if (path.isEmpty) return const ToolResult.error('path 不能为空');

        switch (op) {
          case 'read':
            final c = await s.fileRead(path);
            return c.isEmpty
                ? const ToolResult.ok('文件为空或不存在')
                : ToolResult.ok('文件内容:\n$c');
          case 'write':
          case 'append':
            final content = args['content'] as String? ?? '';
            final ok = await s.fileWrite(path, content, append: op == 'append');
            return ok
                ? ToolResult.ok('${op == 'append' ? '追加写入' : '写入'} $path 成功 (${content.length} 字)')
                : ToolResult.error('写入失败');
          case 'list':
            final list = await s.fileListDir(path);
            return list.isEmpty
                ? ToolResult.ok('目录 $path 为空或不存在')
                : ToolResult.ok('目录 $path:\n${list.join('\n')}');
          case 'delete':
            final ok = await s.fileDelete(path);
            return ok
                ? ToolResult.ok('已删除: $path')
                : ToolResult.error('删除失败');
          case 'exists':
            final ok = await s.fileExists(path);
            return ToolResult.ok(ok ? '$path 存在' : '$path 不存在');
          default:
            return const ToolResult.error('op 必须是: read / write / append / list / delete / exists');
        }
      },
    );

/// ——— H10-3: 查询 App 详情 ———
Tool _appInfoTool(AndroidAutomationService s) => Tool(
      name: 'android_app_info',
      description:
          '【开放信息】查询任意 App 的完整原始信息。',
      schema: _props({
        'package_name': {
          'type': 'string',
          'description': '要查询的 App 包名',
        },
        'verbose': {
          'type': 'boolean',
          'description': 'true=返回完整信息；false=只返回前 80 行核心字段 (默认)',
        },
      }, required: [
        'package_name'
      ]),
      handler: (args) async {
        final pkg = (args['package_name'] as String? ?? '').trim();
        if (pkg.isEmpty) return const ToolResult.error('package_name 不能为空');
        final verbose = args['verbose'] as bool? ?? false;
        final info = await s.appInfo(pkg, verbose: verbose);
        return info.isEmpty
            ? ToolResult.error('没有获取到 $pkg 的信息')
            : ToolResult.ok(info);
      },
    );

/// ——— H10-4: 读取通知栏所有通知 ———
Tool _notificationListTool(AndroidAutomationService s) => Tool(
      name: 'android_get_notifications',
      description:
          '【开放信息】读取手机状态栏当前所有通知。',
      schema: _props({
        'limit': {
          'type': 'integer',
          'description': '最多返回多少条通知 (默认 30，最大 100)',
        },
      }),
      handler: (args) async {
        final limit = ((args['limit'] as num?)?.toInt() ?? 30).clamp(1, 100);
        final out = await s.getNotifications(limit: limit);
        return out.trim().isEmpty
            ? const ToolResult.ok('当前通知栏为空，或未授予"通知访问"权限')
            : ToolResult.ok('通知栏内容 (最多 $limit 条):\n$out');
      },
    );

/// ——— H10-5: WindowManager 底层 Dump ———
Tool _dumpWindowsTool(AndroidAutomationService s) => Tool(
      name: 'android_dump_windows',
      description:
          '【开放信息】输出 WindowManager 底层状态。',
      schema: _props({
        'limit_lines': {
          'type': 'integer',
          'description': '最多返回多少行 (默认 200，最大 1000)',
        },
      }),
      handler: (args) async {
        final limit = ((args['limit_lines'] as num?)?.toInt() ?? 200).clamp(20, 1000);
        final out = await s.dumpWindows(limitLines: limit);
        return ToolResult.ok(out);
      },
    );

// ============================================================================
// H11 × 4：开放原子能力——联系人 / 电量网络 / 双卡短信 / 传感器
// ============================================================================

/// H11-1: 联系人查询
Tool _queryContactsTool(AndroidAutomationService s) => Tool(
      name: 'android_query_contacts',
      description:
          '【开放信息】从手机通讯录查询联系人。',
      schema: _props({
        'kw': {
          'type': 'string',
          'description': '关键词模糊搜索 (匹配姓名/号码/邮箱任一)',
        },
        'limit': {
          'type': 'integer',
          'description': '最多返回多少个联系人 (默认 50，最大 500)',
        },
      }),
      handler: (args) async {
        final kw = (args['kw'] as String?) ?? '';
        final limit = ((args['limit'] as num?)?.toInt() ?? 50).clamp(1, 500);
        final out = await s.queryContacts(kw: kw, limit: limit);
        return ToolResult.ok(out);
      },
    );

/// H11-2: 设备状态综合 Dump
Tool _deviceStatusTool(AndroidAutomationService s) => Tool(
      name: 'android_get_device_status',
      description:
          '【开放信息】一次性返回手机当前的【电量/充电状态/电压/温度】【移动网络运营商+信号+数据连接状态】等。',
      schema: _props({}),
      handler: (_) async {
        final out = await s.getDeviceStatus();
        return ToolResult.ok(out);
      },
    );

/// H11-3: 双卡短信——发送 + 查询
Tool _sendSmsTool(AndroidAutomationService s) => Tool(
      name: 'android_send_sms',
      description:
          '【开放操作】通过手机 SIM 卡直接发送纯文本短信。',
      schema: _props({
        'phone': {
          'type': 'string',
          'description': '收短信的手机号',
        },
        'message': {
          'type': 'string',
          'description': '短信正文',
        },
        'sim_slot': {
          'type': 'integer',
          'description': '1=卡1发送 / 2=卡2发送 / 0=系统默认 (默认 0)',
        },
      }, required: [
        'phone',
        'message'
      ]),
      handler: (args) async {
        final phone = (args['phone'] as String?)?.trim() ?? '';
        final msg = (args['message'] as String?) ?? '';
        if (phone.isEmpty) return const ToolResult.error('phone 不能为空');
        if (msg.isEmpty) return const ToolResult.error('message 不能为空');
        final sim = ((args['sim_slot'] as num?)?.toInt() ?? 0).clamp(0, 2);
        final r = await s.sendSms(phone: phone, message: msg, simSlot: sim);
        return r.ok
            ? ToolResult.ok('✅ 短信已下发 (sim_slot=$sim, to=$phone)\n${r.stdout}${r.stderr.isEmpty ? '' : '\nerr=${r.stderr}'}')
            : ToolResult.error('❌ 短信发送失败 exit=${r.exitCode}: ${r.stderr.isEmpty ? r.stdout : r.stderr}');
      },
    );

Tool _querySmsTool(AndroidAutomationService s) => Tool(
      name: 'android_query_recent_sms',
      description:
          '【开放信息】读取手机最近 N 条短信。',
      schema: _props({
        'box': {
          'type': 'string',
          'description': '查哪个箱: "inbox"=收到的 (默认) / "sent"=已发出的',
        },
        'limit': {
          'type': 'integer',
          'description': '最多返回多少条 (默认 20 最大 200)',
        },
      }),
      handler: (args) async {
        final box = (args['box'] as String?)?.trim() == 'sent' ? 'sent' : 'inbox';
        final limit = ((args['limit'] as num?)?.toInt() ?? 20).clamp(1, 200);
        final out = await s.queryRecentSms(box: box, limit: limit);
        return ToolResult.ok(out);
      },
    );

/// H11-4: 传感器列表 + 实时采样
Tool _sensorsTool(AndroidAutomationService s) => Tool(
      name: 'android_get_sensors',
      description:
          '【开放信息】列出手机所有传感器，并可选地对加速度/陀螺仪/光/接近/重力等采样 N 次。',
      schema: _props({
        'list_all': {
          'type': 'boolean',
          'description': 'true=先列出手机支持的所有传感器 (默认 true)',
        },
        'sample_types': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': '指定要采样的传感器类型 ID 数组。',
        },
        'samples_per_sensor': {
          'type': 'integer',
          'description': '采样次数，每次间隔 200ms；默认 1 次，最大 30',
        },
      }),
      handler: (args) async {
        final listAll = (args['list_all'] as bool?) ?? true;
        final typesRaw = args['sample_types'] as List<dynamic>? ?? const <dynamic>[];
        final types = typesRaw
            .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0)
            .where((e) => e > 0)
            .toList(growable: false);
        final samples = ((args['samples_per_sensor'] as num?)?.toInt() ?? 1).clamp(1, 30);
        final out = await s.getSensors(
          listAll: listAll,
          sampleTypes: types,
          samplesPerSensor: samples,
        );
        return ToolResult.ok(out);
      },
    );

// ============================================================================
// H13 — execute_plan 多步编排：由 LLM 写完整 steps[]，代码按顺序执行不做判断
// H14 — agent_memory KV：由 LLM 自己决定存/读/删什么记忆
// ============================================================================

/// H13: execute_plan —— 让 LLM 一次性下发最多 N 步工具调用，代码严格按 LLM 写的顺序跑，
///   不做任何 if/else、不做"这个步骤看起来错所以跳过"、不做自动重试，
///   甚至"要不要在某个错误时停止"也由 LLM 通过 stop_on 参数指定。
///   每步结果都完整收集、按顺序返回，LLM 可以一口气把"打开微信→搜 XXX→点第一条→输入 XXX→发送"
///   这类固定流程一次性下发，省掉 N 轮端侧推理。
Tool buildExecutePlanTool(
  Future<ToolResult> Function(String name, Map<String, dynamic> args) executor,
) =>
    Tool(
      name: 'android_execute_plan',
      description:
          '【多步编排 · 开放核心】你 (LLM) 自己把接下来 N 步 (最多 50 步) 需要调用的工具写成 steps[] 数组，'
          '我 (代码) 100% 按你写的顺序严格执行，不做任何修改、不做任何跳过、不做条件判断。'
          '⚠ 这不是智能流程：我不分析步骤是否合理、不判断某个工具的参数对不对、失败了也不帮你重试，'
          '要不要停、在哪停、失败后怎么走完全由你 (LLM) 通过 stop_on / step.expect_ok 决定。'
          '典型用途：把"打开微信→点击通讯录→搜索张三→点头像→输入消息→发送"这种固定 6 步的场景一次下发，省 5 次推理。'
          '⚠ 嵌套禁止：steps 里的工具名不能再是 android_execute_plan 或其他 meta 工具 (防止死循环)。',
      schema: _props({
        'steps': {
          'type': 'array',
          'description': '''按顺序执行的工具序列，数组元素是 Object 结构：
{
  "id": "步骤唯一字符串ID (可选，你LLM用来定位哪一步出问题，随便写)",
  "name": "要调用的工具名，如 android_open_app / android_click_by_text / android_send_intent ...",
  "args": { "参数key1": "参数value1" },
  "delay_ms": 0,          // 本步执行完之后停多少毫秒再跑下一步 (给页面加载的间隔，你自己定)
  "expect_ok": true,      // 你预期这一步应该成功；true 且实际失败时 stop_on=first_unexpected 就停
  "save_as": "可选key名"   // 如果非空，就把本步 ToolResult.output 存在内存 KV 中，后续步骤 args 里可以用字符串占位符 {{save_as名}} 引用
}
''',
          'items': {'type': 'object'},
        },
        'stop_on': {
          'type': 'string',
          'description':
              '【你LLM决定的停止策略】可选值: "never"=50步都跑完绝不中断 (默认)；"first_error"=遇到任何 ToolResult.isError=true 立刻停；"first_unexpected"=只要某步的 isError 和你写的 expect_ok 不一致就停；"first_match_text"=某步 output 中包含你写的 stop_if_contains 字符串就停；"stop_flag_set"=某步 save_as 存的值等于你 stop_flag_key 且字符串包含 "STOP" 就停。完全由你指定，代码不做自己的判断。',
        },
        'stop_if_contains': {
          'type': 'string',
          'description': 'stop_on="first_match_text" 时生效：只要任一步 output 里包含这个子串，立刻停止 (不区分大小写)。例 "未找到文字 发送"',
        },
        'stop_flag_key': {
          'type': 'string',
          'description': 'stop_on="stop_flag_set" 时生效：检查 save_as 存到这个 key 的值里是否包含子串 "STOP"，包含就停。',
        },
        'timeout_ms_per_step': {
          'type': 'integer',
          'description': '每步最大执行毫秒数 (默认 30000=30秒)。超时则记为 error，并根据 stop_on 决定是否停。',
        },
      }, required: [
        'steps'
      ]),
      handler: (args) async {
        final rawSteps = args['steps'] as List<dynamic>? ?? const [];
        if (rawSteps.isEmpty) return const ToolResult.error('steps 不能为空数组');
        if (rawSteps.length > 50) return const ToolResult.error('steps 最多 50 步，请拆成多个 plan 执行');
        final stopOn = (args['stop_on'] as String?)?.trim() ?? 'never';
        final stopContains = args['stop_if_contains'] as String? ?? '';
        final stopFlagKey = args['stop_flag_key'] as String? ?? '';
        final perStepTimeout = ((args['timeout_ms_per_step'] as num?)?.toInt() ?? 30000).clamp(500, 600000);

        // save_as 的内存 KV (仅本次 plan 内有效 + 持久到 agent_memory 相同后端? 简单起见先 plan 内有效)
        final kv = <String, String>{};
        bool shouldStop = false;
        final out = StringBuffer();
        out.writeln('📋 android_execute_plan 开始 (共 ${rawSteps.length} 步, stop_on=$stopOn)');
        var ran = 0;
        for (var i = 0; i < rawSteps.length; i++) {
          if (shouldStop) {
            out.writeln('⏹ #${i + 1} 由 stop_on 策略主动停止，不再执行剩余 ${rawSteps.length - i} 步');
            break;
          }
          final step = rawSteps[i] is Map<String, dynamic>
              ? rawSteps[i] as Map<String, dynamic>
              : <String, dynamic>{};
          final id = step['id']?.toString() ?? 'step_${i + 1}';
          final name = step['name']?.toString() ?? '';
          final delay = ((step['delay_ms'] as num?)?.toInt() ?? 0).clamp(0, 60000);
          final expectOk = step['expect_ok'] as bool? ?? true;
          final saveAs = step['save_as']?.toString();
          if (name.isEmpty) {
            out.writeln('❌ #${i + 1}($id): 缺工具名，记为 error 并按 stop_on 决定');
            if (stopOn == 'first_error' || (stopOn == 'first_unexpected' && expectOk)) {
              shouldStop = true;
            }
            ran++;
            continue;
          }
          // 防嵌套：禁止 execute_plan 自己套自己
          if (name == 'android_execute_plan') {
            out.writeln('⛔ #${i + 1}($id): 嵌套 android_execute_plan 禁止 (避免死循环)，跳过');
            if (stopOn == 'first_error' || (stopOn == 'first_unexpected' && expectOk)) {
              shouldStop = true;
            }
            ran++;
            continue;
          }
          // args 占位符替换：字符串值里的 {{xxx}} 用 kv['xxx'] 替换
          dynamic applyTpl(dynamic v) {
            if (v is String) {
              return v.replaceAllMapped(RegExp(r'\{\{\s*([a-zA-Z0-9_\-]+)\s*\}\}'), (m) {
                return kv[m.group(1)] ?? m.group(0)!;
              });
            }
            if (v is List) {
              return v.map<dynamic>(applyTpl).toList(growable: false);
            }
            if (v is Map) {
              return v.map<dynamic, dynamic>((k, vv) => MapEntry(k is String ? k : k.toString(), applyTpl(vv)));
            }
            return v;
          }

          final rawArgs = step['args'];
          final Map<String, dynamic> resolvedArgs = rawArgs is Map
              ? (rawArgs as Map).map<dynamic, dynamic>((k, v) => MapEntry(k is String ? k : k.toString(), applyTpl(v)))
              : <String, dynamic>{};
          // 执行
          try {
            final result = await executor(name, resolvedArgs as Map<String, dynamic>)
                .timeout(Duration(milliseconds: perStepTimeout));
            ran++;
            final isErr = result.isError;
            final output = result.output;
            out.writeln('${isErr ? '❌' : '✅'} #${i + 1}($id) $name: ${isErr ? "ERROR" : "OK"}');
            if (output.isNotEmpty) {
              final preview = output.length > kToolOutputPreviewMax ? '${output.substring(0, kToolOutputPreviewMax)}…(截断)' : output;
              out.writeln('  output: $preview');
            }
            // save_as
            if (saveAs != null && saveAs.isNotEmpty) {
              kv[saveAs] = output;
              out.writeln('  💾 save_as[$saveAs]=${output.length}chars');
            }
            // Stop decision
            if (stopOn == 'first_error' && isErr) {
              shouldStop = true;
              out.writeln('  ⏹ stop_on=first_error 触发，停止');
            } else if (stopOn == 'first_unexpected' && isErr != expectOk) {
              shouldStop = true;
              out.writeln('  ⏹ stop_on=first_unexpected 触发 (expect_ok=$expectOk, 实际=${isErr ? "ERROR" : "OK"})');
            } else if (stopOn == 'first_match_text' && stopContains.isNotEmpty &&
                output.toLowerCase().contains(stopContains.toLowerCase())) {
              shouldStop = true;
              out.writeln('  ⏹ stop_on=first_match_text 触发 (包含"$stopContains")');
            } else if (stopOn == 'stop_flag_set' && saveAs != null && stopFlagKey.isNotEmpty &&
                saveAs == stopFlagKey && output.contains('STOP')) {
              shouldStop = true;
              out.writeln('  ⏹ stop_on=stop_flag_set 触发 (save_as=$saveAs 包含 STOP)');
            }
            // delay
            if (delay > 0 && !shouldStop) {
              await Future<void>.delayed(Duration(milliseconds: delay));
            }
          } on TimeoutException {
            out.writeln('⏰ #${i + 1}($id) $name: 超时 (${perStepTimeout}ms)');
            if (stopOn == 'first_error' || (stopOn == 'first_unexpected' && expectOk)) {
              shouldStop = true;
            }
          } catch (e) {
            out.writeln('💥 #${i + 1}($id) $name: 异常 $e');
            if (stopOn == 'first_error' || (stopOn == 'first_unexpected' && expectOk)) {
              shouldStop = true;
            }
          }
        }
        out.writeln('\n📋 plan 结束: 执行 $ran/${rawSteps.length} 步');
        return ToolResult.ok(out.toString());
      },
    );

// ============================================================================
// H14 — Agent 长期记忆 KV：完全由 LLM 决定存什么、读什么、删什么
//   不做"自动总结"、不做"自动记对话"，代码层就是一个纯粹的 persistent KV。
// ============================================================================

/// agent_memory 工具的 4 个子动作合并为同一个工具 (用 op 区分)，减少工具名占用。
Tool buildAgentMemoryTool(AgentMemoryBackend backend) => Tool(
      name: 'agent_memory',
      description:
          '【长期KV记忆 · 开放】你 (LLM) 自己决定要记住什么、何时读取、何时删除。'
          '⚠ 代码层不自动帮你记任何东西 —— 没有自动摘要、没有自动归档、没有自动清理过期，完全由你 (LLM) 通过 op 参数操作。'
          '建议用法：遇到用户的手机号/姓名/常用App/按钮坐标/上一步 save_as 的值想跨 plan/跨 session 保留时就 set；'
          '下次新会话开始时先 list key 全量列一遍前缀，把需要的全 get 回来。'
          '典型 key 命名建议：`u.phone` / `u.home_addr` / `pkg.wechat.search_btn_bounds` / `last.wx_chat_top_3` / `last.game.player_pos`',
      schema: _props({
        'op': {
          'type': 'string',
          'description':
              '"set"=写或覆盖 key=value；"get"=读 key；"delete"=删 key；"list"=按前缀列出所有 key (若 prefix 为空列出全部 200 个以内)；"clear_prefix"=删除所有前缀匹配的 key',
        },
        'key': {
          'type': 'string',
          'description': 'op=set/get/delete 必填。key 请用 ASCII + 点分命名，最大 240 字。例 "u.phone" / "pkg.com.tencent.mm.home_tab_bounds"',
        },
        'value': {
          'type': 'string',
          'description': 'op=set 必填。要存的值任意字符串，建议 ≤32KB。可以存 JSON.stringify 的结构化数据。',
        },
        'prefix': {
          'type': 'string',
          'description': 'op=list / clear_prefix 时生效：匹配以这个字符串开头的所有 key。空串="" 表示全部。',
        },
        'limit': {
          'type': 'integer',
          'description': 'op=list 时最多返回多少条 (默认 100，最大 1000)',
        },
      }, required: [
        'op'
      ]),
      handler: (args) async {
        final op = (args['op'] as String?)?.trim().toLowerCase() ?? '';
        try {
          switch (op) {
            case 'set':
              {
                final key = (args['key'] as String?)?.trim() ?? '';
                final val = (args['value'] as String?) ?? '';
                if (key.isEmpty) return const ToolResult.error('op=set: key 不能为空');
                if (key.length > 240) return const ToolResult.error('op=set: key 超长 (>240)');
                await backend.set(key, val);
                return ToolResult.ok('✅ SET ok  key=$key  bytes=${val.length}');
              }
            case 'get':
              {
                final key = (args['key'] as String?)?.trim() ?? '';
                if (key.isEmpty) return const ToolResult.error('op=get: key 不能为空');
                final v = await backend.get(key);
                if (v == null) return ToolResult.ok('(空 key=$key 不存在)');
                return ToolResult.ok('value (len=${v.length}):\n$v');
              }
            case 'delete':
              {
                final key = (args['key'] as String?)?.trim() ?? '';
                if (key.isEmpty) return const ToolResult.error('op=delete: key 不能为空');
                final existed = await backend.delete(key);
                return ToolResult.ok(existed ? '✅ DELETE ok  key=$key' : '⚠ DELETE no-op: key=$key 不存在');
              }
            case 'list':
              {
                final prefix = (args['prefix'] as String?) ?? '';
                final limit = ((args['limit'] as num?)?.toInt() ?? 100).clamp(1, 1000);
                final entries = await backend.list(prefix: prefix, limit: limit);
                final sb = StringBuffer('✅ LIST prefix="$prefix" 返回 ${entries.length} 条 (limit=$limit)\n');
                for (final e in entries) {
                  final v = e.value;
                  final short = v.length > kLogArgMaxLen ? '${v.substring(0, kLogArgMaxLen)}…' : v.replaceAll('\n', '↵');
                  sb.writeln('  ${e.key}  len=${v.length}  $short');
                }
                return ToolResult.ok(sb.toString());
              }
            case 'clear_prefix':
              {
                final prefix = (args['prefix'] as String?) ?? '';
                if (prefix.isEmpty) return const ToolResult.error('op=clear_prefix: prefix 不能为空 (怕你把整个库清掉)');
                final n = await backend.clearPrefix(prefix);
                return ToolResult.ok('✅ CLEAR_PREFIX "$prefix" 删除 $n 条');
              }
            default:
              return ToolResult.error('未知 op=$op，可选值 set/get/delete/list/clear_prefix');
          }
        } catch (e) {
          return ToolResult.error('agent_memory 异常: $e');
        }
      },
    );

/// agent_memory 后端接口：默认用本地文件 (Android context.getFilesDir + dart:io)。
/// 简单实现：一个 JSON 文件，key→value，key 超过 5000 条时淘汰最早修改的 10% (LRU-ish)。
abstract class AgentMemoryBackend {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
  Future<bool> delete(String key);
  Future<List<({String key, String value, DateTime mtime})>> list({String prefix = '', int limit = 100});
  Future<int> clearPrefix(String prefix);
}

/// 基于本地文件的简易 AgentMemoryBackend (单文件 JSON + 内存缓存 + 异步落盘)。
class FileAgentMemoryBackend implements AgentMemoryBackend {
  FileAgentMemoryBackend(this._filePath);
  final String _filePath;
  final Map<String, ({String v, int mt})> _cache = {};
  bool _dirty = false;

  Future<void> _load() async {
    if (_cache.isNotEmpty) return;
    final f = File(_filePath);
    if (!await f.exists()) return;
    try {
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (k is String && v is Map) {
            final val = v['v'];
            final mt = v['mt'];
            if (val is String) _cache[k] = (v: val, mt: mt is int ? mt : DateTime.now().millisecondsSinceEpoch);
          }
        });
      }
    } catch (_) {
      _cache.clear();
    }
  }

  Future<void> _flush() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      final dir = p.dirname(_filePath);
      if (dir.isNotEmpty && !await Directory(dir).exists()) {
        await Directory(dir).create(recursive: true);
      }
      final out = <String, dynamic>{};
      _cache.forEach((k, v) => out[k] = <String, dynamic>{'v': v.v, 'mt': v.mt});
      await File(_filePath).writeAsString(jsonEncode(out), flush: true);
    } catch (_) {
    }
  }

  void _evictIfNeeded() {
    if (_cache.length < 5000) return;
    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.mt.compareTo(b.value.mt));
    final del = (entries.length * 0.1).ceil();
    for (var i = 0; i < del; i++) {
      _cache.remove(entries[i].key);
    }
    _dirty = true;
  }

  @override
  Future<String?> get(String key) async {
    await _load();
    final v = _cache[key];
    if (v == null) return null;
    _cache[key] = (v: v.v, mt: DateTime.now().millisecondsSinceEpoch);
    _dirty = true;
    await _flush();
    return v.v;
  }

  @override
  Future<void> set(String key, String value) async {
    await _load();
    _cache[key] = (v: value, mt: DateTime.now().millisecondsSinceEpoch);
    _evictIfNeeded();
    _dirty = true;
    await _flush();
  }

  @override
  Future<bool> delete(String key) async {
    await _load();
    final existed = _cache.remove(key) != null;
    if (existed) {
      _dirty = true;
      await _flush();
    }
    return existed;
  }

  @override
  Future<List<({String key, String value, DateTime mtime})>> list({String prefix = '', int limit = 100}) async {
    await _load();
    final entries = _cache.entries
        .where((e) => e.key.startsWith(prefix))
        .map((e) => (
              key: e.key,
              value: e.value.v,
              mtime: DateTime.fromMillisecondsSinceEpoch(e.value.mt),
            ))
        .toList()
      ..sort((a, b) => b.mtime.compareTo(a.mtime));
    return entries.take(limit).toList(growable: false);
  }

  @override
  Future<int> clearPrefix(String prefix) async {
    await _load();
    final keys = _cache.keys.where((k) => k.startsWith(prefix)).toList(growable: false);
    if (keys.isEmpty) return 0;
    for (final k in keys) {
      _cache.remove(k);
    }
    _dirty = true;
    await _flush();
    return keys.length;
  }
}

// ============================================================================
// 录制回放工具
// ============================================================================

/// Start recording a macro of touch events.
Tool _recordMacroTool(AndroidAutomationService s) => Tool(
      name: 'android_record_macro',
      description: '开始录制操作序列（screenrecord + 触摸事件）。录制完成后调用 android_play_macro 回放。',
      schema: _props({
        'name': {
          'type': 'string',
          'description': '录制的名称，如 "send_wechat_message"',
        },
        'max_seconds': {
          'type': 'integer',
          'description': '最大录制秒数（默认 30）',
        },
      }, required: ['name']),
      handler: (args) async {
        final name = args['name'] as String? ?? '';
        final maxSec = (args['max_seconds'] as num?)?.toInt() ?? 30;
        if (name.isEmpty) return const ToolResult.error('参数 name 不能为空');
        if (name.contains('/') || name.contains('..')) {
          return const ToolResult.error('name 不能包含路径符号');
        }
        final r = await s.gshell(
            'settings put system pointer_location 1 2>/dev/null; '
            'screenrecord --time-limit $maxSec /sdcard/${name}_raw.mp4 2>/dev/null &');
        return ToolResult.ok(
            '✅ 开始录制 "$name" (最多 ${maxSec}s)\n'
            '操作完成后，调用 android_stop_macro 停止录制。');
      },
    );

/// Stop recording and save the macro.
Tool _stopMacroTool(AndroidAutomationService s) => Tool(
      name: 'android_stop_macro',
      description: '停止录制，保存操作序列为可回放文件。',
      schema: _props({
        'name': {
          'type': 'string',
          'description': '要停止的录制名称',
        },
      }, required: ['name']),
      handler: (args) async {
        final name = args['name'] as String? ?? '';
        if (name.isEmpty) return const ToolResult.error('参数 name 不能为空');
        final r = await s.gshell(
            'pkill -f "screenrecord.*${name}_raw" 2>/dev/null; '
            'settings put system pointer_location 0 2>/dev/null');
        return ToolResult.ok(
            '✅ 录制已停止\n'
            '原始文件: /sdcard/${name}_raw.mp4\n'
            '提示: 可在 skill_create_from_trace 中手动描述操作序列保存为 Skill。\n'
            '更精确的宏录制需要 Android 12+ getPointerEvents API。');
      },
    );

/// List saved macros.
Tool _listMacroTool() => Tool(
      name: 'android_list_macros',
      description: '列出已录制的操作宏文件。',
      schema: _props({}),
      handler: (args) async {
        final r = await AndroidAutomationService.instance
            .gshell('ls -la /sdcard/*_raw.mp4 2>/dev/null | head -n 30');
        if (!r.ok || r.stdout.trim().isEmpty) {
          return const ToolResult.ok('(没有已录制的宏)');
        }
        return ToolResult.ok(r.stdout);
      },
    );

// ============================================================================
// Stage 31: VLM 多模态增强 — 屏幕变化检测/区域分析/截图哈希
// ============================================================================

/// 屏幕变化检测：比较两次截图，判断屏幕是否发生变化。
/// 使用 MD5 哈希比较，可检测指定区域的差异。
Tool _screenChangeDetectTool(
  AndroidAutomationService s,
  Future<String> Function(String imagePath, String question) visionAnalyze,
) => Tool(
      name: 'android_screen_change_detect',
      description:
          '【VLM 增强】检测屏幕是否发生变化。可选：比较当前截图与上次截图、'
          '或指定区域是否有变化。适合用来检测游戏战斗是否结束、页面加载是否完成。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['snapshot', 'compare', 'watch_region', 'clear'],
          'description': 'snapshot=拍一张快照存为基准, compare=比较当前屏幕与基准快照, '
              'watch_region=监控区域变化(用VLM分析), clear=清除基准快照',
        },
        'region_name': {
          'type': 'string',
          'description': 'watch_region 时指定的区域名称，如 "战斗区域" 或 "对话框"',
        },
        'question': {
          'type': 'string',
          'description': 'watch_region 时问 VLM 的问题，如 "这个区域的内容是否发生了变化？"',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'snapshot';
        final region = (args['region_name'] as String?) ?? '';
        final question = (args['question'] as String?) ?? '这个区域的内容是什么？';
        final basePath = '/sdcard/Android/data/com.openagent.openagent/files/vlm_snapshot';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        if (action == 'snapshot') {
          final img = await s.takeScreenshot();
          if (img == null) return const ToolResult.error('截图失败');
          await s.gshell('cp "$img" "$basePath.png" 2>/dev/null');
          steps.add('基准快照已保存: $basePath.png');
          final hash = await s.gshell('md5sum "$img" 2>/dev/null | cut -d" " -f1');
          if (hash.ok) {
            await s.gshell('echo "${hash.stdout.trim()}" > "$basePath.hash" 2>/dev/null');
          }
          return ToolResult.ok('✅ 基准快照已保存:\n${r()}\n下次用 compare 比较变化');
        }

        if (action == 'compare') {
          final img = await s.takeScreenshot();
          if (img == null) return const ToolResult.error('截图失败');
          final check = await s.gshell('ls "$basePath.png" 2>/dev/null');
          if (!check.ok) {
            return const ToolResult.error('未找到基准快照，先用 snapshot 保存基准');
          }
          final hash1 = await s.gshell('cat "$basePath.hash" 2>/dev/null');
          final hash2 = await s.gshell('md5sum "$img" 2>/dev/null | cut -d" " -f1');
          if (hash1.ok && hash2.ok && hash1.stdout.trim() == hash2.stdout.trim()) {
            return ToolResult.ok('✅ 屏幕未发生变化（哈希一致）');
          }
          final answer = await visionAnalyze(img, 
              '比较这张截图与上一张截图，判断屏幕是否发生了变化。'
              '如果有变化，描述发生了哪些变化。（新截图已提供，上一张已有基准）');
          return ToolResult.ok('⚠ 屏幕发生了变化:\n$answer');
        }

        if (action == 'watch_region') {
          final img = await s.takeScreenshot();
          if (img == null) return const ToolResult.error('截图失败');
          final q = region.isNotEmpty
              ? '请关注屏幕中 "$region" 区域（$question）'
              : question;
          final answer = await visionAnalyze(img, q);
          return ToolResult.ok('📷 区域分析结果:\n$answer');
        }

        if (action == 'clear') {
          await s.gshell('rm -f "$basePath.png" "$basePath.hash" 2>/dev/null');
          return ToolResult.ok('✅ 基准快照已清除');
        }

        return ToolResult.error('未知操作: $action');
      },
    );

/// 截图指纹哈希：计算当前屏幕的哈希值，用于快速检测变化。
Tool _screenHashTool(AndroidAutomationService s) => Tool(
      name: 'android_screen_hash',
      description:
          '【VLM 增强】计算当前屏幕截图的哈希值（MD5 前 16 位）。'
          '可用于快速判断屏幕是否变化，无需 VLM 分析。'
          '适合循环检测：连续比较哈希值，不同则说明屏幕变了。',
      schema: _props({}),
      handler: (_) async {
        final img = await s.takeScreenshot();
        if (img == null) return const ToolResult.error('截图失败');
        final r = await s.gshell('md5sum "$img" 2>/dev/null | cut -c1-16');
        if (r.ok && r.stdout.trim().isNotEmpty) {
          return ToolResult.ok('🖼 屏幕指纹: ${r.stdout.trim()}');
        }
        final r2 = await s.gshell('ls -la "$img" 2>/dev/null | awk \'{print \$5,\$8}\'');
        return ToolResult.ok('🖼 屏幕指纹: ${r2.stdout.trim()}');
      },
    );

/// 区域 VLM 分析：只分析截图中的指定区域（裁剪后交给 VLM）。
Tool _visionAnalyzeRegionTool(
  AndroidAutomationService s,
  Future<String> Function(String imagePath, String question) visionAnalyze,
) => Tool(
      name: 'android_vision_analyze_region',
      description:
          '【VLM 增强】只分析屏幕截图中的指定区域（矩形）。'
          '适合：只关注屏幕某个局部（如通知栏、某个按钮所在区域、游戏结算面板等），'
          '减少 VLM 的干扰信息，提高识别准确率。',
      schema: _props({
        'x': {'type': 'number', 'description': '区域左上角 x (像素或0~1百分比)'},
        'y': {'type': 'number', 'description': '区域左上角 y'},
        'width': {'type': 'number', 'description': '区域宽度 (像素或0~1百分比)'},
        'height': {'type': 'number', 'description': '区域高度'},
        'question': {
          'type': 'string',
          'description': '针对该区域的问题，如 "这个按钮的文字是什么？"',
        },
      }, required: ['x', 'y', 'width', 'height', 'question']),
      handler: (args) async {
        final q = args['question'] as String? ?? '请描述这个区域的内容';
        final img = await s.takeScreenshot();
        if (img == null) return const ToolResult.error('截图失败');
        final res = await s.screenResolution();
        final w = (res?[0] ?? 1080).toDouble();
        final h = (res?[1] ?? 2400).toDouble();
        double toPx(num v, double max) => v < 1 ? v * max : v;
        final x = toPx((args['x'] as num?)?.toDouble() ?? 0, w);
        final y = toPx((args['y'] as num?)?.toDouble() ?? 0, h);
        final rw = toPx((args['width'] as num?)?.toDouble() ?? w, w);
        final rh = toPx((args['height'] as num?)?.toDouble() ?? h, h);
        final answer = await visionAnalyze(img,
            '请关注屏幕中 x=${x.toStringAsFixed(2)}, y=${y.toStringAsFixed(2)}, '
            'w=${rw.toStringAsFixed(2)}, h=${rh.toStringAsFixed(2)} 的区域。$q');
        return ToolResult.ok('📷 区域分析结果:\n$answer');
      },
    );

// ============================================================================
// Stage 32: 深化 — Shizuku 简化/权限自愈/Agent 执行日志
// ============================================================================

/// ——— Shizuku 授权简化：无线 ADB 替代方案 ———
Tool _shizukuSimplifiedTool(AndroidAutomationService s) => Tool(
      name: 'android_shizuku_simplified',
      description:
          '【深化】Shizuku 授权简化版。如果 Shizuku App 未安装或未授权，'
          '可尝试用无线 ADB 替代方案（需开发者选项 + 无线调试已开启）。'
          '提供完整的 Shizuku 授权引导和状态检查。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['check', 'setup_wireless_adb', 'guide', 'status_all'],
          'description': 'check=检查 Shizuku 状态, setup_wireless_adb=尝试无线 ADB 连接, '
              'guide=显示完整授权向导, status_all=检查所有权限状态',
        },
        'adb_port': {
          'type': 'integer',
          'description': '无线 ADB 端口号（默认 5555，从开发者选项的无线调试中获取）',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'check';
        final adbPort = ((args['adb_port'] as num?)?.toInt() ?? 5555).clamp(1024, 65535);
        final sb = StringBuffer();

        if (action == 'check') {
          sb.writeln('===== Shizuku 状态检查 =====');
          final r1 = await s.gshell('pm list packages | grep shizuku 2>/dev/null');
          sb.writeln('Shizuku 安装: ${r1.ok && r1.stdout.contains('shizuku') ? "✅ 已安装" : "❌ 未安装"}');
          final r2 = await s.gshell('ps -ef | grep shizuku 2>/dev/null');
          sb.writeln('Shizuku 运行: ${r2.ok && r2.stdout.contains('shizuku') ? "✅ 运行中" : "❌ 未运行"}');
          final r3 = await s.gshell('getprop service.adb.tcp.port 2>/dev/null');
          sb.writeln('无线 ADB: ${r3.ok && r3.stdout.trim().isNotEmpty ? "✅ 端口 ${r3.stdout.trim()}" : "❌ 未开启"}');
          final r4 = await s.gshell('settings get global development_settings_enabled 2>/dev/null');
          sb.writeln('开发者选项: ${r4.stdout.trim() == "1" ? "✅ 已开启" : "❌ 未开启"}');
          sb.writeln('');
          sb.writeln('💡 建议：');
          if (!r1.ok || !r1.stdout.contains('shizuku')) {
            sb.writeln('1. 安装 Shizuku: 从 moe.shizuku.privileged.api 下载');
          }
          if (!r2.ok || !r2.stdout.contains('shizuku')) {
            sb.writeln('2. 启动 Shizuku: 打开 App → 点击"启动"');
          }
          sb.writeln('3. 或用 setup_wireless_adb 尝试无线 ADB 替代方案');
          return ToolResult.ok(sb.toString());
        }

        if (action == 'setup_wireless_adb') {
          final r1 = await s.gshell('settings put global development_settings_enabled 1 2>/dev/null');
          final r2 = await s.gshell('settings put global adb_wifi_enabled 1 2>/dev/null');
          final r3 = await s.gshell('setprop service.adb.tcp.port $adbPort 2>/dev/null');
          final r4 = await s.gshell('stop adbd; start adbd 2>/dev/null');
          sb.writeln('===== 无线 ADB 设置 =====');
          sb.writeln('开发者选项: ${r1.ok ? "已开启" : "失败"}');
          sb.writeln('无线调试: ${r2.ok ? "已开启" : "失败"}');
          sb.writeln('ADB 端口: $adbPort');
          sb.writeln('ADB 重启: ${r4.ok ? "OK" : "可能需手动重启"}');
          if (r1.ok || r2.ok) {
            sb.writeln('\n✅ 无线 ADB 已配置。');
            sb.writeln('现在可以在 PC 上连接: adb connect 设备IP:$adbPort');
            sb.writeln('或在手机上用 Shizuku 的"无线调试"启动方式。');
          } else {
            sb.writeln('\n❌ 配置失败。可能需要 root 权限。');
            sb.writeln('建议：手动在 设置 → 开发者选项 → 无线调试 中开启。');
          }
          return ToolResult.ok(sb.toString());
        }

        if (action == 'guide') {
          sb.writeln('===== Shizuku 授权完整向导 =====');
          sb.writeln('');
          sb.writeln('📱 方式一：Shizuku App（推荐）');
          sb.writeln('  1. 下载安装: https://shizuku.rikka.app/download/');
          sb.writeln('  2. 打开 App → 点击"启动"');
          sb.writeln('  3. 如果弹出授权，点击"允许"');
          sb.writeln('  4. 回到本 App → 权限引导页查看状态');
          sb.writeln('');
          sb.writeln('📱 方式二：无线 ADB（无需安装 App）');
          sb.writeln('  1. 设置 → 关于手机 → 连续点击"版本号"7 次开启开发者选项');
          sb.writeln('  2. 设置 → 系统 → 开发者选项 → 开启"无线调试"');
          sb.writeln('  3. 使用 android_shizuku_simplified action=setup_wireless_adb');
          sb.writeln('  4. 或在 PC 上执行: adb connect 设备IP:5555');
          sb.writeln('');
          sb.writeln('📱 方式三：Root 设备');
          sb.writeln('  如果已 Root，Shizuku 会自动获得权限。');
          sb.writeln('');
          sb.writeln('💡 授权后可用 android_auto_grant_* 工具自动授予其他权限。');
          return ToolResult.ok(sb.toString());
        }

        if (action == 'status_all') {
          sb.writeln('===== 全部权限状态 =====');
          final r1 = await s.gshell('settings get secure enabled_accessibility_services 2>/dev/null');
          sb.writeln('无障碍服务: ${r1.stdout.contains('openagent') ? "✅" : "❌"}');
          final r2 = await s.gshell('settings get secure enabled_notification_listeners 2>/dev/null');
          sb.writeln('通知监听: ${r2.stdout.contains('openagent') ? "✅" : "❌"}');
          final r3 = await s.gshell('settings get secure enabled_notification_assistant 2>/dev/null');
          sb.writeln('通知助理: ${r3.stdout.contains('openagent') ? "✅" : "❌"}');
          final r4 = await s.gshell('ps -ef | grep shizuku 2>/dev/null');
          sb.writeln('Shizuku: ${r4.stdout.contains('shizuku') ? "✅" : "❌"}');
          final r5 = await s.gshell('dumpsys media_projection 2>/dev/null | grep -i "granted\\|active" | head -5');
          sb.writeln('截图权限: ${r5.ok && r5.stdout.trim().isNotEmpty ? "✅" : "❌(需截图时临时授权)"}');
          final r6 = await s.gshell('dumpsys package com.openagent.openagent 2>/dev/null | grep -i "WRITE_SECURE_SETTINGS" | head -3');
          sb.writeln('WRITE_SECURE_SETTINGS: ${r6.ok && r6.stdout.contains('granted') ? "✅" : "❌(需 Shizuku 授权)"}');
          sb.writeln('\n💡 用 android_auto_grant_* 工具可自动授权缺失项。');
          return ToolResult.ok(sb.toString());
        }

        return ToolResult.error('未知操作: $action');
      },
    );

/// ——— 权限自愈：自动检测并修复丢失的权限 ———
Tool _permissionSelfHealTool(AndroidAutomationService s) => Tool(
      name: 'android_permission_self_heal',
      description:
          '【深化】权限自愈。自动检测所有关键权限的状态，'
          '对已丢失的权限尝试自动重新授权。需要 Shizuku 已授权。'
          '适合在 Agent 检测到操作失败时调用（如点击无效、截图失败等）。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['check_and_fix', 'check_only', 'fix_all'],
          'description': 'check_and_fix=检查并自动修复, check_only=仅检查不修复, fix_all=尝试修复所有缺失权限',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'check_and_fix';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');
        final sb = StringBuffer();

        // 检查阶段
        final issues = <String>[];
        final checks = <String, Future<bool> Function()>{
          '无障碍服务': () async {
            final r = await s.gshell('settings get secure enabled_accessibility_services 2>/dev/null');
            return r.stdout.contains('openagent');
          },
          '通知监听': () async {
            final r = await s.gshell('settings get secure enabled_notification_listeners 2>/dev/null');
            return r.stdout.contains('openagent');
          },
          'Shizuku 运行': () async {
            final r = await s.gshell('ps -ef | grep shizuku 2>/dev/null');
            return r.stdout.contains('shizuku');
          },
        };

        for (final entry in checks.entries) {
          final ok = await entry.value();
          if (!ok) issues.add(entry.key);
        }

        sb.writeln('===== 权限自检 =====');
        if (issues.isEmpty) {
          sb.writeln('✅ 所有权限正常');
          if (action == 'check_only') return ToolResult.ok(sb.toString());
          return ToolResult.ok('${sb.toString()}\n无需修复');
        }
        sb.writeln('❌ 发现 ${issues.length} 个问题:');
        for (final issue in issues) {
          sb.writeln('  - $issue');
        }

        if (action == 'check_only') return ToolResult.ok(sb.toString());

        // 修复阶段
        sb.writeln('\n===== 修复 =====');
        for (final issue in issues) {
          switch (issue) {
            case '无障碍服务':
              final r = await s.gshell(
                  'settings put secure enabled_accessibility_services '
                  'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentAccessibilityService 2>/dev/null');
              await s.gshell('settings put secure accessibility_enabled 1 2>/dev/null');
              steps.add('无障碍服务: ${r.ok ? "已修复" : "修复失败"}');
              break;
            case '通知监听':
              final r = await s.gshell(
                  'settings put secure enabled_notification_listeners '
                  'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentNotificationListener 2>/dev/null');
              steps.add('通知监听: ${r.ok ? "已修复" : "修复失败"}');
              break;
            case 'Shizuku 运行':
              final r = await s.gshell('am start -n moe.shizuku.privileged.api/.MainActivity 2>/dev/null');
              steps.add('Shizuku 启动: ${r.ok ? "已启动" : "修复失败（需手动打开 Shizuku App）"}');
              break;
          }
        }

        sb.writeln(r());
        sb.writeln('\n💡 如果仍有问题，用 android_shizuku_simplified action=guide 查看完整授权向导。');
        return ToolResult.ok(sb.toString());
      },
    );

/// ——— Agent 执行日志/回溯 ———
Tool _agentExecutionLogTool(AndroidAutomationService s) => Tool(
      name: 'android_agent_execution_log',
      description:
          '【深化】Agent 执行日志与回溯。记录最近执行的操作步骤、结果、耗时，'
          '支持回溯查看历史操作。适合在 Agent 执行失败时分析原因。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['show', 'clear', 'save', 'stats'],
          'description': 'show=显示最近执行日志, clear=清除日志, '
              'save=保存日志到文件, stats=执行统计',
        },
        'lines': {
          'type': 'integer',
          'description': '显示的行数（默认 20）',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'show';
        final lines = ((args['lines'] as num?)?.toInt() ?? 20).clamp(5, 200);
        final logPath = '/sdcard/Android/data/com.openagent.openagent/files/agent_execution.log';
        final sb = StringBuffer();

        if (action == 'show') {
          final r = await s.gshell('tail -n $lines "$logPath" 2>/dev/null');
          if (r.ok && r.stdout.trim().isNotEmpty) {
            sb.writeln('===== Agent 执行日志 (最近 $lines 行) =====');
            sb.writeln(r.stdout.trim());
          } else {
            sb.writeln('📝 暂无执行日志。');
            sb.writeln('Agent 执行操作时会自动记录到 $logPath');
          }
          return ToolResult.ok(sb.toString());
        }

        if (action == 'clear') {
          await s.gshell('echo "" > "$logPath" 2>/dev/null');
          return ToolResult.ok('✅ 执行日志已清除');
        }

        if (action == 'save') {
          final savePath = '/sdcard/Download/agent_log_${DateTime.now().millisecondsSinceEpoch}.txt';
          final r = await s.gshell('cp "$logPath" "$savePath" 2>/dev/null');
          return r.ok
              ? ToolResult.ok('✅ 日志已保存到: $savePath')
              : ToolResult.error('保存失败');
        }

        if (action == 'stats') {
          final r = await s.gshell('wc -l "$logPath" 2>/dev/null | awk \'{print \$1}\'');
          final totalLines = int.tryParse(r.stdout.trim()) ?? 0;
          sb.writeln('===== 执行统计 =====');
          sb.writeln('日志总行数: $totalLines');
          if (totalLines > 0) {
            final success = await s.gshell('grep -c "✅\\|成功\\|OK" "$logPath" 2>/dev/null');
            final failed = await s.gshell('grep -c "❌\\|失败\\|error" "$logPath" 2>/dev/null');
            sb.writeln('成功操作: ${success.stdout.trim()}');
            sb.writeln('失败操作: ${failed.stdout.trim()}');
            sb.writeln('成功率: ${totalLines > 0 ? ((int.tryParse(success.stdout.trim()) ?? 0) * 100 / totalLines).toStringAsFixed(1) : 0}%');
          }
          sb.writeln('\n路径: $logPath');
          return ToolResult.ok(sb.toString());
        }

        return ToolResult.error('未知操作: $action');
      },
    );