part of '../android_tools.dart';

// ============================================================================
// H7 系统设置 + 社交补全 （×5）
// ============================================================================

/// ——— 系统：开/关 Wi-Fi (优先L2 svc，不行才跳设置 UI) ———
Tool _composeSystemWifi(AndroidAutomationService s) => Tool(
      name: 'android_system_set_wifi',
      description:
          '【高层·系统设置】开启/关闭 手机 Wi-Fi。优先用 shell `svc wifi enable/disable` (L2/L3 秒切)；不行再进系统设置页 UI 开关。',
      schema: _props({
        'enabled': {
          'type': 'boolean',
          'description': 'true=打开 Wi-Fi；false=关闭 Wi-Fi',
        },
      }, required: [
        'enabled'
      ]),
      handler: (args) async {
        final on = args['enabled'] != false;
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 1) Shell 秒切 (Shizuku/Root 都支持 svc)
        final sh = await s.gshell('svc wifi ${on ? 'enable' : 'disable'}');
        steps.add(
            'svc wifi ${on ? 'enable' : 'disable'}: ok=${sh.ok}, exit=${sh.exitCode}');
        if (sh.ok) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          return ToolResult.ok('✅ Wi-Fi ${on ? '已开启' : '已关闭'} (svc)\n${r()}');
        }

        // 2) UI Fallback: 打开设置 → 网络 → Wi-Fi 开关
        steps.add('L2 svc 失败，尝试 UI 方式');
        await s.openApp('com.android.settings');
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await s.clickByText('WLAN', exact: false);
        await s.clickByText('Wi-Fi', exact: false);
        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // 典型 Wi-Fi 开关在 右上 88%x 8%y (小米/HW)；或 34%x 20%y
        await s.clickCoords((w * 0.88).round(), (h * 0.08).round());
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return ToolResult.ok(
            '⚠ 已尝试 UI 切换 Wi-Fi ${on ? '开' : '关'} (非 L2 可能需要手动确认)\n${r()}');
      },
    );

/// ——— 系统：开/关 蓝牙 ———
Tool _composeSystemBluetooth(AndroidAutomationService s) => Tool(
      name: 'android_system_set_bluetooth',
      description:
          '【高层·系统设置】开启/关闭 蓝牙。优先 shell `svc bluetooth enable/disable`；失败走设置 UI。',
      schema: _props({
        'enabled': {
          'type': 'boolean',
          'description': 'true=开蓝牙；false=关蓝牙',
        },
      }, required: [
        'enabled'
      ]),
      handler: (args) async {
        final on = args['enabled'] != false;
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final sh = await s.gshell('svc bluetooth ${on ? 'enable' : 'disable'}');
        steps.add('svc bluetooth ${on ? 'enable' : 'disable'}: ok=${sh.ok}');
        if (sh.ok) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          return ToolResult.ok('✅ 蓝牙 ${on ? '已开启' : '已关闭'} (svc)\n${r()}');
        }

        steps.add('L2 失败，UI fallback');
        await s.openApp('com.android.settings');
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await s.clickByText('蓝牙', exact: false);
        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        await s.clickCoords((w * 0.88).round(), (h * 0.10).round());
        return ToolResult.ok('⚠ UI 尝试切换蓝牙 ${on ? '开' : '关'}\n${r()}');
      },
    );

/// ——— 系统：调节媒体/通话/闹钟/铃声音量 (0-15 档) ———
Tool _composeSystemSetVolume(AndroidAutomationService s) => Tool(
      name: 'android_system_set_volume',
      description: '【高层·系统设置】一次性设置 媒体/通话/铃声/闹钟 任一流的音量档位 (0 静音 ~ 15 最大)。'
          '优先 shell `cmd media_session dispatch volume --set` 或 `media volume --stream N --set`；失败走按物理 VOLUME_UP/DOWN N 次模拟。',
      schema: _props({
        'level': {
          'type': 'integer',
          'description': '目标音量档位 0~15 (0=静音, 7=中等, 15=最大)',
        },
        'stream': {
          'type': 'string',
          'description': 'music=媒体音乐/视频(默认), ring=来电铃声, alarm=闹钟, call=通话音量',
        },
      }, required: [
        'level'
      ]),
      handler: (args) async {
        final level = ((args['level'] as num?)?.toInt() ?? 7).clamp(0, 15);
        final stream = (args['stream'] as String?) ?? 'music';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // STREAM mapping: Android STREAM_VOICE_CALL=0, SYSTEM=1, RING=2, MUSIC=3, ALARM=4
        final streamNo = const {
              'call': '0',
              'ring': '2',
              'music': '3',
              'alarm': '4'
            }[stream] ??
            '3';

        // 方案 A: `media volume` (部分国内 ROM 支持) → `cmd media_session dispatch set_volume`
        final a1 =
            await s.gshell('media volume --stream $streamNo --set $level 2>&1');
        if (a1.ok && (a1.exitCode == 0)) {
          steps.add('media volume s=$streamNo lvl=$level: OK');
        } else {
          // 方案 B: service call audio / cmd media_session dispatch 等 (兼容性依次尝试)
          final a2 = await s.gshell(
              'cmd media_session dispatch volume --stream $streamNo --set $level');
          if (!a2.ok) {
            // 方案 C: service call audio 3 (getMode) → 不同 ROM 码号不同，放弃 Shell
            steps.add('Shell 设置音量失败 (exit=${a2.exitCode})，改用 VOL 键模拟 0→$level');
            // 按 8 次 DOWN 先回静音 (保险一点)，再按 $level 次 UP
            for (var i = 0; i < 9; i++) await s.pressKey(AndroidKey.volumeDown);
            for (var i = 0; i < level; i++)
              await s.pressKey(AndroidKey.volumeUp);
            steps.add('按键模拟: 先-9静音 + 再+$level UP → 目标=$level');
          } else {
            steps.add('cmd media_session dispatch set $streamNo/$level: OK');
          }
        }
        return ToolResult.ok(
            '✅ 音量设置 stream=$stream($streamNo) → $level\n${r()}');
      },
    );

/// ——— 微信：群发助手 (给 N 个好友发相同文字 —— 节日/通知群发) ———
Tool _composeWechatBroadcastMessage(AndroidAutomationService s) => Tool(
      name: 'android_wechat_broadcast_message',
      description:
          '【高层·一键群发】微信 → 我 → 设置 → 通用 → 辅助功能 → 群发助手 → 开始群发 → 新建 → 搜并选择好友 → 下一步 → 写文字 → 发送。'
          '⚠ 用户说"给所有客户群发个祝福""给群里所有人发通知"时用本工具。注意：不能用来发骚扰营销内容，受微信频控。',
      schema: _props({
        'message': {
          'type': 'string',
          'description': '群发的正文文字 (必填)',
        },
        'search_names': {
          'type': 'array',
          'description': '【可选】N 个好友/群聊备注名。工具会依次搜索并勾选；为空则只点群发助手不选具体人（手动确认）。',
        },
      }, required: [
        'message'
      ]),
      handler: (args) async {
        final msg = args['message'] as String? ?? '';
        final namesRaw = args['search_names'];
        List<String> names = <String>[];
        if (namesRaw is List) names = namesRaw.whereType<String>().toList();
        if (msg.isEmpty) return const ToolResult.error('缺少 message');

        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // Step 1: 微信主页 → 右下「我」
        final ok1 = await s.openApp('com.tencent.mm');
        steps.add('打开微信: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('启动失败\n${r()}');
        await s.waitForText('微信', timeoutSec: 18, pollMs: 700, exact: false) ||
            await s.waitForText('通讯录', timeoutSec: 6, pollMs: 500, exact: true);

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        final me = await s.clickByText('我', exact: true) ||
            await s.clickCoords((w * 0.88).round(), (h * 0.96).round());
        steps.add('点「我」: ${me ? 'OK' : '坐标尝试 (88%x, 96%y)'}');
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // Step 2: 设置 → 通用 → 辅助功能 → 群发助手
        for (final label in ['设置', '通用', '辅助功能', '群发助手']) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          final ok = await s.clickByText(label, exact: true);
          steps.add('点「$label」: ${ok ? 'OK' : '(没找到，继续)'}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // Step 3: 开始群发 → 新建群发
        for (final label in ['开始群发', '新建']) {
          final ok = await s.clickByText(label, exact: true);
          steps.add('点「$label」: ${ok ? 'OK' : ''}');
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }

        // Step 4: 选 N 个收信人
        var chosen = 0;
        for (final nm in names) {
          if (chosen >= 50) break; // 微信单次群发上限 ≈200，保守限制 50
          final bar = await s.clickByText('搜索', exact: false) ||
              await s.clickCoords((w * 0.50).round(), (h * 0.10).round());
          if (bar) {
            final wrote = await s.inputText(nm);
            if (wrote) {
              await Future<void>.delayed(const Duration(milliseconds: 400));
              // 点击第一个搜索结果 (左侧头像右边 30%x 区域)
              final t =
                  await s.clickCoords((w * 0.20).round(), (h * 0.32).round());
              if (t) chosen++;
              steps.add('搜索+选择「$nm」: 选择=${t ? 'OK' : '未点到'}, 当前选中$chosen');
              await Future<void>.delayed(const Duration(milliseconds: 200));
            }
          }
        }
        if (names.isEmpty) steps.add('未指定 search_names，停在「选人」页等待用户自己挑');

        // Step 5: 下一步 → 写文字 → 发送
        if (names.isNotEmpty && chosen > 0) {
          await s.clickByText('下一步', exact: true) ||
              await s.clickCoords((w * 0.90).round(), (h * 0.95).round());
          await Future<void>.delayed(const Duration(milliseconds: 600));
          final iw = await s.inputText(msg);
          steps.add('写群发内容(${msg.length}字): ${iw ? 'OK' : '失败'}');
          if (iw) {
            final sent = await s.clickByText('发送', exact: true);
            steps.add('发送: ${sent ? 'OK' : '发送失败'}');
          }
        }
        return ToolResult.ok(
            '✅ 微信群发助手流程完成 (尝试勾选 $chosen/${names.length} 人)\n${r()}');
      },
    );

/// ——— B站视频播放页：发一条弹幕 ———
Tool _composeBilibiliSendDanmaku(AndroidAutomationService s) => Tool(
      name: 'android_bilibili_send_danmaku',
      description: '【高层·B站社交】当前在播放的 B 站视频页：点击底部弹幕输入框 → 写弹幕 → 发送。'
          '用户说"在这条视频刷个「下次一定」"时调用。',
      schema: _props({
        'text': {
          'type': 'string',
          'description': '弹幕内容，不要超过 30 字',
        },
        'color_hex': {
          'type': 'string',
          'description': '(预留) 弹幕颜色 RGB hex，默认白字 #FFFFFF，当前版本未改颜色面板',
        },
      }, required: [
        'text'
      ]),
      handler: (args) async {
        final txt = args['text'] as String? ?? '';
        if (txt.isEmpty) return const ToolResult.error('缺少 text');
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 确保在 B站
        final info = await s.getTopApp();
        if (info.package != 'tv.danmaku.bili') {
          steps.add('当前不在 B 站，跳过(防止误发在其他App)');
          return ToolResult.error('请先打开 B 站视频页再发弹幕\n${r()}');
        }
        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // B站播放器：竖屏弹幕输入框在视频下方 42%~48%y 的一条灰色"发条友善的弹幕~"占位符
        // 横屏时一般位于屏幕 左中 30%x~50%x。双位置尝试
        final focus = await s.clickByText('发条友善的弹幕', exact: false) ||
            await s.clickByText('发个弹幕', exact: false) ||
            await s.clickByText('说点什么', exact: false) ||
            await s.clickCoords((w * 0.30).round(), (h * 0.45).round()) ||
            await s.clickCoords((w * 0.25).round(), (h * 0.90).round());
        steps.add('点弹幕输入框: ${focus ? 'OK' : '双坐标尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final wrote = await s.inputText(txt);
        steps.add('输入弹幕「$txt」: ${wrote ? 'OK' : '失败'}');
        if (!wrote) return ToolResult.error('弹幕输入框写入失败\n${r()}');
        final sent = await s.clickByText('发送', exact: true) ||
            await s.clickByText('发', exact: true) ||
            await s.clickCoords((w * 0.93).round(), (h * 0.45).round());
        steps.add('发送弹幕: ${sent ? 'OK' : '未点到发送按钮'}');
        return ToolResult.ok('✅ B站弹幕流程完成\n${r()}');
      },
    );

// ============================================================================
// H15 — 系统原子补全 ×6
// ============================================================================

/// H15-1: 最近任务列表
Tool _recentTasksTool(AndroidAutomationService s) => Tool(
      name: 'android_get_recent_tasks',
      description: '【开放信息】返回手机最近打开过的 N 个 App 任务 + 当前 ResumedActivity 栈顶。',
      schema: _props({
        'limit': {
          'type': 'integer',
          'description': '最多返回多少个最近任务 (默认 20，最大 100)',
        },
      }),
      handler: (args) async {
        final limit = ((args['limit'] as num?)?.toInt() ?? 20).clamp(1, 100);
        final out = await s.getRecentTasks(limit: limit);
        return ToolResult.ok(out);
      },
    );

/// H15-2: 当前前台 Activity + Fragment 栈
Tool _dumpFragmentsTool(AndroidAutomationService s) => Tool(
      name: 'android_dump_activity_fragments',
      description: '【开放细粒度信息】输出当前前台 Activity 的完整 FragmentManager 栈。',
      schema: _props({
        'limit_lines': {
          'type': 'integer',
          'description': '最多返回多少行 (默认 160，最大 800)',
        },
      }),
      handler: (args) async {
        final limit =
            ((args['limit_lines'] as num?)?.toInt() ?? 160).clamp(20, 800);
        final out = await s.dumpActivityFragments(limitLines: limit);
        return ToolResult.ok(out);
      },
    );

/// H15-3: WiFi 扫描
Tool _wifiScanTool(AndroidAutomationService s) => Tool(
      name: 'android_get_wifi_scan',
      description: '【开放信息】返回手机附近 WiFi 的扫描结果。',
      schema: _props({
        'limit': {
          'type': 'integer',
          'description': '最多返回多少个 AP (默认 60，最大 500)',
        },
      }),
      handler: (args) async {
        final limit = ((args['limit'] as num?)?.toInt() ?? 60).clamp(1, 500);
        final out = await s.getWifiScan(limit: limit);
        return ToolResult.ok(out);
      },
    );

/// H15-4: 双卡详情
Tool _simInfoTool(AndroidAutomationService s) => Tool(
      name: 'android_get_sim_info',
      description: '【开放信息】SIM卡/手机IMEI/IMSI信息。',
      schema: _props({}),
      handler: (_) async {
        final out = await s.getSimInfo();
        return ToolResult.ok(out);
      },
    );

/// H15-5: Toast 历史
Tool _toastHistoryTool(AndroidAutomationService s) => Tool(
      name: 'android_get_toast_history',
      description: '【开放信息】尽力而为地返回最近 Toast 弹过的文字/包名/时长。',
      schema: _props({
        'limit': {
          'type': 'integer',
          'description': '最多保留多少条 Toast 痕迹 (默认 50，最大 300)',
        },
      }),
      handler: (args) async {
        final limit = ((args['limit'] as num?)?.toInt() ?? 50).clamp(1, 300);
        final out = await s.getToastHistory(limit: limit);
        return ToolResult.ok(out);
      },
    );

/// H15-6: 杀应用 / 冷启动
Tool _killRestartTool(AndroidAutomationService s) => Tool(
      name: 'android_kill_or_restart_app',
      description: '【开放操作】彻底杀掉一个 App 的所有进程，然后可选地立刻冷启动它。',
      schema: _props({
        'package_name': {
          'type': 'string',
          'description': '要杀/重启的应用包名',
        },
        'mode': {
          'type': 'string',
          'description':
              '"kill_only"=只杀不启；"kill_and_restart"=先 force-stop 再干净启动 (默认)；"restart_only"=不杀直接 monkey 启动',
        },
      }, required: [
        'package_name'
      ]),
      handler: (args) async {
        final pkg = (args['package_name'] as String?)?.trim() ?? '';
        if (pkg.isEmpty) return const ToolResult.error('package_name 不能为空');
        final mode = (args['mode'] as String?)?.trim().toLowerCase() ??
            'kill_and_restart';
        switch (mode) {
          case 'kill_only':
            {
              final r = await s.killAndRestartApp(pkg, killOnly: true);
              return r.ok
                  ? ToolResult.ok('✅ 已杀掉 $pkg\n${r.stdout}')
                  : ToolResult.error(
                      '❌ 杀 $pkg 失败: ${r.stderr.isEmpty ? r.stdout : r.stderr}');
            }
          case 'restart_only':
            {
              final r = await s.openAppWithResult(pkg);
              return r.ok
                  ? ToolResult.ok('✅ 已尝试启动 (不杀) $pkg\n${r.stdout}')
                  : ToolResult.error(
                      '❌ 启动 $pkg 失败: ${r.stderr.isEmpty ? r.stdout : r.stderr}');
            }
          case 'kill_and_restart':
          default:
            {
              final r = await s.killAndRestartApp(pkg, killOnly: false);
              return r.ok
                  ? ToolResult.ok('✅ 已冷启动 $pkg (先杀再启)\n${r.stdout}')
                  : ToolResult.error(
                      '❌ 冷启动 $pkg 失败 exit=${r.exitCode}: ${r.stderr.isEmpty ? r.stdout : r.stderr}');
            }
        }
      },
    );

// ============================================================================
// H17 ×5：硬件信息 / 通话记录 / 相册媒体 / 系统设置工具 / 壁纸分享输入法
// ============================================================================

/// H17-1: 硬件信息全景
Tool _hardwareInfoTool(AndroidAutomationService s) => Tool(
      name: 'android_get_hardware_info',
      description: '【开放信息】返回手机完整硬件+系统版本信息。',
      schema: _props({}),
      handler: (_) async {
        final out = await s.getHardwareInfo();
        return ToolResult.ok(out);
      },
    );

/// H17-2: 通话记录查询
Tool _callLogTool(AndroidAutomationService s) => Tool(
      name: 'android_get_call_log',
      description: '【开放信息】读取最近 N 条通话记录。',
      schema: _props({
        'box': {
          'type': 'string',
          'description':
              '"all"=所有通话 (默认)；"incoming"=只查来电；"outgoing"=只查去电；"missed"=只查未接',
        },
        'limit': {
          'type': 'integer',
          'description': '最多多少条 (默认 30，最大 500)',
        },
      }),
      handler: (args) async {
        final box = (args['box'] as String?)?.trim().toLowerCase() ?? 'all';
        final limit = ((args['limit'] as num?)?.toInt() ?? 30).clamp(1, 500);
        final out = await s.getCallLog(box: box, limit: limit);
        return ToolResult.ok(out);
      },
    );

/// H17-3: 媒体库 / 相册
Tool _mediaGalleryTool(AndroidAutomationService s) => Tool(
      name: 'android_query_media_gallery',
      description: '【开放信息】查询手机媒体库。',
      schema: _props({
        'bucket': {
          'type': 'string',
          'description':
              '按相册名模糊匹配过滤，例 "DCIM" / "Camera" / "Screenshots" / "ALL" = 全部媒体。默认 "DCIM"',
        },
        'keyword': {
          'type': 'string',
          'description': '按文件名关键字搜索',
        },
        'limit': {
          'type': 'integer',
          'description': '最多返回多少条 (默认 60，最大 500)',
        },
        'include_videos': {
          'type': 'boolean',
          'description': 'true=同时查图片和视频 (默认)',
        },
      }),
      handler: (args) async {
        final bucket = (args['bucket'] as String?)?.trim() ?? 'DCIM';
        final kw = args['keyword'] as String?;
        final limit = ((args['limit'] as num?)?.toInt() ?? 60).clamp(1, 500);
        final incV = args['include_videos'] as bool? ?? true;
        final out = await s.queryMediaGallery(
            bucket: bucket, keyword: kw, limit: limit, includeVideos: incV);
        return ToolResult.ok(out);
      },
    );

/// H17-4: 亮度调节 + 输入法切换
Tool _displayAndInputTool(AndroidAutomationService s) => Tool(
      name: 'android_adjust_display_or_input',
      description: '【开放操作】① 调节屏幕亮度 ② 切换输入法 (IME)。',
      schema: _props({
        'brightness': {
          'type': ['integer', 'string'],
          'description': '亮度设置：整数 0~255=手动固定亮度；字符串 "auto" = 开启自动亮度',
        },
        'brightness_open_settings_if_denied': {
          'type': 'boolean',
          'description': '没 WRITE_SETTINGS 时是否跳显示设置页引导。默认 true。',
        },
        'ime_id': {
          'type': 'string',
          'description': '"picker"=弹输入法选择器；"next"/"prev"=切下/上一个输入法',
        },
      }),
      handler: (args) async {
        final sb = StringBuffer();
        if (args.containsKey('brightness') && args['brightness'] != null) {
          final bRaw = args['brightness'];
          final openS =
              args['brightness_open_settings_if_denied'] as bool? ?? true;
          final r = await s.setSystemBrightness(
              brightness: bRaw, openSettingsIfDenied: openS);
          sb.writeln('=== 亮度调节结果 ===');
          sb.writeln(
              '请求 brightness=$bRaw → ${r.ok ? "OK" : "FAILED exit=${r.exitCode}"}');
          sb.writeln(r.stdout.isEmpty ? r.stderr : r.stdout);
          sb.writeln();
        }
        final imeId = (args['ime_id'] as String?)?.trim() ?? '';
        if (imeId.isNotEmpty) {
          final r = await s.switchInputMethod(imeId: imeId);
          sb.writeln('=== 输入法切换结果 (ime_id=$imeId) ===');
          sb.writeln(r);
        }
        if (sb.isEmpty) {
          return const ToolResult.error('brightness 或 ime_id 至少填一个');
        }
        return ToolResult.ok(sb.toString());
      },
    );

/// H17-5: 壁纸设置 + 系统分享
Tool _wallpaperAndShareTool(AndroidAutomationService s) => Tool(
      name: 'android_wallpaper_or_share',
      description: '【开放操作】壁纸设置和系统分享合并成一个工具。',
      schema: _props({
        'set_wallpaper_path': {
          'type': 'string',
          'description': '图片文件绝对路径',
        },
        'wallpaper_which': {
          'type': 'string',
          'description': '"home" = 只设桌面壁纸；"lock" = 只设锁屏；"both" = 同时设 (默认)',
        },
        'share_text': {
          'type': 'string',
          'description': '要分享的文字内容',
        },
        'share_image_path': {
          'type': 'string',
          'description': '要分享的图片/视频文件的绝对路径',
        },
        'share_target_package': {
          'type': 'string',
          'description': '想直接投给哪个 App 的包名',
        },
        'share_target_component': {
          'type': 'string',
          'description': '可选，精确到某个 Activity 的完整 component 名',
        },
        'share_file_mime': {
          'type': 'string',
          'description': '可选，手动指定 MIME',
        },
      }),
      handler: (args) async {
        final sb = StringBuffer();
        final wpPath = (args['set_wallpaper_path'] as String?)?.trim() ?? '';
        if (wpPath.isNotEmpty) {
          final which =
              (args['wallpaper_which'] as String?)?.trim().toLowerCase() ??
                  'both';
          final r = await s.setWallpaper(wpPath, which: which);
          sb.writeln('=== 壁纸设置 (path=$wpPath, which=$which) ===');
          sb.writeln(r.ok ? '✅ OK' : '❌ FAIL exit=${r.exitCode}');
          sb.writeln(r.stdout.isEmpty ? r.stderr : r.stdout);
          sb.writeln();
        }
        final sText = args['share_text'] as String?;
        final sImg = args['share_image_path'] as String?;
        final hasShare = (sText != null && sText.trim().isNotEmpty) ||
            (sImg != null && sImg.trim().isNotEmpty);
        if (hasShare) {
          final r = await s.shareSystem(
            imagePath: sImg,
            text: sText,
            fileMime: args['share_file_mime'] as String?,
            targetPackage: args['share_target_package'] as String?,
            targetComponent: args['share_target_component'] as String?,
          );
          sb.writeln('=== 系统分享结果 ===');
          sb.writeln('text=${sText == null ? "(none)" : "${sText.length}字"}'
              '  image=${sImg ?? "(none)"}'
              '  pkg=${args['share_target_package'] ?? "(system picker)"}');
          sb.writeln(r.ok ? '✅ Intent 已下发' : '❌ FAIL exit=${r.exitCode}');
          sb.writeln(r.stdout.isEmpty ? r.stderr : r.stdout);
        }
        if (sb.isEmpty) {
          return const ToolResult.error(
              'set_wallpaper_path 或 share_text/share_image_path 至少填一组');
        }
        return ToolResult.ok(sb.toString());
      },
    );
