// Permission guide page for Android automation layers.
//
// Walks the user through enabling the 3 tiers of privilege needed for the
// full OpenAgent Android-automation experience, with status indicators and
// big "跳转开启" action buttons that deep-link to the right Settings screen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/models.dart';
import '../../../data/services/android_automation_service.dart';
import '../../../data/services/file_storage_service.dart';

class PermissionGuidePage extends StatefulWidget {
  const PermissionGuidePage({
    super.key,
    required this.storage,
  });

  final FileStorageService storage;

  @override
  State<PermissionGuidePage> createState() => _PermissionGuidePageState();
}

class _PermissionGuidePageState extends State<PermissionGuidePage> {
  final AndroidAutomationService _svc = AndroidAutomationService.instance;
  AutomationPermissionStatus _status = const AutomationPermissionStatus();
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Poll every 5s so the UI reflects when the user returns from Settings.
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!_svc.isSupported) {
      setState(() => _loading = false);
      return;
    }
    final cfg = await widget.storage.loadAppConfig();
    final runtimeStatus = await _svc.refreshStatus();
    final merged = cfg.automation.copyWith(
      accessibilityEnabled: runtimeStatus.accessibilityEnabled ||
          cfg.automation.accessibilityEnabled,
      shizukuGranted:
          runtimeStatus.shizukuGranted || cfg.automation.shizukuGranted,
      screenshotGranted:
          runtimeStatus.screenshotGranted || cfg.automation.screenshotGranted,
      usageStatsGranted:
          runtimeStatus.usageStatsGranted || cfg.automation.usageStatsGranted,
      notificationListenerGranted: runtimeStatus.notificationListenerGranted ||
          cfg.automation.notificationListenerGranted,
    );
    if (!mounted) return;
    final allEnabled = merged.accessibilityEnabled &&
        merged.shizukuGranted &&
        merged.screenshotGranted &&
        merged.usageStatsGranted;
    setState(() {
      _status = merged;
      _loading = false;
    });
    // 所有权限已开启时，停止轮询
    if (allEnabled && _refreshTimer != null && _refreshTimer!.isActive) {
      _refreshTimer?.cancel();
    }
    // Persist merged status back so the Agent runtime can pick it up.
    if (merged != cfg.automation) {
      await widget.storage.saveAppConfig(cfg.copyWith(automation: merged));
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = _svc.isSupported;
    return Scaffold(
      appBar: AppBar(
        title: const Text('自动化权限引导'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!supported)
                  _warn('当前平台不是 Android，自动化功能仅在 Android 真机上可用（可在模拟器或真机上运行）。'),
                if (!_status.warningDismissed) ...[
                  _warningCard(),
                  const SizedBox(height: 16),
                ],
                const Text('三层权限架构 + 辅助授权',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  '越往下能力越强，设置也越多。首版建议开启 L1 + 辅助「应用使用统计」即可覆盖微信/抖音/小红书 95% 操作场景。'
                  'L2 (Shizuku) 适合游戏/精准坐标；L3 (截图) 仅在 Omni 视觉时开启。',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _permissionTile(
                  tier: 'L1',
                  name: '无障碍服务 (Accessibility)',
                  description:
                      '能识别屏幕上的文字/按钮、执行点击/滑动/输入。覆盖微信/抖音/小红书等标准 App 90% 操作场景。',
                  icon: Icons.accessibility_new,
                  color: Colors.green,
                  status: _status.accessibilityEnabled,
                  onTap: () async {
                    await _svc.openAccessibilitySettings();
                  },
                ),
                const SizedBox(height: 10),
                _permissionTile(
                  tier: 'L2',
                  name: 'Shizuku 高级权限',
                  description:
                      '实现精准坐标点击、滑动、任意硬件按键、静默安装 APK、截图等游戏控制场景需开启此项。需安装 Shizuku App 并一次性授权。',
                  icon: Icons.bolt,
                  color: Colors.orange,
                  status: _status.shizukuGranted,
                  onTap: () async {
                    final ok = await _svc.openShizukuApp();
                    if (!ok) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                '未检测到 Shizuku，请先从应用商店或官网 moe.shizuku.privileged.api 下载安装')),
                      );
                    }
                  },
                  extra: [
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _showShizukuGuide,
                      icon: const Icon(Icons.help_outline, size: 18),
                      label: const Text('如何启用 Shizuku？(向导)'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Card(
                  elevation: 1,
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.auto_fix_high,
                              color: Colors.amber.shade800),
                          const SizedBox(width: 8),
                          const Text('一键自动授权',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.amber,
                                borderRadius: BorderRadius.circular(4)),
                            child: const Text('自动',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          '如果已开启 Shizuku，可一键自动授予以下权限，无需手动跳转设置：',
                          style: TextStyle(
                              height: 1.45,
                              color: Colors.grey.shade800,
                              fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        _autoGrantButton(
                          '自动启用无障碍服务',
                          Icons.accessibility_new,
                          _status.shizukuGranted &&
                              !_status.accessibilityEnabled,
                          () async {
                            final r = await _svc.gshell(
                                'settings put secure enabled_accessibility_services '
                                'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentAccessibilityService 2>/dev/null');
                            if (r.ok) {
                              await _svc.gshell(
                                  'settings put secure accessibility_enabled 1');
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('✅ 无障碍服务已自动启用')));
                              await _refresh();
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        _autoGrantButton(
                          '自动启用通知监听',
                          Icons.notifications,
                          _status.shizukuGranted &&
                              !_status.notificationListenerGranted,
                          () async {
                            await _svc.gshell(
                                'settings put secure enabled_notification_listeners '
                                'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentNotificationListener 2>/dev/null');
                            await _svc.gshell(
                                'settings put secure enabled_notification_assistant '
                                'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentNotificationListener 2>/dev/null');
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('✅ 通知监听已自动启用')));
                            await _refresh();
                          },
                        ),
                        const SizedBox(height: 8),
                        _autoGrantButton(
                          '授予 WRITE_SECURE_SETTINGS',
                          Icons.security,
                          _status.shizukuGranted,
                          () async {
                            final r = await _svc.gshell(
                                'pm grant com.openagent.openagent android.permission.WRITE_SECURE_SETTINGS 2>/dev/null');
                            if (r.ok) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('✅ WRITE_SECURE_SETTINGS 已授予')));
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        _autoGrantButton(
                          '授予 DUMP（查看所有 App 信息）',
                          Icons.info,
                          _status.shizukuGranted,
                          () async {
                            await _svc.gshell(
                                'pm grant com.openagent.openagent android.permission.DUMP 2>/dev/null');
                            await _svc.gshell(
                                'pm grant com.openagent.openagent android.permission.PACKAGE_USAGE_STATS 2>/dev/null');
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        '✅ DUMP + PACKAGE_USAGE_STATS 已授予')));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _permissionTile(
                  tier: '辅助',
                  name: '应用使用统计 (查询前台 App)',
                  description:
                      '让 Agent 能实时检测当前在前台运行的应用（例如"打开微信后 Agent 确认在微信再动手点击"）。'
                      '未开启时会退回 dumpsys shell fallback（需 Shizuku）。',
                  icon: Icons.query_stats,
                  color: Colors.lightBlue,
                  status: _status.usageStatsGranted,
                  onTap: () async {
                    await _svc.openUsageAccessSettings();
                  },
                  extra: [
                    const SizedBox(height: 6),
                    Text(
                      '  💡 授予后 Agent 可"先确认在对的 App 再操作"，避免误点到其他应用。',
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _permissionTile(
                  tier: 'L3',
                  name: '屏幕截图 (MediaProjection)',
                  description:
                      '配合 Omni 多模态模型看懂抖音/游戏等无文字界面，再决定操作。使用时会弹出一次性录屏授权。',
                  icon: Icons.screenshot_monitor,
                  color: Colors.indigo,
                  status: _status.screenshotGranted,
                  onTap: _requestScreenshot,
                ),
                const SizedBox(height: 16),
                // 一键全授权按钮（需 Shizuku 已授权）
                if (_status.shizukuGranted) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _allInOneGrant,
                      icon: const Icon(Icons.auto_fix_high, size: 20),
                      label: const Text('一键全授权（无障碍 + 通知 + 安全设置 + DUMP）'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                _summaryCard(),
                const SizedBox(height: 24),
                _antiDetectionCard(),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('返回对话页开始使用'),
                ),
              ],
            ),
    );
  }

  Widget _autoGrantButton(
    String label,
    IconData icon,
    bool enabled,
    VoidCallback onPressed,
  ) =>
      OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: enabled ? Colors.amber.shade800 : Colors.grey,
          side: BorderSide(
              color: enabled ? Colors.amber.shade300 : Colors.grey.shade300),
          minimumSize: const Size(double.infinity, 40),
        ),
      );

  /// 一键全授权：按顺序执行所有自动授权操作。
  Future<void> _allInOneGrant() async {
    if (!_status.shizukuGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要先开启 Shizuku 权限')),
      );
      return;
    }
    final results = <String>[];
    // 1) 无障碍服务
    final r1 = await _svc.gshell(
        'settings put secure enabled_accessibility_services '
        'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentAccessibilityService 2>/dev/null');
    await _svc
        .gshell('settings put secure accessibility_enabled 1 2>/dev/null');
    results.add('无障碍: ${r1.ok ? "✅" : "❌"}');

    // 2) 通知监听
    final r2 = await _svc.gshell(
        'settings put secure enabled_notification_listeners '
        'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentNotificationListener 2>/dev/null');
    results.add('通知监听: ${r2.ok ? "✅" : "❌"}');

    // 3) WRITE_SECURE_SETTINGS
    final r3 = await _svc.gshell(
        'pm grant com.openagent.openagent android.permission.WRITE_SECURE_SETTINGS 2>/dev/null');
    results.add('安全设置: ${r3.ok ? "✅" : "❌"}');

    // 4) DUMP + PACKAGE_USAGE_STATS
    final r4a = await _svc.gshell(
        'pm grant com.openagent.openagent android.permission.DUMP 2>/dev/null');
    final r4b = await _svc.gshell(
        'pm grant com.openagent.openagent android.permission.PACKAGE_USAGE_STATS 2>/dev/null');
    results.add('DUMP+统计: ${r4a.ok && r4b.ok ? "✅" : "❌"}');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('一键全授权完成\n${results.join(" | ")}'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
    // 清除缓存并刷新
    _svc.invalidatePermissionCache();
    await _refresh();
  }

  Widget _warningCard() => Card(
        color: Colors.red.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.warning_amber, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('风险提示',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade900))),
              ]),
              const SizedBox(height: 8),
              Text(
                '开启以上权限后，OpenAgent Agent 将可在您授权的范围内操控手机：打开应用、点击、输入文字等。'
                '请仅在您信任的场景下使用；所有操作均在本地完成，不会上传任何隐私数据。'
                '若出现误触请立即关闭对应权限。',
                style: TextStyle(height: 1.5, color: Colors.red.shade800),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade800),
                  onPressed: () async {
                    final cfg = await widget.storage.loadAppConfig();
                    await widget.storage.saveAppConfig(cfg.copyWith(
                        automation:
                            cfg.automation.copyWith(warningDismissed: true)));
                    await _refresh();
                  },
                  child: const Text('我已知晓风险，继续开启'),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _permissionTile({
    required String tier,
    required String name,
    required String description,
    required IconData icon,
    required Color color,
    required bool status,
    required VoidCallback onTap,
    List<Widget> extra = const [],
  }) =>
      Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, color: color, size: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(4)),
                            child: Text(tier,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(name,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600))),
                          _statusChip(status, okLabel: '已开启', badLabel: '未开启'),
                        ]),
                        const SizedBox(height: 6),
                        Text(description,
                            style: TextStyle(
                                height: 1.45,
                                color: Colors.grey.shade700,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _status.warningDismissed ? onTap : null,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('去开启 / 跳转到设置'),
                ),
              ),
              ...extra,
            ],
          ),
        ),
      );

  Widget _statusChip(bool ok,
          {required String okLabel, required String badLabel}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: ok ? Colors.green.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(ok ? okLabel : badLabel,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ok ? Colors.green.shade800 : Colors.grey.shade700)),
      );

  Widget _summaryCard() {
    final score = [
      _status.accessibilityEnabled,
      _status.shizukuGranted,
      _status.screenshotGranted,
    ].where((e) => e).length;
    final tier = score == 0
        ? '暂不可用'
        : score == 1
            ? '基础模式 (L1)：仅操作标准 App'
            : score == 2
                ? '进阶模式 (L1+L2)：支持游戏坐标点击'
                : '完整模式：全部功能可用';
    final color = score == 0
        ? Colors.grey
        : score == 1
            ? Colors.green
            : score == 2
                ? Colors.orange
                : Colors.indigo;
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(Icons.verified_outlined, size: 30, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前等级 $score / 3',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(tier,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color.shade800)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  /// Anti-detection tips card for high-risk apps detection.
  Widget _antiDetectionCard() => Card(
        color: Colors.orange.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.security_outlined, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('防高风险应用检测',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade900)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                '部分银行、支付类 App（如工行、建行、招商银行、支付宝等）会检测无障碍服务、'
                'Root、Shizuku、USB 调试等"高风险"特征，可能拒绝运行或限制功能。',
                style: TextStyle(
                    height: 1.5, color: Colors.orange.shade900, fontSize: 13),
              ),
              const SizedBox(height: 10),
              _antiDetectionTip(
                icon: Icons.visibility_off,
                title: '包名限制（已启用）',
                desc: 'OpenAgent 已配置为仅监控社交/工具类 App（微信、抖音、小红书等），'
                    '银行/支付类 App 在前台时不会触发无障碍服务，降低被检测风险。',
              ),
              const SizedBox(height: 8),
              _antiDetectionTip(
                icon: Icons.bolt,
                title: '优先使用 Shizuku',
                desc: 'Shizuku 授权比无障碍服务更隐蔽，应用难以检测。'
                    '建议在银行/支付类 App 上操作时优先使用 L2 Shizuku 而非 L1 无障碍。',
              ),
              const SizedBox(height: 8),
              _antiDetectionTip(
                icon: Icons.toggle_off_outlined,
                title: '临时关闭建议',
                desc: '使用银行/支付 App 前，可在设置中临时关闭无障碍服务。'
                    '操作完成后重新开启即可。转账等敏感操作建议手动进行。',
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: Colors.amber.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Agent 内置了防检测规则：当系统检测到前台为银行/支付类 App 时，'
                        '会自动切换为 Shizuku 操作模式或暂停自动化，确保安全。',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber.shade900,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _antiDetectionTip({
    required IconData icon,
    required String title,
    required String desc,
  }) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.orange.shade900)),
                const SizedBox(height: 2),
                Text(desc,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade800,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      );

  Widget _warn(String m) => Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade300)),
        child: Text(m, style: TextStyle(color: Colors.amber.shade900)),
      );

  void _requestScreenshot() async {
    // NOTE: MediaProjection permission must be granted from an Activity via
    // the Intent returned by createScreenCaptureIntent. The MethodChannel
    // bridge doesn't carry the ActivityResult launch flow yet.
    // Calling takeScreenshot() now exercises the Shizuku screencap path first.
    final path = await _svc.takeScreenshot();
    if (!mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('截图成功 (Shizuku 路径)：$path')));
      final cfg = await widget.storage.loadAppConfig();
      await widget.storage.saveAppConfig(cfg.copyWith(
          automation: cfg.automation.copyWith(screenshotGranted: true)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需先在手机上手动允许截图权限（首次调用会弹出系统级录屏确认）')));
    }
    await _refresh();
  }

  void _showShizukuGuide() {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('启用 Shizuku 步骤'),
              scrollable: true,
              content: const Text(
                '1. 在应用商店或官网下载安装 Shizuku App。\n'
                '2. 将手机通过 USB 连接电脑，开启「USB 调试」。\n'
                '3. 电脑端执行：\n'
                '   adb shell sh /sdcard/Android/data/moe.shizuku.privileged.api/start.sh\n'
                '4. 返回 Shizuku App，确认显示「服务已启动」。\n'
                '5. 回到本页，Shizuku 状态会自动变为「已开启」。\n\n'
                '如无电脑，可通过「无线调试」配对方式启用 Shizuku。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('知道了'),
                ),
              ],
            ));
  }
}
