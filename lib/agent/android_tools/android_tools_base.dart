part of '../android_tools.dart';

// ---------------------------------------------------------------------------
// Individual base tools
// ---------------------------------------------------------------------------

Tool _openAppTool(AndroidAutomationService s) => Tool(
      name: 'android_open_app',
      description: '打开 Android 设备上的某个应用（通过包名 package_name）。${_packageHint()}',
      schema: _props({
        'package_name': {
          'type': 'string',
          'description': '目标应用的 Android 包名，如 com.tencent.mm',
        },
      }, required: [
        'package_name'
      ]),
      handler: (args) async {
        final pkg = args['package_name'] as String?;
        if (pkg == null || pkg.isEmpty) {
          return const ToolResult.error('缺少参数 package_name');
        }
        final ok = await s.openApp(pkg);
        return ok
            ? ToolResult.ok('已打开 $pkg（若没看到界面，可能需要等待加载）')
            : ToolResult.error('打开 $pkg 失败。可能原因：应用未安装 | 应用被禁用 | 需要 Shizuku 权限。'
                '建议：用 android_gshell "pm list packages" 确认安装状态，'
                '或用 android_permission_self_heal action=check_and_fix 检查权限。');
      },
    );

Tool _clickByTextTool(AndroidAutomationService s) => Tool(
      name: 'android_click_by_text',
      description: '在当前屏幕上点击显示指定文字的按钮/链接/标签（标准 View 控件可用）。exact=true 表示完全匹配文字。',
      schema: _props({
        'text': {'type': 'string', 'description': '控件上显示的文字，如 发现、发送'},
        'exact': {
          'type': 'boolean',
          'description': '是否完全匹配，默认 true；不确定时可设为 false 模糊搜索',
        },
      }, required: [
        'text'
      ]),
      handler: (args) async {
        final text = args['text'] as String?;
        if (text == null || text.isEmpty) {
          return const ToolResult.error('缺少参数 text');
        }
        final exact = args['exact'] as bool? ?? true;
        final ok = await s.clickByText(text, exact: exact);
        return ok
            ? ToolResult.ok('已点击文字 "$text"')
            : ToolResult.error('未找到文字为 "$text" 的可点击控件。'
                '可能原因：页面未加载完成 | 文字在不可见区域 | 需要滚动。'
                '建议：先 android_dump_ui 查看当前页面控件，'
                '或用 android_scroll_to_text 滚动查找。');
      },
    );

Tool _clickByIdTool(AndroidAutomationService s) => Tool(
      name: 'android_click_by_id',
      description: '按资源 ID (view_id) 精准点击控件，优先于按文字点击。可通过 dump_ui 获取 id。',
      schema: _props({
        'view_id': {
          'type': 'string',
          'description': '控件的 viewIdResourceName，如 com.tencent.mm:id/b4k',
        },
      }, required: [
        'view_id'
      ]),
      handler: (args) async {
        final id = args['view_id'] as String?;
        if (id == null || id.isEmpty) {
          return const ToolResult.error('缺少参数 view_id');
        }
        final ok = await s.clickById(id);
        return ok
            ? ToolResult.ok('已点击 id=$id')
            : ToolResult.error('未找到 id=$id 的控件');
      },
    );

Tool _clickCoordsTool(AndroidAutomationService s) => Tool(
      name: 'android_click_coords',
      description:
          '按屏幕像素坐标点击，用于游戏/视频等无标准 View 的界面。坐标可通过 dump_ui 的 bounds 或截图后人工判断得到。',
      schema: _props({
        'x': {'type': 'integer', 'description': '横坐标像素值 (0 ≤ x < 屏幕宽)'},
        'y': {'type': 'integer', 'description': '纵坐标像素值 (0 ≤ y < 屏幕高)'},
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
        final ok = await s.clickCoords(x, y);
        return ok
            ? ToolResult.ok('已点击坐标 ($x, $y)')
            : ToolResult.error('坐标点击失败（可能无障碍/Shizuku 权限未开启）');
      },
    );

Tool _swipeTool(AndroidAutomationService s) => Tool(
      name: 'android_swipe',
      description: '执行滑动手势，用于翻页、滚动列表、返回上一级等。duration_ms 默认 300。',
      schema: _props({
        'x1': {'type': 'integer', 'description': '起点 x 像素'},
        'y1': {'type': 'integer', 'description': '起点 y 像素'},
        'x2': {'type': 'integer', 'description': '终点 x 像素'},
        'y2': {'type': 'integer', 'description': '终点 y 像素'},
        'duration_ms': {
          'type': 'integer',
          'description': '滑动持续毫秒，数字越大滑动越慢',
        },
      }, required: [
        'x1',
        'y1',
        'x2',
        'y2'
      ]),
      handler: (args) async {
        final x1 = args['x1'] as int?;
        final y1 = args['y1'] as int?;
        final x2 = args['x2'] as int?;
        final y2 = args['y2'] as int?;
        if (x1 == null || y1 == null || x2 == null || y2 == null) {
          return const ToolResult.error('缺少 x1/y1/x2/y2 参数');
        }
        final dur = args['duration_ms'] as int? ?? 300;
        final ok = await s.swipe(x1, y1, x2, y2, durationMs: dur);
        return ok
            ? ToolResult.ok('已执行滑动 (${x1}x$y1 → ${x2}x$y2, ${dur}ms)')
            : ToolResult.error('滑动失败');
      },
    );

Tool _scrollForwardTool(AndroidAutomationService s) => Tool(
      name: 'android_scroll_forward',
      description: '在当前可滚动的控件上向前滚动一屏（如刷抖音下一条、向下看更多内容）',
      schema: _props({}),
      handler: (_) async {
        final ok = await s.scrollForward();
        return ok
            ? const ToolResult.ok('已向前滚动一屏')
            : const ToolResult.error('未找到可滚动控件，改用 android_swipe 手动指定位置');
      },
    );

Tool _inputTextTool(AndroidAutomationService s) => Tool(
      name: 'android_input_text',
      description: '在当前焦点输入框中输入文字（需先通过点击让输入框获得焦点）',
      schema: _props({
        'text': {'type': 'string', 'description': '要输入的文本内容'},
      }, required: [
        'text'
      ]),
      handler: (args) async {
        final text = args['text'] as String?;
        if (text == null) return const ToolResult.error('缺少参数 text');
        final ok = await s.inputText(text);
        return ok
            ? ToolResult.ok('已输入文字')
            : ToolResult.error('输入失败。可能原因：输入框未获得焦点 | 输入法未就绪 | 无障碍权限不足。'
                '建议：先用 android_click_by_text 点击输入框获得焦点，再重试输入。');
      },
    );

Tool _pressKeyTool(AndroidAutomationService s) => Tool(
      name: 'android_press_key',
      description:
          '按下系统级按键。可选值: home, back, recent, volume_up, volume_down, power, enter, del',
      schema: _props({
        'key': {
          'type': 'string',
          'description':
              '按键名：home=回桌面 / back=返回 / recent=最近任务 / volume_up=音量加 / volume_down=音量减 / power=电源 / enter=回车 / del=删除',
        },
      }, required: [
        'key'
      ]),
      handler: (args) async {
        final k = args['key'] as String?;
        final key = switch (k?.toLowerCase()) {
          'home' => AndroidKey.home,
          'back' => AndroidKey.back,
          'recent' => AndroidKey.recent,
          'volume_up' || 'vol_up' => AndroidKey.volumeUp,
          'volume_down' || 'vol_down' => AndroidKey.volumeDown,
          'power' => AndroidKey.power,
          'enter' => AndroidKey.enter,
          'del' || 'delete' => AndroidKey.delete,
          _ => null,
        };
        if (key == null) {
          return ToolResult.error(
              '不支持的按键: $k。可选值: home back recent volume_up volume_down power enter del');
        }
        final ok = await s.pressKey(key);
        return ok ? ToolResult.ok('已按：${k}') : ToolResult.error('按键 ${k} 执行失败');
      },
    );

Tool _dumpUiTool(AndroidAutomationService s) => Tool(
      name: 'android_dump_ui',
      description:
          '读取当前屏幕上所有控件的文字/ID/坐标/是否可点击等信息，用来决定下一步点击什么。执行任何自动化前强烈建议先调用本工具观察界面。',
      schema: _props({
        'limit': {
          'type': 'integer',
          'description': '最多返回多少个控件（默认 80），太长会超出 LLM 上下文',
        },
      }),
      handler: (args) async {
        final limit = args['limit'] as int? ?? 80;
        final summary = await s.dumpUiSummary(limit: limit);
        if (summary.isEmpty) {
          return const ToolResult.error('dump_ui 返回为空。'
              '可能原因：无障碍服务未开启 | 当前页面无文字控件（游戏/Canvas/图片）。'
              '建议：用 android_permission_self_heal 检查无障碍状态，'
              '或用 android_vision_analyze 进行视觉分析。');
        }
        return ToolResult.ok(summary);
      },
    );

Tool _listPackagesTool(AndroidAutomationService s) => Tool(
      name: 'android_list_packages',
      description: '列出设备上已安装应用的全部包名，供 android_open_app 使用。输出可能较长，建议仅在需要找包名时调用。',
      schema: _props({
        'contains': {
          'type': 'string',
          'description': '可选：只返回包含该关键词的包名（模糊过滤）',
        },
      }),
      handler: (args) async {
        final list = await s.listInstalledPackages();
        if (list.isEmpty) {
          return const ToolResult.error('无法获取应用列表（需要 Shizuku 或无障碍权限）');
        }
        final filter = args['contains'] as String?;
        final filtered = filter == null
            ? list
            : list.where((p) => p.contains(filter.toLowerCase())).toList();
        final str = filtered.take(200).join('\n');
        final totalShown = filtered.length > 200
            ? '\n（仅显示前 200 / ${filtered.length} 个，可用 contains 进一步过滤）'
            : '';
        return ToolResult.ok('$str$totalShown');
      },
    );

Tool _screenResolutionTool(AndroidAutomationService s) => Tool(
      name: 'android_screen_resolution',
      description:
          '获取设备屏幕分辨率 [宽, 高] 像素。在需要精准计算 android_click_coords / android_swipe 时先调用。',
      schema: _props({}),
      handler: (_) async {
        final r = await s.screenResolution();
        if (r == null || r.length != 2) {
          return const ToolResult.error('无法获取屏幕分辨率（需要 Shizuku 权限或截图权限）');
        }
        return ToolResult.ok('屏幕分辨率：宽 ${r[0]} × 高 ${r[1]} 像素');
      },
    );

Tool _screenshotTool(AndroidAutomationService s) => Tool(
      name: 'android_screenshot',
      description:
          '截取当前屏幕为 PNG 文件，返回图片的绝对文件路径。对于抖音/游戏等无法 dump_ui 的场景，可调用本工具再通过 Omni 多模态模型直接分析截图内容。',
      schema: _props({}),
      handler: (_) async {
        final path = await s.takeScreenshot();
        if (path == null) {
          return const ToolResult.error('截图失败（需先在权限引导页开启截图权限，或授权 Shizuku 后重试）');
        }
        return ToolResult.ok('截图已保存到：$path\n'
            '（如需看懂屏幕内容：把该路径作为 Omni 多模态对话的图片附件传给助手即可）');
      },
    );

Tool _waitTool() => Tool(
      name: 'android_wait',
      description: '等待若干秒（如等待页面跳转、应用加载完成、弹窗弹出后再操作）',
      schema: _props({
        'seconds': {
          'type': 'number',
          'description': '等待秒数（可小数，如 1.5），默认 2 秒',
        },
      }),
      handler: (args) async {
        final secs = (args['seconds'] as num?)?.toDouble() ?? 2.0;
        final ms = (secs * 1000).round();
        await Future<void>.delayed(Duration(milliseconds: ms));
        return ToolResult.ok('已等待 ${secs.toStringAsFixed(2)} 秒');
      },
    );

/// Intelligently wait for a specific UI element (text/id string) to appear
/// on the screen before the next automation step. Much more reliable than a
/// blind android_wait fixed-delay because phones vary a lot on app launch
/// latency and page rendering speed.
Tool _waitForTextTool(AndroidAutomationService s) => Tool(
      name: 'android_wait_for_text',
      description: '轮询无障碍 UI 树，直到屏幕出现指定文字（timeout 超时返回失败）。'
          '比固定等待秒数 android_wait 更稳：用于「打开 App 后等登录按钮出来再点」、'
          '「点了发送后等「发送成功」出现」、跳转新页面确认加载完这类场景。'
          '超时后返回失败，由 Agent 决定是否换 dump_ui 分析或延长超时重试。',
      schema: _props({
        'text': {
          'type': 'string',
          'description': '要等待出现的目标文字（大小写不敏感，包含匹配）',
        },
        'timeout_seconds': {
          'type': 'number',
          'description': '最长等待秒数，默认 10 秒',
        },
        'poll_ms': {
          'type': 'number',
          'description': '两次 UI 扫描间隔毫秒，默认 500ms',
        },
        'exact': {
          'type': 'boolean',
          'description': '是否精确匹配整行 (默认 false=包含匹配即可)',
        },
      }, required: [
        'text'
      ]),
      handler: (args) async {
        final text = args['text'] as String?;
        if (text == null || text.isEmpty) {
          return const ToolResult.error('缺少 text 参数');
        }
        final timeout =
            ((args['timeout_seconds'] as num?)?.toDouble() ?? 10.0).toInt();
        final poll = ((args['poll_ms'] as num?)?.toDouble() ?? 500.0).toInt();
        final exact = args['exact'] == true;
        final safePoll = poll < 50 ? 50 : poll;
        final ok = await s.waitForText(
          text,
          timeoutSec: timeout,
          pollMs: safePoll,
          exact: exact,
        );
        if (ok) {
          final scansApprox = (timeout * 1000 / safePoll).round();
          return ToolResult.ok(
              '已在屏幕上检测到文字「$text」（超时${timeout}s，约 $scansApprox 次扫描）。可进行下一步操作。');
        }
        return ToolResult.error('等待「$text」出现失败：${timeout}秒内没在 UI 树中找到。'
            '建议：1) android_dump_ui 重看一下真实界面文字是否变化；'
            '2) 把 timeout_seconds 调大（如 15/20）；3) 检查大小写或改用非 exact 包含匹配。');
      },
    );

Tool _installApkTool(AndroidAutomationService s) => Tool(
      name: 'android_install_apk',
      description: '静默安装 APK 文件（需要 Shizuku 或 Root 权限；否则会弹出系统安装器需用户确认）',
      schema: _props({
        'apk_path': {'type': 'string', 'description': 'APK 文件的绝对路径'},
      }, required: [
        'apk_path'
      ]),
      handler: (args) async {
        final p = args['apk_path'] as String?;
        if (p == null || p.isEmpty) {
          return const ToolResult.error('缺少 apk_path');
        }
        final ok = await s.installApk(p);
        return ok
            ? ToolResult.ok('APK 安装成功：$p')
            : ToolResult.error(
                '静默安装失败（无 Shizuku 权限？已改由系统安装器显示安装确认界面，用户点确认后可完成）');
      },
    );

// ---- Advanced / optional tools (below) -----------------------------------

Tool _getTopAppTool(AndroidAutomationService s) => Tool(
      name: 'android_get_top_app',
      description: '获取当前在前台运行的应用（包名 + Activity 类名）。'
          '用于确认是否已成功打开目标 App（如执行 android_open_app 后校验），再进行后续点击操作。',
      schema: _props({}),
      handler: (_) async {
        final info = await s.getTopApp();
        if (info.package.isEmpty) {
          return const ToolResult.error(
              '无法获取前台应用（需要 PACKAGE_USAGE_STATS 或 Shizuku 权限）。可改用 android_dump_ui 观察包名。');
        }
        return ToolResult.ok('当前前台应用：package=${info.package}\n'
            'activity=${info.activity.isEmpty ? '(未知)' : info.activity}');
      },
    );

Tool _getPermissionStatusTool(AndroidAutomationService s) => Tool(
      name: 'android_get_permission_status',
      description: '查询当前 Android 自动化后端状态（无障碍 / Shizuku / 截图 / 应用使用统计）。'
          '若某个操作一直失败，先调用该工具确认对应权限是否已授权。',
      schema: _props({}),
      handler: (_) async {
        final m = await s.getPermissionStatusMap();
        if (m.isEmpty) {
          return const ToolResult.ok('当前平台非 Android，自动化不可用。');
        }
        String fmt(String k, String zhName) {
          final v = m[k] == true ? '✅已授权' : '❌未授权';
          return '$zhName: $v';
        }

        return ToolResult.ok([
          fmt('accessibility_enabled', 'L1 无障碍服务'),
          fmt('shizuku_granted', 'L2 Shizuku Shell'),
          fmt('screenshot_granted', '截图 MediaProjection'),
          fmt('usage_stats_granted', '应用使用统计(查前台App)'),
        ].join('\n'));
      },
    );

/// Danger-zone tool — can run arbitrary shell commands. Gated behind a
/// confirmation notice in the tool description so the model only uses it
/// when really needed (e.g. adb-style `pm enable ...`, `settings put ...`,
/// `screencap`, custom dumpsys filters).
Tool _gshellTool(AndroidAutomationService s) => Tool(
      name: 'android_gshell',
      description: '⚠ 高级工具：直接通过 Shizuku / shell 运行任意命令。'
          '仅限以下场景使用：1) 没有对应专用自动化工具时；2) 需修改系统设置等特殊操作。'
          '每次调用需报告将执行的命令以及预期影响。',
      schema: _props({
        'command': {
          'type': 'string',
          'description':
              '要执行的 shell 命令，如 "pm list packages -3" 或 "dumpsys battery"',
        },
      }, required: [
        'command'
      ]),
      handler: (args) async {
        final cmd = args['command'] as String?;
        if (cmd == null || cmd.isEmpty)
          return const ToolResult.error('缺少 command');
        final r = await s.gshell(cmd);
        final preview = r.stdout.length > kUiDumpPreviewMax
            ? '${r.stdout.substring(0, kUiDumpPreviewMax)}\n…(stdout 截断，共 ${r.stdout.length} 字符)'
            : r.stdout;
        final body = StringBuffer('命令：`$cmd`\n');
        body.writeln('退出码：${r.exitCode} (${r.ok ? "成功" : "失败"})');
        if (r.stderr.isNotEmpty) {
          body.writeln(
              'stderr:\n```\n${r.stderr.substring(0, r.stderr.length > kUiDumpPreviewShort ? kUiDumpPreviewShort : r.stderr.length)}\n```');
        }
        if (preview.isNotEmpty) body.writeln('stdout:\n```\n$preview\n```');
        return ToolResult.ok(body.toString());
      },
    );

/// Vision analysis tool: wraps an on-device Omni multimodal model.
/// The Agent calls this after android_screenshot when dump_ui is empty
/// (games / Douyin ForYou feeds / custom Canvas surfaces). Outputs a
/// text answer the model can use to pick a click coordinate / next action.
Tool _visionAnalyzeTool(
        Future<String> Function(String imagePath, String question) analyze) =>
    Tool(
      name: 'android_vision_analyze',
      description: '用本地多模态大模型 (Omni VLM) 分析一张截图。'
          '在 android_dump_ui 返回空时（游戏、抖音 feed、自定义画布、纯图片界面）调用，'
          '传入截图路径 + 你的问题，返回文字描述（含按钮位置、坐标建议）。'
          '参数 image_path 一般来自 android_screenshot 的输出。',
      schema: _props({
        'image_path': {
          'type': 'string',
          'description': '截图 PNG/JPG 的绝对路径（android_screenshot 返回）',
        },
        'question': {
          'type': 'string',
          'description': '要对截图问的问题。例：请描述这张截图里所有可点击的按钮，'
              '并估算每个按钮的中心坐标 (x,y)（屏幕宽 1080 高 2400 左上角为 0,0）。'
              '如要操作游戏：描述所有关卡入口 / 开始按钮 / 确认按钮的坐标。',
        },
      }, required: [
        'image_path',
        'question',
      ]),
      handler: (args) async {
        final p = args['image_path'] as String?;
        final q = args['question'] as String?;
        if (p == null || p.isEmpty)
          return const ToolResult.error('缺少 image_path');
        if (q == null || q.isEmpty)
          return const ToolResult.error('缺少 question');
        try {
          final answer = await analyze(p, q);
          return ToolResult.ok(answer);
        } catch (e) {
          return ToolResult.error('视觉分析失败: $e');
        }
      },
    );
