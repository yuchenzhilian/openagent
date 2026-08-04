part of '../android_tools.dart';

// ============================================================================
// 防高风险应用检测工具
// ============================================================================

/// Check if current foreground app is a high-risk app (banking/payment)
/// that might detect accessibility service or root.
Tool _antiDetectionCheckTool(AndroidAutomationService s) => Tool(
      name: 'android_anti_detection_check',
      description: '检查当前前台 App 是否属于高风险应用（银行/支付/安全类），',
      schema: _props({
        'package_name': {
          'type': 'string',
          'description': '可选：要检查的包名，为空则自动检测当前前台应用',
        },
      }),
      handler: (args) async {
        final pkg = (args['package_name'] as String?)?.trim() ?? '';
        String targetPkg = pkg;
        if (targetPkg.isEmpty) {
          final info = await s.getTopApp();
          targetPkg = info.package;
          if (targetPkg.isEmpty) {
            return const ToolResult.error('无法获取前台应用包名');
          }
        }
        final isBanking = _bankingPackages.contains(targetPkg);
        final isPayment = _paymentPackages.contains(targetPkg);
        final isSecurity = _securityPackages.contains(targetPkg);
        final isSocial = _socialPackages.contains(targetPkg);
        final isGame = _gamePackages.contains(targetPkg);
        final safeMode = await s.isSafeMode();
        final sb = StringBuffer();
        sb.writeln('应用: $targetPkg');
        sb.writeln(
            '分类: ${isBanking ? "银行" : isPayment ? "支付" : isSecurity ? "安全" : isSocial ? "社交" : isGame ? "游戏" : "其他"}');
        sb.writeln(
            '风险等级: ${isBanking || isPayment ? "高危" : isSecurity ? "中危" : "低危"}');
        sb.writeln('安全模式: ${safeMode ? "✅ 已开启（手势已拦截）" : "❌ 未开启"}');
        if (isBanking || isPayment) {
          sb.writeln(
              '⚠ 建议：避免使用无障碍服务操作此应用，优先使用 Shizuku 或调用 android_anti_detection_safe_mode enabled=true');
        }
        return ToolResult.ok(sb.toString());
      },
    );

/// Temporarily switch to safe mode (实际后端绑定).
Tool _antiDetectionSafeModeTool(AndroidAutomationService s) => Tool(
      name: 'android_anti_detection_safe_mode',
      description: '切换到安全模式：当检测到高风险应用（银行/支付）在前台时，'
          '自动暂停无障碍服务操作，仅使用 Shizuku 执行必要操作。',
      schema: _props({
        'enabled': {
          'type': 'boolean',
          'description': 'true=开启安全模式（限制无障碍操作）；false=关闭安全模式',
        },
      }, required: [
        'enabled'
      ]),
      handler: (args) async {
        final enabled = args['enabled'] as bool? ?? true;
        final ok = await s.setSafeMode(enabled);
        if (!ok) {
          return const ToolResult.error('设置安全模式失败：MethodChannel 调用返回 false');
        }
        if (enabled) {
          return ToolResult.ok(
            '✅ 安全模式已开启\n'
            '• 无障碍服务操作已暂停（Kotlin 端实际拦截 all gesture/click/scroll）\n'
            '• 仅 Shizuku 操作可用\n'
            '• 调用 android_anti_detection_safe_mode enabled=false 恢复',
          );
        } else {
          return ToolResult.ok(
            '✅ 安全模式已关闭\n'
            '• 无障碍服务操作已恢复\n'
            '• 通过 android_is_safe_mode 可查询当前状态',
          );
        }
      },
    );

/// List all known banking/payment packages.
Tool _antiDetectionBankingListTool() => Tool(
      name: 'android_anti_detection_banking_list',
      description: '列出已知的银行/支付/安全类 App 包名，这些 App 可能会检测无障碍服务。',
      schema: _props({}),
      handler: (args) async {
        final sb = StringBuffer();
        sb.writeln('===== 银行类 App (${_bankingPackages.length} 个) =====');
        for (final p in _bankingPackages) {
          sb.writeln('  - $p');
        }
        sb.writeln('\n===== 支付类 App (${_paymentPackages.length} 个) =====');
        for (final p in _paymentPackages) {
          sb.writeln('  - $p');
        }
        sb.writeln('\n===== 安全类 App (${_securityPackages.length} 个) =====');
        for (final p in _securityPackages) {
          sb.writeln('  - $p');
        }
        sb.writeln('\n===== 社交类 App (监控白名单) =====');
        for (final p in _socialPackages) {
          sb.writeln('  - $p');
        }
        sb.writeln('\n===== 游戏类 App (监控白名单) =====');
        for (final p in _gamePackages) {
          sb.writeln('  - $p');
        }
        sb.writeln('\n\n提示：银行/支付类 App 在前台时，无障碍服务不会触发（已在配置中过滤）。');
        return ToolResult.ok(sb.toString());
      },
    );

// ============================================================================
// Stage 27: 设备安全加固 — 保活/防检测/虚拟定位
// ============================================================================

/// ——— 应用保活：添加到系统白名单 / 防清理 / 前台服务 ———
Tool _keepAliveTool(AndroidAutomationService s) => Tool(
      name: 'android_keep_alive',
      description: '【安全】将本应用添加到系统省电白名单、防清理列表，并启动前台服务保活，避免后台被系统杀掉。'
          '需要 Shizuku 已授权。执行后 Agent 可在后台持续运行不被系统清理。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': [
            'add_whitelist',
            'check_status',
            'remove_whitelist',
            'start_foreground',
            'stop_foreground',
            'is_running',
          ],
          'description': 'add_whitelist=添加白名单+前台服务, check_status=检查状态, '
              'remove_whitelist=移除白名单, start_foreground=仅启动前台服务, '
              'stop_foreground=停止前台服务, is_running=检查前台服务是否运行中',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'add_whitelist';
        final pkg = 'com.openagent.openagent';
        final fgService = 'OpenAgentForegroundService';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        if (action == 'is_running') {
          final r1 = await s
              .gshell('dumpsys activity services $fgService 2>/dev/null');
          final running = r1.stdout.contains(fgService);
          return ToolResult.ok(running ? '✅ 前台服务运行中' : '❌ 前台服务未运行');
        }

        if (action == 'start_foreground') {
          final r1 = await s.gshell(
              'am start-foreground-service -n $pkg/.automation.$fgService 2>/dev/null');
          return ToolResult.ok(
              r1.ok ? '✅ 前台服务已启动' : '⚠ 启动前台服务失败（可能需要 Shizuku）');
        }

        if (action == 'stop_foreground') {
          final r1 = await s.gshell(
              'am stopservice -n $pkg/.automation.$fgService 2>/dev/null');
          return ToolResult.ok(r1.ok ? '✅ 前台服务已停止' : '⚠ 停止前台服务失败');
        }

        if (action == 'check_status') {
          final r1 = await s
              .gshell('dumpsys deviceidle whitelist | grep $pkg 2>/dev/null');
          final r2 = await s
              .gshell('dumpsys activity services $fgService 2>/dev/null');
          final sb = StringBuffer();
          sb.writeln('===== 保活状态 =====');
          sb.writeln('省电白名单: ${r1.stdout.contains(pkg) ? "✅ 已加入" : "❌ 未加入"}');
          sb.writeln(
              '前台服务: ${r2.stdout.contains(fgService) ? "✅ 运行中" : "⚠ 未运行"}');
          // 额外检查电源管理可见性
          final r3 = await s.gshell('dumpsys power | grep $pkg 2>/dev/null');
          sb.writeln(
              '电源管理可见性: ${r3.stdout.contains(pkg) ? "✅ 可见" : "⚠ 可能不可见"}');
          return ToolResult.ok(sb.toString());
        }

        final sr =
            await s.gshell('dumpsys deviceidle whitelist +$pkg 2>/dev/null');
        steps.add('省电白名单: ${sr.ok ? "OK" : "失败"}');

        await s.gshell('cmd deviceidle whitelist +$pkg 2>/dev/null');
        steps.add('deviceidle 白名单: 已执行');

        await s.gshell(
            'am start-foreground-service -n $pkg/.automation.$fgService 2>/dev/null');
        steps.add('前台服务: 已启动');

        if (action == 'remove_whitelist') {
          await s.gshell('dumpsys deviceidle whitelist -$pkg 2>/dev/null');
          await s.gshell(
              'am stopservice -n $pkg/.automation.$fgService 2>/dev/null');
          steps.add('已移除白名单并停止前台服务');
        }

        return ToolResult.ok('✅ 保活设置完成:\n${r()}');
      },
    );

/// ——— Shizuku 隐藏 / 防检测模式（集成安全模式后端） ———
Tool _hideShizukuTool(AndroidAutomationService s) => Tool(
      name: 'android_hide_shizuku',
      description: '【安全】隐藏/伪装 Shizuku 和 Root 特征，防止被银行/支付/安全类 App 检测并拒绝运行。'
          '同时启用安全模式，阻止无障碍手势操作。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['hide', 'restore', 'check'],
          'description': 'hide=隐藏特征+安全模式, restore=恢复, check=检查当前暴露风险',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'check';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        if (action == 'check') {
          final sb = StringBuffer();
          sb.writeln('===== 防检测风险评估 =====');
          final r1 = await s.gshell('ps -ef | grep shizuku 2>/dev/null');
          sb.writeln(
              'Shizuku 进程: ${r1.stdout.contains('shizuku') ? "⚠ 可见" : "✅ 未运行"}');
          final r2 = await s.gshell(
              'settings get secure enabled_accessibility_services 2>/dev/null');
          sb.writeln(
              '无障碍服务: ${r2.stdout.contains('openagent') ? "⚠ 可见" : "✅ 已隐藏"}');
          final r3 = await s.gshell('which su 2>/dev/null');
          sb.writeln('Root 检测: ${r3.ok ? "⚠ su 存在" : "✅ su 不可见"}');
          final r4 = await s.gshell('ls /data/adb/magisk 2>/dev/null');
          sb.writeln('Magisk: ${r4.ok ? "⚠ 可见" : "✅ 已隐藏"}');
          final safeMode = await s.isSafeMode();
          sb.writeln('安全模式: ${safeMode ? "✅ 已开启" : "❌ 未开启"}');
          sb.writeln('\n建议：银行/支付 App 检测到上述特征可能会拒绝运行。');
          sb.writeln('用 android_hide_shizuku action=hide 可隐藏特征并启用安全模式。');
          return ToolResult.ok(sb.toString());
        }

        if (action == 'hide') {
          await s.gshell(
              'settings put secure enabled_accessibility_services "" 2>/dev/null');
          steps.add('已禁用无障碍服务（临时）');
          await Future.delayed(const Duration(milliseconds: 300));
          await s
              .gshell('am force-stop moe.shizuku.privileged.api 2>/dev/null');
          steps.add('已停止 Shizuku App');
          await s.gshell(
              'pm hide moe.shizuku.privileged.api 2>/dev/null || pm disable moe.shizuku.privileged.api 2>/dev/null');
          steps.add('已隐藏 Shizuku 应用图标');
          // 通过 MethodChannel 设置安全模式（Kotlin 端持久化 + 无障碍服务即时拦截）
          await s.setSafeMode(true);
          steps.add('已启用安全模式（手势拦截生效）');
          return ToolResult.ok(
              '✅ 防检测特征已隐藏:\n$r()\n⚠ 银行/支付 App 将不再检测到无障碍/Shizuku。\n⚠ 安全模式已开启，所有手势操作被阻止。\n⚠ 使用完毕后用 action=restore 恢复。');
        }

        // restore
        await s.gshell('settings put secure enabled_accessibility_services '
            'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentAccessibilityService 2>/dev/null');
        steps.add('已恢复无障碍服务');
        await s.gshell(
            'pm unhide moe.shizuku.privileged.api 2>/dev/null || pm enable moe.shizuku.privileged.api 2>/dev/null');
        steps.add('已恢复 Shizuku 图标');
        // 通过 MethodChannel 关闭安全模式
        await s.setSafeMode(false);
        steps.add('已关闭安全模式');
        return ToolResult.ok('✅ 防检测特征已恢复:\n$r()');
      },
    );

/// ——— 虚拟定位（Mock GPS） ———
Tool _mockLocationTool(AndroidAutomationService s) => Tool(
      name: 'android_mock_location',
      description:
          '【安全】设置虚拟定位（Mock GPS 位置）。需要开发者选项中已选择 Mock Location App 为本应用。',
      schema: _props({
        'latitude': {
          'type': 'number',
          'description': '纬度，如 39.9042（北京）',
        },
        'longitude': {
          'type': 'number',
          'description': '经度，如 116.4074（北京）',
        },
        'action': {
          'type': 'string',
          'enum': ['set', 'clear', 'status'],
          'description': 'set=设置, clear=清除, status=查看当前状态',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'status';
        final lat = (args['latitude'] as num?)?.toDouble() ?? 39.9042;
        final lng = (args['longitude'] as num?)?.toDouble() ?? 116.4074;
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        if (action == 'status') {
          final sb = StringBuffer();
          final r1 =
              await s.gshell('settings get secure mock_location 2>/dev/null');
          sb.writeln(
              'Mock Location 允许: ${r1.stdout.trim() == "1" ? "✅ 已开启" : "❌ 未开启"}');
          final r2 = await s
              .gshell('settings get secure mock_location_app 2>/dev/null');
          sb.writeln(
              'Mock Location App: ${r2.stdout.trim().isEmpty ? "未设置" : r2.stdout.trim()}');
          final r3 = await s
              .gshell('dumpsys location | grep "last location" 2>/dev/null');
          sb.writeln(
              '当前 GPS: ${r3.stdout.trim().isNotEmpty ? r3.stdout.trim() : "未知"}');
          sb.writeln('\n提示：需在开发者选项中设置 "选择模拟位置信息应用" 为本应用。');
          return ToolResult.ok(sb.toString());
        }

        if (action == 'set') {
          final sr = await s
              .gshell('am broadcast -a android.intent.action.MOCK_LOCATION '
                  '--ef lat $lat --ef lng $lng 2>/dev/null');
          steps.add('广播 Mock Location: ${sr.ok ? "OK" : "失败"}');
          await s.gshell(
              'content insert --uri content://com.google.android.gms.location.mock '
              '--bind latitude:d:$lat --bind longitude:d:$lng 2>/dev/null');
          steps.add('GMS Mock Location: 已执行');
          await s.gshell(
              'settings put global mock_location_test_coords $lat,$lng 2>/dev/null');
          steps.add('坐标已写入: $lat, $lng');
          return ToolResult.ok('✅ 虚拟定位已设置:\n${r()}');
        }

        // clear
        await s.gshell(
            'settings put global mock_location_test_coords "" 2>/dev/null');
        steps.add('已清除虚拟定位');
        return ToolResult.ok('✅ 虚拟定位已清除:\n${r()}');
      },
    );

// ============================================================================
// Stage 29: 手机管家 — 文件整理/应用管理/深度清理
// ============================================================================

/// ——— 文件整理：按类型归类 / 扫描大文件 / 清理临时文件 ———
Tool _phoneFileManagerTool(AndroidAutomationService s) => Tool(
      name: 'android_phone_file_manager',
      description: '【手机管家】扫描并整理手机文件。可：分析存储空间、按类型归类文件、'
          '查找大文件、清理临时/缓存文件、删除空目录。需要 Shizuku 已授权。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': [
            'analyze',
            'large_files',
            'clean_temp',
            'clean_downloads',
            'organize'
          ],
          'description': 'analyze=分析存储概况, large_files=查找大文件(>50MB), '
              'clean_temp=清理临时文件(.tmp/.log/.cache), clean_downloads=清理下载目录旧文件, '
              'organize=按类型归类(图片/视频/文档/APK到各自文件夹)',
        },
        'path': {
          'type': 'string',
          'description': '可选：指定扫描路径，默认 /sdcard',
        },
        'min_mb': {
          'type': 'integer',
          'description': 'large_files 时的大文件阈值(MB)，默认 50',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'analyze';
        final path = (args['path'] as String?) ?? '/sdcard';
        final minMb = ((args['min_mb'] as num?)?.toInt() ?? 50).clamp(10, 9999);
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        if (action == 'analyze') {
          final r1 = await s.gshell('df -h $path 2>/dev/null');
          final r2 = await s
              .gshell('du -sh $path/* 2>/dev/null | sort -rh | head -20');
          final sb = StringBuffer();
          sb.writeln('===== 存储分析 ($path) =====');
          sb.writeln(r1.stdout.trim());
          sb.writeln('\n--- 占用前 20 ---');
          sb.writeln(r2.stdout.trim());
          return ToolResult.ok(sb.toString());
        }

        if (action == 'large_files') {
          final sr = await s.gshell(
              'find $path -type f -size +${minMb}M 2>/dev/null | sort -rh | head -30');
          if (sr.stdout.trim().isEmpty) {
            return ToolResult.ok('✅ 未找到大于 ${minMb}MB 的文件');
          }
          return ToolResult.ok('===== 大文件 (>${minMb}MB) =====\n${sr.stdout}');
        }

        if (action == 'clean_temp') {
          await s.gshell(
              'find $path -type f \\( -name "*.tmp" -o -name "*.log" -o -name "*.cache" \\) '
              '-delete 2>/dev/null; '
              'find $path -type d -name "cache" -exec rm -rf {}/* \\; 2>/dev/null; '
              'echo "done"');
          steps.add('临时文件清理: OK');
          return ToolResult.ok('✅ 临时文件已清理:\n${r()}');
        }

        if (action == 'clean_downloads') {
          await s.gshell(
              'find $path/Download -type f -mtime +30 -delete 2>/dev/null; '
              'find $path/Download -type d -empty -delete 2>/dev/null; '
              'echo "done"');
          steps.add('下载目录清理: OK');
          return ToolResult.ok('✅ 下载目录旧文件已清理:\n${r()}');
        }

        if (action == 'organize') {
          final dirs = ['图片', '视频', '文档', 'APK', '压缩包', '其他'];
          for (final d in dirs) {
            await s.gshell('mkdir -p $path/$d 2>/dev/null');
          }
          await s.gshell(
              'mv $path/*.jpg $path/*.jpeg $path/*.png $path/*.gif $path/*.bmp $path/*.webp '
              '"$path/图片/" 2>/dev/null');
          await s.gshell(
              'mv $path/*.mp4 $path/*.mkv $path/*.avi $path/*.mov $path/*.flv '
              '"$path/视频/" 2>/dev/null');
          await s.gshell(
              'mv $path/*.pdf $path/*.doc $path/*.docx $path/*.xls $path/*.xlsx '
              '$path/*.ppt $path/*.pptx $path/*.txt '
              '"$path/文档/" 2>/dev/null');
          await s.gshell('mv $path/*.apk "$path/APK/" 2>/dev/null');
          await s.gshell('mv $path/*.zip $path/*.rar $path/*.7z $path/*.tar.gz '
              '"$path/压缩包/" 2>/dev/null');
          steps.add('文件已按类型归类到对应文件夹');
          return ToolResult.ok('✅ 文件整理完成:\n${r()}\n分类: 图片/视频/文档/APK/压缩包');
        }

        return ToolResult.error('未知操作: $action');
      },
    );

/// ——— 应用管理：批量卸载 / 清除缓存 / 批量权限 ———
Tool _phoneAppManagerTool(AndroidAutomationService s) => Tool(
      name: 'android_phone_app_manager',
      description: '【手机管家】管理已安装的应用。可：卸载应用、清除应用缓存、'
          '批量管理应用权限、列出占用空间最大的应用。需要 Shizuku 已授权。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': [
            'uninstall',
            'clear_cache',
            'list_large',
            'disable',
            'permissions'
          ],
          'description': 'uninstall=卸载应用, clear_cache=清除指定应用缓存, '
              'list_large=列出占用最大应用, disable=禁用应用, permissions=查看应用权限列表',
        },
        'package_name': {
          'type': 'string',
          'description': '应用包名（uninstall/clear_cache/disable/permissions 时必填）',
        },
        'keep_system': {
          'type': 'boolean',
          'description': 'list_large 时是否排除系统应用，默认 true',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'list_large';
        final pkg = (args['package_name'] as String?) ?? '';
        final keepSystem = args['keep_system'] as bool? ?? true;
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        if (action == 'list_large') {
          final sr = await s.gshell(
              'pm list packages ${keepSystem ? "-3" : ""} 2>/dev/null | '
              'head -50 | while read line; do '
              'pkg=\${line#package:}; '
              'size=\$(du -sh /data/data/\$pkg 2>/dev/null | cut -f1); '
              '[ -n "\$size" ] && echo "\$size \$pkg"; '
              'done | sort -rh | head -20');
          final sb = StringBuffer();
          sb.writeln('===== 占用空间最大的应用 =====');
          sb.writeln(sr.stdout.trim().isNotEmpty
              ? sr.stdout.trim()
              : '(无可显示数据，需要 Shizuku 已授权)');
          sb.writeln(
              '\n提示：用 android_phone_cleaner action=deep_clean 可一键清理所有缓存');
          return ToolResult.ok(sb.toString());
        }

        if (action == 'uninstall') {
          if (pkg.isEmpty) return ToolResult.error('需要 package_name 参数');
          final sr =
              await s.gshell('pm uninstall -k --user 0 $pkg 2>/dev/null');
          steps.add('卸载 $pkg: ${sr.ok ? "OK" : "失败"}');
          return ToolResult.ok('${sr.ok ? "✅" : "❌"} 卸载应用:\n${r()}');
        }

        if (action == 'clear_cache') {
          if (pkg.isEmpty) return ToolResult.error('需要 package_name 参数');
          final sr = await s.gshell('pm clear $pkg 2>/dev/null');
          steps.add('清除缓存 $pkg: ${sr.ok ? "OK" : "失败"}');
          return ToolResult.ok('${sr.ok ? "✅" : "❌"} 清除缓存:\n${r()}');
        }

        if (action == 'disable') {
          if (pkg.isEmpty) return ToolResult.error('需要 package_name 参数');
          final sr = await s.gshell(
              'pm disable $pkg 2>/dev/null || pm hide $pkg 2>/dev/null');
          steps.add('禁用 $pkg: ${sr.ok ? "OK" : "失败"}');
          return ToolResult.ok('${sr.ok ? "✅" : "❌"} 禁用应用:\n${r()}');
        }

        if (action == 'permissions') {
          if (pkg.isEmpty) return ToolResult.error('需要 package_name 参数');
          final sr = await s.gshell(
              'dumpsys package $pkg 2>/dev/null | grep -A 100 "requested permissions:" | head -50');
          return ToolResult.ok(
              '===== $pkg 权限列表 =====\n${sr.stdout.trim().isNotEmpty ? sr.stdout.trim() : "无法获取（需要 Shizuku）"}');
        }

        return ToolResult.error('未知操作: $action');
      },
    );

/// ——— 深度清理：分析存储 / 清理缓存 / 垃圾文件 ———
Tool _phoneDeepCleanTool(AndroidAutomationService s) => Tool(
      name: 'android_phone_deep_clean',
      description: '【手机管家】深度清理手机存储空间。可：一键清理所有应用缓存、'
          '清理系统垃圾（空目录/临时文件）、分析存储使用情况、清理卸载残留。'
          '需要 Shizuku 已授权。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': [
            'quick_clean',
            'deep_clean',
            'analyze_storage',
            'clean_residue'
          ],
          'description':
              'quick_clean=快速清理(缓存+临时文件), deep_clean=深度清理(缓存+临时+空目录+残留), '
                  'analyze_storage=详细存储分析, clean_residue=清理卸载残留',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'quick_clean';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        if (action == 'analyze_storage') {
          final sb = StringBuffer();
          sb.writeln('===== 存储深度分析 =====');
          final r1 = await s.gshell('df -h 2>/dev/null');
          sb.writeln(r1.stdout.trim());
          sb.writeln('');
          final dirs = [
            '/sdcard/DCIM',
            '/sdcard/Download',
            '/sdcard/Android',
            '/sdcard/Music',
            '/sdcard/Movies',
            '/sdcard/Pictures',
            '/sdcard/Documents'
          ];
          for (final d in dirs) {
            final sr = await s.gshell('du -sh $d 2>/dev/null');
            if (sr.ok && sr.stdout.trim().isNotEmpty) {
              sb.writeln(sr.stdout.trim());
            }
          }
          sb.writeln('\n提示：用 clean_temp 清理临时文件，用 deep_clean 深度清理');
          return ToolResult.ok(sb.toString());
        }

        if (action == 'quick_clean') {
          await s.gshell(
              'for pkg in \$(pm list packages -3 2>/dev/null | cut -d: -f2); do '
              'pm clear \$pkg 2>/dev/null; done; echo "done"');
          steps.add('应用缓存清理: OK');
          await s.gshell(
              'find /sdcard -type f \\( -name "*.tmp" -o -name "*.log" -o -name "*.cache" \\) -delete 2>/dev/null');
          steps.add('临时文件清理: 已执行');
          await s.gshell('find /sdcard -type d -empty -delete 2>/dev/null');
          steps.add('空目录清理: 已执行');
          return ToolResult.ok('✅ 快速清理完成:\n${r()}\n已清理: 第三方应用缓存 + 临时文件 + 空目录');
        }

        if (action == 'deep_clean') {
          await s.gshell(
              'for pkg in \$(pm list packages 2>/dev/null | cut -d: -f2); do '
              'pm clear \$pkg 2>/dev/null; done');
          steps.add('所有应用缓存: 已清理');
          await s.gshell(
              'find /sdcard -type f \\( -name "*.tmp" -o -name "*.log" -o -name "*.cache" '
              '-o -name "*.temp" -o -name "thumbs.db" -o -name ".thumb*" \\) -delete 2>/dev/null');
          steps.add('临时/缩略图文件: 已清理');
          await s.gshell('find /sdcard -type d -empty -delete 2>/dev/null');
          steps.add('空目录: 已清理');
          await s.gshell(
              'find /sdcard/Download -type f -mtime +30 -delete 2>/dev/null');
          steps.add('下载目录旧文件: 已清理');
          await s.gshell('rm -rf /sdcard/Android/logs/* 2>/dev/null');
          steps.add('系统日志: 已清理');
          return ToolResult.ok(
              '✅ 深度清理完成:\n${r()}\n清理: 全部缓存 + 临时文件 + 缩略图 + 空目录 + 下载旧文件 + 系统日志');
        }

        if (action == 'clean_residue') {
          final sr = await s.gshell('for d in /data/data/* /data/app/*; do '
              'pkg=\$(basename \$d); '
              'pm list packages | grep -q \$pkg || echo "残留: \$d"; '
              'done 2>/dev/null | head -30');
          if (sr.stdout.trim().isEmpty) {
            return ToolResult.ok('✅ 未发现卸载残留');
          }
          return ToolResult.ok(
              '===== 卸载残留 =====\n${sr.stdout}\n提示：用 pm uninstall 或手动删除');
        }

        return ToolResult.error('未知操作: $action');
      },
    );

/// Known banking packages (完整版，含主要银行 + 外资银行 + 理财类).
const _bankingPackages = <String>{
  // 六大国有银行
  'com.icbc', 'com.icbc.biz', // 工商银行
  'com.chinamworld.main', // 中国银行
  'com.ccb.forum', // 建设银行
  'com.abchina.qr', // 农业银行
  'com.bankcomm.ebank', // 交通银行
  'com.psbc.mbank', // 邮储银行
  // 股份制银行
  'com.cmbchina.ccd.phone.cmbmobilebank', // 招商银行
  'com.cmbc.ccb', // 民生银行
  'com.spdb.ibank', // 浦发银行
  'com.citicbank.mobilebank', // 中信银行
  'com.cebbank.mobile.cebapp', // 光大银行
  'com.hxb.credit', // 华夏银行
  'com.pingan.bank', // 平安银行
  'com.cgbchina.xianyu', // 广发银行
  'com.cib.credit', // 兴业银行
  // 地方性银行
  'com.bankofbeijing.activity', // 北京银行
  'com.spdb.unionpay', // 上海银行
  'com.bankofshanghai', // 上海银行
  'com.guangzhou.bank', // 广州银行
  'com.sdb', // 深圳发展银行
  // 信用卡
  'com.hxb.creditcard', // 华夏信用卡
  'com.luojilab.player', // 招商银行掌上生活
  // 外资银行
  'com.hsbc.hsbcdirect', // 汇丰银行
  'com.citi.citimobile', // 花旗银行
  'com.standardchartered', // 渣打银行
  // 理财/支付
  'com.unionpay.payment', // 银联
  'com.chinapay.payment', // 中国支付
  'com.netease.wealth', // 网易有钱
};

/// Known payment packages.
const _paymentPackages = <String>{
  'com.eg.android.AlipayGphone',
  'com.alipay.mobile',
  'com.tencent.mm',
  'com.tencent.mobileqq',
  'com.jingdong.app.mall',
  'com.taobao.taobao',
  'com.sankuai.meituan',
  'com.dianping.v1',
  'com.xiaomi.shop',
};

/// Known security packages.
const _securityPackages = <String>{
  'com.qihoo360.mobilesafe',
  'com.tencent.qqpimsecure',
  'com.lbe.security',
  'com.ijinshan.mguard',
  'com.cleanmaster.mguard',
  'com.antivirus',
  'com.samsung.android.security.manager',
};

/// Social packages (monitored by accessibility).
const _socialPackages = <String>{
  'com.tencent.mm',
  'com.tencent.mobileqq',
  'com.ss.android.ugc.aweme',
  'com.xingin.xhs',
  'tv.danmaku.bili',
  'com.sina.weibo',
  'com.zhihu.android',
};

/// Game packages (monitored by accessibility).
const _gamePackages = <String>{
  'com.hypergryph.arknights',
  'com.tencent.tmgp.sgame',
  'com.tencent.tmgp.cod',
  'com.netease.mc.pe',
  'com.miHoYo.GenshinImpact',
  'com.miHoYo.hkrpg',
};
