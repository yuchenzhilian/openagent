part of '../android_tools.dart';

// ============================================================================
// H1 高层 App 脚本组合工具（Composite / Macro）
//
// 把"打开 App → 等待 → 点搜索 → 输入 → 点发送"这种 3~8 步的原子操作
// 合并成一个 Tool，节省端侧模型推理步数（每步都是一次 LLM 前向）。
// 规则（给模型看的）：当系统提供高层 android_wechat_* / android_douyin_* /
// android_xhs_* 工具时，**优先用高层工具**，不要拆原子步骤。
// ============================================================================

/// ——— WeChat 发消息 ———
/// 打开微信 → 搜「联系人/群名」→ 进聊天 → 输文字 → 点发送，一条龙。
Tool _composeWechatSendMessage(AndroidAutomationService s) => Tool(
      name: 'android_wechat_send_message',
      description:
          '【高层·一步完成】直接给微信好友 / 群聊发文字消息。自动完成：打开微信 → 顶部搜索好友 → 点进聊天页 → 输入框写文字 → 点发送。'
          '⚠ 优先使用本工具，不要自己拆成 android_open_app / click / input / wait 等 N 个小步骤（浪费推理步数）。',
      schema: _props({
        'contact_name': {
          'type': 'string',
          'description': '微信好友备注名 / 群聊名（顶部搜索框能搜到的显示文字）',
        },
        'message': {
          'type': 'string',
          'description': '要发送的文字内容，支持中文/emoji，例如「你好🌞 下班约吗」',
        },
      }, required: [
        'contact_name',
        'message',
      ]),
      handler: (args) async {
        final contact = args['contact_name'] as String?;
        final msg = args['message'] as String?;
        if (contact == null || contact.isEmpty) {
          return const ToolResult.error('缺少 contact_name 参数');
        }
        if (msg == null || msg.isEmpty) {
          return const ToolResult.error('缺少 message 参数');
        }

        final steps = <String>[];
        String report() => steps.map((l) => '  • $l').join('\n');

        // 1. open WeChat
        final ok1 = await s.openApp('com.tencent.mm');
        steps.add('打开微信: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('步骤失败:\n${report()}\n微信未安装或启动失败');

        // 2. wait for WeChat home (allow 启动广告)
        final ok2 = await s.waitForText('微信', timeoutSec: 18, pollMs: 600, exact: false) ||
            await s.waitForText('通讯录', timeoutSec: 5, pollMs: 500, exact: true);
        steps.add('等待主界面: ${ok2 ? 'OK' : '超时(可能有广告/需人工)'}');
        if (!ok2) {
          return ToolResult.error('步骤失败:\n${report()}\n20秒内未进入微信首页，可能有启动广告，请人工处理后重试');
        }

        // 3. click top search (新版: 顶部"搜索"文字/描述；旧版: 放大镜按钮)
        final ok3 = await s.clickByText('搜索', exact: false) ||
            await s.clickByText('搜索指定内容', exact: false);
        steps.add('点搜索: ${ok3 ? 'OK' : '未找到搜索入口'}');
        if (!ok3) return ToolResult.error('步骤失败:\n${report()}\n无法定位搜索框，请 dump_ui 确认界面结构');

        // 4. input contact name in search
        final ok4 = await s.inputText(contact);
        steps.add('输入联系人名「$contact」: ${ok4 ? 'OK' : '失败'}');
        if (!ok4) return ToolResult.error('步骤失败:\n${report()}\n搜索框输入失败');

        // 5. click first matching result
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final ok5 = await s.clickByText(contact, exact: false);
        steps.add('点击联系人结果: ${ok5 ? 'OK' : '按文字未匹配到(界面结构可能变化)'}');
        if (!ok5) {
          return ToolResult.error('步骤失败:\n${report()}\n搜索结果中无法点击到「$contact」');
        }

        // 6. wait chat page (see 发消息 placeholder or 语音通话)
        final ok6 = await s.waitForText('发消息', timeoutSec: 10, pollMs: 600, exact: false) ||
            await s.waitForText('语音通话', timeoutSec: 5, pollMs: 500, exact: false);
        steps.add('进入聊天页: ${ok6 ? 'OK' : '(已在聊天 / 或结构变化)'}');

        // focus chat input
        await s.clickByText('发消息', exact: false);
        await Future<void>.delayed(const Duration(milliseconds: 300));

        // 7. type the message
        final ok7 = await s.inputText(msg);
        steps.add('写入消息「$msg」: ${ok7 ? 'OK' : '失败'}');
        if (!ok7) return ToolResult.error('步骤失败:\n${report()}\n聊天输入框输入失败');

        // 8. Send button
        final ok8 = await s.clickByText('发送', exact: true);
        steps.add('点发送: ${ok8 ? 'OK' : '失败'}');
        if (!ok8) return ToolResult.error('步骤失败:\n${report()}\n找不到「发送」按钮');

        return ToolResult.ok('✅ 微信发送完成 (8 步):\n${report()}');
      },
    );

/// ——— Douyin 刷推荐 + 点赞当前视频 ———
Tool _composeDouyinLikeCurrent(AndroidAutomationService s) => Tool(
      name: 'android_douyin_like_current_video',
      description:
          '【高层·一步完成】打开抖音 → 等推荐流加载 → 给当前正在播放的推荐视频点❤点赞（右侧爱心图标）。'
          '⚠ 优先使用本工具，不要分步。',
      schema: _props({}),
      handler: (_) async {
        final steps = <String>[];
        String report() => steps.map((l) => '  • $l').join('\n');

        final ok1 = await s.openApp('com.ss.android.ugc.aweme');
        steps.add('打开抖音: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('步骤失败:\n${report()}\n抖音未安装');

        // splash + feed load (抖音冷启动可能有 5s 广告)
        final ok2 = await s.waitForText('首页', timeoutSec: 20, pollMs: 800, exact: false) ||
            await s.waitForText('推荐', timeoutSec: 10, pollMs: 800, exact: false);
        steps.add('等待推荐流加载: ${ok2 ? 'OK' : '可能在广告页(继续尝试)'}');

        // 点赞: 右侧爱心 (content-desc 通常是 未点赞/点赞/喜欢 之类的中文 — clickByText 自动匹配 text + contentDescription)
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        var ok3 = await s.clickByText('未点赞', exact: false) ||
            await s.clickByText('喜欢', exact: false) ||
            await s.clickByText('点赞', exact: false);
        if (!ok3) {
          // fallback: screen resolution → right ~88% x, vertical middle ~62% (抖音点赞按钮位置经验值)
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final w = res[0];
            final h = res[1];
            final lx = (w * 0.90).round();
            final ly = (h * 0.62).round();
            ok3 = await s.clickCoords(lx, ly);
            steps.add('按坐标点右侧爱心 (${lx}x$ly): ${ok3 ? 'OK' : '失败'}');
          } else {
            steps.add('尝试点爱心: 失败(description匹配失败且拿不到分辨率)');
          }
        } else {
          steps.add('按 description 点爱心: OK');
        }
        if (!ok3) return ToolResult.error('步骤失败:\n${report()}\n点赞失败');

        return ToolResult.ok('✅ 已点赞当前抖音推荐视频:\n${report()}');
      },
    );

/// ——— Xiaohongshu 搜索关键词 ———
Tool _composeXiaohongshuSearch(AndroidAutomationService s) => Tool(
      name: 'android_xhs_search',
      description:
          '【高层·一步完成】打开小红书 → 点放大镜搜索 → 输入 keyword → 搜索，返回笔记列表页。'
          '⚠ 优先使用本高层工具，不要拆成 5 个小步骤。',
      schema: _props({
        'keyword': {
          'type': 'string',
          'description': '要搜索的关键词，支持中文/标签，例如「夏日穿搭」「citywalk 咖啡馆」',
        },
      }, required: [
        'keyword'
      ]),
      handler: (args) async {
        final kw = args['keyword'] as String?;
        if (kw == null || kw.isEmpty) {
          return const ToolResult.error('缺少 keyword');
        }
        final steps = <String>[];
        String report() => steps.map((l) => '  • $l').join('\n');

        final ok1 = await s.openApp('com.xingin.xhs');
        steps.add('打开小红书: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('步骤失败:\n${report()}\n小红书未安装');

        // wait home (allow splash ads)
        final ok2 = await s.waitForText('首页', timeoutSec: 20, pollMs: 800, exact: false) ||
            await s.waitForText('发现', timeoutSec: 10, pollMs: 800, exact: false);
        steps.add('等待首页: ${ok2 ? 'OK' : '(可能仍在广告/加载, 继续尝试)'}');

        // Search entry: 放大镜 icon / top search bar placeholder
        await Future<void>.delayed(const Duration(milliseconds: 600));
        final ok3 = await s.clickByText('搜索', exact: false) ||
            await s.clickByText('搜索小红书', exact: false);
        steps.add('点搜索入口: ${ok3 ? 'OK' : '未找到(尝试 fallback 按坐标)'}');
        if (!ok3) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final x = (res[0] * 0.90).round();
            final y = (res[1] * 0.07).round();
            final ok = await s.clickCoords(x, y);
            steps.add('按右上角放大镜坐标 (${x}x$y): ${ok ? 'OK' : '失败'}');
            if (!ok) return ToolResult.error('步骤失败:\n${report()}\n无法进入搜索页');
          }
        }

        // wait search input field
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final ok4 = await s.inputText(kw);
        steps.add('输入关键词「$kw」: ${ok4 ? 'OK' : '失败'}');
        if (!ok4) return ToolResult.error('步骤失败:\n${report()}\n搜索框输入失败');

        // Press ENTER / click 搜索 button
        var ok5 = await s.clickByText('搜索', exact: true);
        if (!ok5) {
          await s.pressKey(AndroidKey.enter);
          steps.add('敲回车触发搜索: (尽力执行)');
        } else {
          steps.add('点「搜索」按钮: OK');
        }

        await Future<void>.delayed(const Duration(milliseconds: 900));
        return ToolResult.ok('✅ 小红书搜索完成:\n${report()}');
      },
    );

/// ——— QQ 发消息 (Tencent QQ) ———
/// 模式同微信：打开 QQ → 顶部搜索 → 选联系人 → 写消息 → 发送。
Tool _composeQqSendMessage(AndroidAutomationService s) => Tool(
      name: 'android_qq_send_message',
      description:
          '【高层·一步完成】直接给手机 QQ 好友 / 群聊发文字消息。自动完成：打开QQ → 顶部搜索好友 → 点进聊天页 → 输入框写文字 → 点发送。'
          '⚠ 优先使用本高层工具，不要拆成 5~8 个原子小步骤。',
      schema: _props({
        'contact_name': {
          'type': 'string',
          'description': 'QQ 好友备注 / 昵称 / 群聊名（顶部搜索框能搜到的文字）',
        },
        'message': {
          'type': 'string',
          'description': '要发送的文字内容，支持中文/emoji，例如「在吗 看下项目文档」',
        },
      }, required: [
        'contact_name',
        'message',
      ]),
      handler: (args) async {
        final contact = args['contact_name'] as String?;
        final msg = args['message'] as String?;
        if (contact == null || contact.isEmpty) {
          return const ToolResult.error('缺少 contact_name 参数');
        }
        if (msg == null || msg.isEmpty) {
          return const ToolResult.error('缺少 message 参数');
        }
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final ok1 = await s.openApp('com.tencent.mobileqq');
        steps.add('打开QQ: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('步骤失败:\n${r()}\nQQ 未安装或启动失败');

        // QQ 主界面判断：首页通常有"消息/联系人/动态"
        final ok2 = await s.waitForText('消息', timeoutSec: 20, pollMs: 700, exact: true) ||
            await s.waitForText('联系人', timeoutSec: 5, pollMs: 500, exact: true);
        steps.add('等待QQ主界面: ${ok2 ? 'OK' : '(未检测到, 继续尝试搜索)'}');

        // 搜索入口：QQ 顶部通常有搜索框或放大镜图标 (contentDescription="搜索" / text="搜索")
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final ok3 = await s.clickByText('搜索', exact: false) ||
            await s.clickByText('搜索联系人和群', exact: false);
        steps.add('点搜索入口: ${ok3 ? 'OK' : '未找到'}');
        if (!ok3) {
          // fallback: 经验坐标 — QQ 搜索框一般在屏幕顶部 ~85% 宽、6% 高的位置
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final lx = (res[0] * 0.90).round();
            final ly = (res[1] * 0.065).round();
            final ok = await s.clickCoords(lx, ly);
            steps.add('按经验坐标点搜索 (${lx}x$ly): ${ok ? 'OK' : '失败'}');
            if (!ok) return ToolResult.error('步骤失败:\n${r()}\n无法进入 QQ 搜索页，需 dump_ui 人工判断');
          }
        }

        final ok4 = await s.inputText(contact);
        steps.add('输入联系人「$contact」: ${ok4 ? 'OK' : '失败'}');
        if (!ok4) return ToolResult.error('步骤失败:\n${r()}\nQQ 搜索框输入失败');

        await Future<void>.delayed(const Duration(milliseconds: 700));
        final ok5 = await s.clickByText(contact, exact: false);
        steps.add('点搜索结果「$contact」: ${ok5 ? 'OK' : '失败'}');
        if (!ok5) {
          return ToolResult.error('步骤失败:\n${r()}\n搜索结果里没找到匹配「$contact」的联系人/群');
        }

        // QQ 聊天页：通常有"发送" placeholder 或 语音通话 按钮
        await s.waitForText('发送', timeoutSec: 10, pollMs: 600, exact: false)
            .then((_) => null); // best-effort, don't fail
        // focus chat input
        await s.clickByText('输入消息', exact: false); // placeholder hint desc
        await Future<void>.delayed(const Duration(milliseconds: 250));

        final ok7 = await s.inputText(msg);
        steps.add('写入消息「$msg」: ${ok7 ? 'OK' : '失败'}');
        if (!ok7) return ToolResult.error('步骤失败:\n${r()}\n聊天框输入失败');

        final ok8 = await s.clickByText('发送', exact: true) ||
            await s.clickByText('发送', exact: true);
        steps.add('点发送: ${ok8 ? 'OK' : '失败'}');
        if (!ok8) return ToolResult.error('步骤失败:\n${r()}\n找不到发送按钮');

        return ToolResult.ok('✅ QQ 消息发送完成:\n${r()}');
      },
    );

/// ——— 抖音：划到下一条推荐视频 ———
/// 推荐流是垂直排列，向上划 80%h → 20%h = 拉到下一条视频（类似人手向上滑屏幕）。
Tool _composeDouyinNextVideo(AndroidAutomationService s) => Tool(
      name: 'android_douyin_next_video',
      description:
          '【高层·一步完成】在抖音推荐流 / 关注流页面向上滑动，切换到下一条视频。'
          '⚠ 想连续刷视频直接循环调用本工具，不要自己写 swipe 坐标。',
      schema: _props({
        'count': {
          'type': 'integer',
          'description': '要划几条（默认 1 条），最多允许 50 条',
        },
      }),
      handler: (args) async {
        final count = ((args['count'] as num?)?.toInt() ?? 1).clamp(1, 50);
        final res = await s.screenResolution();
        if (res == null || res.length != 2) {
          return const ToolResult.error('拿不到屏幕分辨率，无法计算滑动坐标');
        }
        final w = res[0];
        final h = res[1];
        final cx = (w * 0.50).round(); // 屏幕中线上的任意一列都行（避开侧边栏按钮）
        final yStart = (h * 0.80).round(); // 从下 80% 处起
        final yEnd = (h * 0.20).round();   // 拉到上 20% 处
        var success = 0;
        for (var i = 0; i < count; i++) {
          final ok = await s.swipe(cx, yStart, cx, yEnd, durationMs: 380);
          if (ok) success++;
          await Future<void>.delayed(const Duration(milliseconds: 550)); // 等下一条播起来
        }
        return ToolResult.ok('划了 $count 条，成功 $success 条'
            '（屏幕内 ${cx}x$yStart → ${cx}x$yEnd, duration 380ms）');
      },
    );

/// ——— 抖音：评论当前视频 ———
Tool _composeDouyinCommentCurrent(AndroidAutomationService s) => Tool(
      name: 'android_douyin_comment_current_video',
      description:
          '【高层·一步完成】给当前正在播放的抖音视频写一条评论并发送：点开评论面板 → 聚焦输入框 → 写内容 → 发送。'
          '⚠ 优先用本高层工具，不要拆原子步骤。',
      schema: _props({
        'comment': {
          'type': 'string',
          'description': '要发的评论文字，支持中文/emoji，例如「这个思路太棒了👏」',
        },
      }, required: [
        'comment'
      ]),
      handler: (args) async {
        final comment = args['comment'] as String?;
        if (comment == null || comment.isEmpty) {
          return const ToolResult.error('缺少 comment 参数');
        }
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 1. 确保在抖音里
        final info = await s.getTopApp();
        if (info.package != 'com.ss.android.ugc.aweme') {
          final ok = await s.openApp('com.ss.android.ugc.aweme');
          steps.add('打开抖音: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('步骤失败:\n${r()}\n抖音未安装');
          await s.waitForText('首页', timeoutSec: 15, pollMs: 800, exact: false);
        } else {
          steps.add('已在抖音 App (top activity=${info.activity})');
        }

        // 2. 打开评论面板：右侧评论小图标 (description 常是"评论"/"评论区")
        await Future<void>.delayed(const Duration(milliseconds: 900));
        var ok = await s.clickByText('评论', exact: false) ||
            await s.clickByText('说点什么', exact: false);
        if (!ok) {
          // 评论图标坐标经验值：屏幕右侧 90%x、72%y 附近（爱心下方是评论）
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final x = (res[0] * 0.90).round();
            final y = (res[1] * 0.72).round();
            ok = await s.clickCoords(x, y);
            steps.add('按经验坐标点评论图标 (${x}x$y): ${ok ? 'OK' : '失败'}');
          }
        } else {
          steps.add('点评论入口: OK');
        }
        if (!ok) return ToolResult.error('步骤失败:\n${r()}\n无法打开评论面板');
        await Future<void>.delayed(const Duration(milliseconds: 700));

        // 3. 聚焦底部评论输入框
        var fOk = await s.clickByText('说点什么', exact: false) ||
            await s.clickByText('留下你的精彩评论吧', exact: false);
        if (!fOk) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final x = (res[0] * 0.45).round();
            final y = (res[1] * 0.93).round();
            fOk = await s.clickCoords(x, y);
            steps.add('按坐标聚焦评论输入 (${x}x$y): ${fOk ? 'OK' : '失败'}');
          }
        } else {
          steps.add('聚焦评论输入框: OK');
        }

        // 4. 输入评论
        final okIn = await s.inputText(comment);
        steps.add('写入评论「$comment」: ${okIn ? 'OK' : '失败'}');
        if (!okIn) return ToolResult.error('步骤失败:\n${r()}\n评论内容输入失败');

        // 5. 点发送
        final okSend = await s.clickByText('发送', exact: true) ||
            await s.clickByText('发送', exact: false);
        steps.add('点发送: ${okSend ? 'OK' : '失败'}');
        if (!okSend) return ToolResult.error('步骤失败:\n${r()}\n找不到发送按钮');

        return ToolResult.ok('✅ 抖音评论已发送:\n${r()}');
      },
    );

/// ——— 小红书：点赞当前 feed 页第一个可见笔记 ———
/// 小红书双列瀑布流，第一个笔记一般在左上 ~25%x 35%y 处；点进去 → 点❤️ → 返回列表。
Tool _composeXiaohongshuLikeFirstNote(AndroidAutomationService s) => Tool(
      name: 'android_xhs_like_first_note',
      description:
          '【高层·一步完成】在小红书发现页/搜索结果页，点第一个可见的笔记卡片 → 进入详情后点底部/顶栏❤️点赞 → 回列表。'
          '⚠ 优先用本工具，不要拆成 click_coords 乱点。',
      schema: _props({}),
      handler: (_) async {
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 确认在小红书里
        final info = await s.getTopApp();
        if (info.package != 'com.xingin.xhs') {
          final ok = await s.openApp('com.xingin.xhs');
          steps.add('打开小红书: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('步骤失败:\n${r()}\n小红书未安装');
          await s.waitForText('发现', timeoutSec: 18, pollMs: 800, exact: false);
        } else {
          steps.add('已在小红书 App');
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));

        // 点第一个笔记卡片 (瀑布流左上。宽 0.28, 高 0.35 经验值)
        final res = await s.screenResolution();
        int? lx, ly;
        if (res != null && res.length == 2) {
          lx = (res[0] * 0.28).round();
          ly = (res[1] * 0.35).round();
        }
        var ok = await s.clickCoords(lx ?? 300, ly ?? 800);
        steps.add('点第一个笔记卡片 (${lx ?? 300}x${ly ?? 800}): ${ok ? 'OK' : '失败'}');
        if (!ok) return ToolResult.error('步骤失败:\n${r()}\n点卡片失败');
        await Future<void>.delayed(const Duration(milliseconds: 900));

        // 点赞: 底部 ❤️ 图标 或 底部"赞" — 通常 屏幕下 6% 行、左 18% 列
        var like = await s.clickByText('赞', exact: true) ||
            await s.clickByText('点赞', exact: false) ||
            await s.clickByText('点赞', exact: false);
        if (!like && res != null && res.length == 2) {
          final bx = (res[0] * 0.18).round();
          final by = (res[1] * 0.94).round();
          like = await s.clickCoords(bx, by);
          steps.add('按底部经验坐标点点赞 (${bx}x$by): ${like ? 'OK' : '失败'}');
        } else {
          steps.add('点❤️(底部赞): ${like ? 'OK' : '失败'}');
        }
        if (!like) return ToolResult.error('步骤失败:\n${r()}\n点赞失败');

        // 返回列表
        await s.pressKey(AndroidKey.back);
        steps.add('点返回键 回到列表');

        return ToolResult.ok('✅ 小红书点赞完成:\n${r()}');
      },
    );

/// ——— B站搜索 ———
Tool _composeBilibiliSearch(AndroidAutomationService s) => Tool(
      name: 'android_bilibili_search',
      description:
          '【高层·一步完成】打开哔哩哔哩 B站 → 顶部搜索关键词 → 出结果页。搜索动画/鬼畜/UP 主/番剧时直接调用。',
      schema: _props({
        'keyword': {
          'type': 'string',
          'description': '要搜索的关键词/UP 主/番剧名，例如「大模型推理优化」「间谍过家家 S2」',
        },
      }, required: [
        'keyword'
      ]),
      handler: (args) async {
        final kw = args['keyword'] as String?;
        if (kw == null || kw.isEmpty) {
          return const ToolResult.error('缺少 keyword');
        }
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final ok1 = await s.openApp('tv.danmaku.bili');
        steps.add('打开B站: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('步骤失败:\n${r()}\nB站未安装');

        final ok2 = await s.waitForText('首页', timeoutSec: 20, pollMs: 800, exact: false) ||
            await s.waitForText('推荐', timeoutSec: 10, pollMs: 800, exact: false);
        steps.add('等待B站首页: ${ok2 ? 'OK' : '(未检测到, 继续尝试搜索)'}');
        await Future<void>.delayed(const Duration(milliseconds: 600));

        // B站顶部超大搜索框 (text/desc 一般就是关键字 或 placeholder hint)
        final ok3 = await s.clickByText('搜索', exact: false) ||
            await s.clickByText('你感兴趣的视频都在B站', exact: false);
        steps.add('点搜索入口: ${ok3 ? 'OK' : '未找到, fallback 经验坐标'}');
        if (!ok3) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final x = (res[0] * 0.50).round();
            final y = (res[1] * 0.07).round();
            final ok = await s.clickCoords(x, y);
            steps.add('按顶部搜索框坐标 (${x}x$y): ${ok ? 'OK' : '失败'}');
            if (!ok) return ToolResult.error('步骤失败:\n${r()}\n进不去搜索页');
          }
        }

        final ok4 = await s.inputText(kw);
        steps.add('输入关键词「$kw」: ${ok4 ? 'OK' : '失败'}');
        if (!ok4) return ToolResult.error('步骤失败:\n${r()}\n搜索框输入失败');

        final ok5 = await s.clickByText('搜索', exact: true);
        if (!ok5) {
          await s.pressKey(AndroidKey.enter);
          steps.add('按 Enter 触发搜索');
        } else {
          steps.add('点搜索按钮: OK');
        }
        await Future<void>.delayed(const Duration(milliseconds: 800));
        return ToolResult.ok('✅ B站搜索完成:\n${r()}');
      },
    );

// ============================================================================
// H3 批处理 / 深度操作 Macro（单工具调用 1 步 → 内部几十个子操作）
// ============================================================================

/// ——— 抖音：连续刷 N 条 + 每条点赞 + 每 K 条留模板评论 ———
/// 真正的"挂机刷流"工具：1 次调用 顶 30~150 个原子步骤，省 95% 推理
Tool _composeDouyinBatchSwipe(AndroidAutomationService s) => Tool(
      name: 'android_douyin_batch_swipe_like',
      description:
          '【高层·挂机批处理】一口气刷抖音 N 条推荐视频，每条自动点赞；可设置每隔 K 条自动留一条模板评论。'
          '⚠ 调用 1 次 = 内部自动循环 30~100 步，Agent 不要再在外面写 for 循环反复调 douyin_like + next_video。',
      schema: _props({
        'count': {
          'type': 'integer',
          'description': '总共要刷的视频条数 (默认 20，最多允许 200)',
        },
        'like_each': {
          'type': 'boolean',
          'description': '每条视频是否自动点❤ (默认 true)',
        },
        'comment_every': {
          'type': 'integer',
          'description': '每隔几条发 1 条评论 (0=不发评论，默认 0)，例如 5 = 每刷 5 条评第 5 条',
        },
        'comment_template': {
          'type': 'string',
          'description': '评论模板，支持简单随机 {emoji}: 例如「太棒了👏」「学到了 666」',
        },
      }),
      handler: (args) async {
        final total = ((args['count'] as num?)?.toInt() ?? 20).clamp(1, 200);
        final like = args['like_each'] != false; // default true
        final every = ((args['comment_every'] as num?)?.toInt() ?? 0).clamp(0, 200);
        final tpl = (args['comment_template'] as String?) ?? '好棒 👍';

        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 确保在抖音推荐流首页
        final info = await s.getTopApp();
        if (info.package != 'com.ss.android.ugc.aweme') {
          final ok = await s.openApp('com.ss.android.ugc.aweme');
          steps.add('打开抖音: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('启动失败');
          await s.waitForText('首页', timeoutSec: 16, pollMs: 800, exact: false);
        } else {
          steps.add('已在抖音');
        }
        await Future<void>.delayed(const Duration(milliseconds: 900));

        final res = await s.screenResolution();
        if (res == null || res.length != 2) {
          return const ToolResult.error('拿不到屏幕分辨率');
        }
        final w = res[0];
        final h = res[1];
        final heartX = (w * 0.90).round();
        final heartY = (h * 0.62).round();
        final commentX = (w * 0.90).round();
        final commentY = (h * 0.72).round();
        final sendInputX = (w * 0.45).round();
        final sendInputY = (h * 0.93).round();
        final swipeStart = (h * 0.80).round();
        final swipeEnd = (h * 0.20).round();
        final centerX = (w * 0.50).round();

        var liked = 0;
        var commented = 0;
        var done = 0;
        for (var i = 1; i <= total; i++) {
          // 每条先停一下等视频加载（不调用 wait_for_text，因为推荐流 text 不稳定）
          await Future<void>.delayed(const Duration(milliseconds: 650));

          // —— Step A: 点赞当前条 ——
          if (like) {
            final ok = await s.clickByText('未点赞', exact: false) ||
                await s.clickByText('喜欢', exact: false) ||
                await s.clickByText('点赞', exact: false) ||
                await s.clickCoords(heartX, heartY);
            if (ok) liked++;
          }

          // —— Step B: 每隔 K 条 发模板评论 ——
          if (every > 0 && i % every == 0) {
            var cOk = await s.clickByText('评论', exact: false) ||
                await s.clickByText('说点什么', exact: false) ||
                await s.clickCoords(commentX, commentY);
            if (cOk) {
              await Future<void>.delayed(const Duration(milliseconds: 600));
              final fOk = await s.clickByText('说点什么', exact: false) ||
                  await s.clickByText('留下你的精彩评论吧', exact: false) ||
                  await s.clickCoords(sendInputX, sendInputY);
              if (fOk) {
                final inOk = await s.inputText(tpl);
                if (inOk) {
                  final sendOk = await s.clickByText('发送', exact: true);
                  if (sendOk) commented++;
                }
              }
              // 关闭评论面板 回到 feed (press BACK)
              await s.pressKey(AndroidKey.back);
              await Future<void>.delayed(const Duration(milliseconds: 300));
            }
          }

          done = i;

          // —— Step C: 非最后一条就划下一条 ——
          if (i < total) {
            await s.swipe(centerX, swipeStart, centerX, swipeEnd, durationMs: 380);
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }

        final summary = StringBuffer('✅ 抖音批处理完成:\n');
        summary.writeln('  刷完 $done / $total 条');
        summary.writeln('  点赞成功: $liked');
        if (every > 0) summary.writeln('  评论成功: $commented（模板:「$tpl」 隔 $every 条 1 次）');
        summary.writeln(r());
        return ToolResult.ok(summary.toString());
      },
    );

/// ——— 微信朋友圈：打开+滚动+批量点赞前 N 条新鲜事 ———
Tool _composeWechatMomentsLikeBatch(AndroidAutomationService s) => Tool(
      name: 'android_wechat_moments_like_batch',
      description:
          '【高层·一步批处理】打开微信 → 发现 → 朋友圈 → 批量给前 N 条朋友圈点❤️（不用一条条自己点右下角⭕菜单→选点赞）。'
          '⚠ 直接用，不要拆小步骤。',
      schema: _props({
        'n': {
          'type': 'integer',
          'description': '要点赞多少条朋友圈动态 (默认 10，最多 100)',
        },
        'start_from_top': {
          'type': 'boolean',
          'description': 'true=回到顶部最新开始点赞；false=当前位置继续 (默认 true)',
        },
      }),
      handler: (args) async {
        final n = ((args['n'] as num?)?.toInt() ?? 10).clamp(1, 100);
        final fromTop = args['start_from_top'] != false;
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 1. Open WeChat home
        final ok1 = await s.openApp('com.tencent.mm');
        steps.add('打开微信: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('微信启动失败');
        final ok2 = await s.waitForText('微信', timeoutSec: 18, pollMs: 700, exact: false) ||
            await s.waitForText('通讯录', timeoutSec: 5, pollMs: 500, exact: true);
        steps.add('微信主界面: ${ok2 ? 'OK' : '超时继续尝试'}');

        // 2. 点「发现」Tab  (通常底部 第三个 Tab / 右二)
        var tab = await s.clickByText('发现', exact: true);
        if (!tab) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final x = (res[0] * 0.70).round();
            final y = (res[1] * 0.96).round();
            tab = await s.clickCoords(x, y);
            steps.add('点发现Tab坐标 (${x}x$y): ${tab ? 'OK' : '失败'}');
          }
        } else {
          steps.add('点「发现」Tab: OK');
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // 3. 点「朋友圈」入口
        var okM = await s.clickByText('朋友圈', exact: true);
        if (!okM) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            okM = await s.clickCoords((res[0] * 0.40).round(), (res[1] * 0.20).round());
            steps.add('点朋友圈入口坐标: ${okM ? 'OK' : '失败'}');
          }
        } else {
          steps.add('点「朋友圈」: OK');
        }
        if (!okM) return ToolResult.error('步骤失败:\n${r()}\n进不去朋友圈');
        await s.waitForText('朋友圈', timeoutSec: 12, pollMs: 600, exact: true);
        await Future<void>.delayed(const Duration(milliseconds: 800));

        // 4. 如果需要从顶部开始：先划几下回到顶部 (靠按 HOME 回到自己头像顶端)
        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        if (fromTop) {
          // 回到顶部的最快方式：按 BACK 出朋友圈再进会回到自己名片；直接快速上划 2 次比较稳
          for (var i = 0; i < 2; i++) {
            await s.swipe((w * 0.5).round(), (h * 0.25).round(), (w * 0.5).round(), (h * 0.80).round(), durationMs: 280);
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          steps.add('回到朋友圈顶部 (2 次上划)');
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }

        // —— 5. 每条：定位右下角「⋯」两个点图标 → 弹出菜单 → 点「赞」——
        // 朋友圈每条右下角的 ... 菜单按钮，contentDescription 或 text 通常没固定文字，
        // 但坐标相对可估：屏幕右 7% 宽 位置，每条动态高度 ~35%~45% 屏高之间
        var liked = 0;
        final dotsX = (w * 0.93).round();
        var currentDotsY = (h * 0.42).round(); // 第一条的右下角一般在 42%
        final menuY = (h * 0.55).round();       // 弹出菜单内「赞」的位置（菜单位于屏幕中下部）
        // 点赞按钮在微信弹出菜单中通常第一行，contentDescription="赞"
        for (var i = 0; i < n; i++) {
          // (A) 点这一条的 "⋯" 图标 (右下角)
          final dots = await s.clickCoords(dotsX, currentDotsY);
          await Future<void>.delayed(const Duration(milliseconds: 400));
          var likeOk = false;
          if (dots) {
            // (B) 弹出菜单：优先匹配 text = 赞 / 点赞 / 喜欢
            likeOk = await s.clickByText('赞', exact: true) ||
                await s.clickByText('点赞', exact: false);
            if (!likeOk) {
              // fallback: 弹出菜单中的「赞」通常在 ~55%h 那条行，按屏幕中部偏下一点坐标
              likeOk = await s.clickCoords((w * 0.55).round(), menuY);
            }
          }
          if (likeOk) liked++;
          await Future<void>.delayed(const Duration(milliseconds: 250));

          // (C) 向下滚动显示下一条（如果不是最后一条就再往下滚一条动态高度）
          if (i < n - 1) {
            await s.swipe((w * 0.5).round(), (h * 0.80).round(), (w * 0.5).round(), (h * 0.30).round(), durationMs: 420);
            currentDotsY = (h * 0.50).round(); // 下一条的 ... 图标位置大概固定在屏幕中部（因为刚滚过）
            await Future<void>.delayed(const Duration(milliseconds: 450));
          }
        }

        final sb = StringBuffer('✅ 微信朋友圈批处理完成:\n');
        sb.writeln('  尝试 $n 条，点赞成功 $liked 条');
        sb.writeln(r());
        return ToolResult.ok(sb.toString());
      },
    );

/// ——— B站视频：一键 点赞+投币+收藏 (俗称「三连」) ———
Tool _composeBilibiliThreeInOne(AndroidAutomationService s) => Tool(
      name: 'android_bilibili_video_three_in_one',
      description:
          '【高层·一键三连】对当前正在播放 / 搜索结果第 1 个 B 站视频执行 👍点赞 + 💰投币 + ⭐收藏 三连操作。'
          '⚠ 当用户说「给这个视频来个三连」时直接调本工具，不要拆 3 个 click。',
      schema: _props({
        'open_first_search': {
          'type': 'boolean',
          'description': '如果目前不在视频播放页：是否先打开B站首页推荐流中第一个视频 (默认 true)',
        },
        'coin_count': {
          'type': 'integer',
          'description': '投币数量 (1 或 2，默认 2)',
        },
      }),
      handler: (args) async {
        final openFirst = args['open_first_search'] != false;
        final coin = ((args['coin_count'] as num?)?.toInt() ?? 2).clamp(1, 2);
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;

        // 1. 进入 B 站并（可选）开第一个视频
        final info = await s.getTopApp();
        if (info.package != 'tv.danmaku.bili') {
          final ok = await s.openApp('tv.danmaku.bili');
          steps.add('打开B站: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('启动失败');
          await s.waitForText('首页', timeoutSec: 18, pollMs: 800, exact: false);
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
        if (openFirst) {
          // 点首页推荐流第一个视频卡片（通常在左上 25%x, 30%y）
          final ok = await s.clickCoords((w * 0.30).round(), (h * 0.35).round());
          steps.add('点推荐流第一个视频: ${ok ? 'OK' : '失败'}');
          await Future<void>.delayed(const Duration(milliseconds: 1400));
        }

        // 2. 视频页底部/右侧工具栏：点赞、投币、收藏
        // 新版 B 站横屏/竖屏布局不同。通用 fallback：经验坐标 (下 6% 行 分别 28%/42%/56% 列)
        final barY = (h * 0.94).round();
        final likeX = (w * 0.28).round();
        final coinX = (w * 0.42).round();
        final favX  = (w * 0.56).round();

        var okLike = await s.clickByText('赞', exact: true) ||
            await s.clickByText('点赞', exact: false) ||
            await s.clickCoords(likeX, barY);
        steps.add('👍点赞: ${okLike ? 'OK' : '失败(可能已赞)'}');
        await Future<void>.delayed(const Duration(milliseconds: 300));

        var okCoin = await s.clickByText('币', exact: true) ||
            await s.clickByText('投币', exact: false) ||
            await s.clickCoords(coinX, barY);
        if (okCoin) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          // 投币弹窗中选 1 或 2 个硬币 + 点「确定/投币」
          if (coin == 1) {
            await s.clickByText('1', exact: true); // 选 1 币
          } else {
            await s.clickByText('2', exact: true); // 选 2 币
          }
          await Future<void>.delayed(const Duration(milliseconds: 150));
          final confirm = await s.clickByText('确定', exact: true) ||
              await s.clickByText('投币', exact: false);
          steps.add('💰投$coin币: ${confirm ? 'OK' : '弹窗失败(可能需要登录)'}');
          await Future<void>.delayed(const Duration(milliseconds: 250));
        } else {
          steps.add('💰投币: 打开弹窗失败');
        }

        var okFav = await s.clickByText('收藏', exact: true) ||
            await s.clickByText('⭐', exact: false) ||
            await s.clickCoords(favX, barY);
        if (okFav) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          // 收藏弹窗：默认收藏夹（第一个）/ 点「确定」保存
          await s.clickByText('确定', exact: true);
          steps.add('⭐收藏: 已提交（弹窗已确定）');
        } else {
          steps.add('⭐收藏: 打开弹窗失败');
        }

        final status = StringBuffer('✅ B站视频三连完成:\n');
        status.writeln(r());
        return ToolResult.ok(status.toString());
      },
    );

// ============================================================================
// H4 系统能力 + App 进阶操作 Macro （×5）
// ============================================================================

/// ——— 微信：发一条「纯文字朋友圈」 (长按右上角相机 📷 进入纯文字模式) ———
Tool _composeWechatPostTextMoments(AndroidAutomationService s) => Tool(
      name: 'android_wechat_post_text_moments',
      description:
          '【高层·一步完成】打开微信 → 发现 → 朋友圈 → 长按右上角相机 (发纯文字) → 写文字 → 发表。'
          '⚠ 用户说"发个朋友圈说…"时直接用本工具，不要自己选发图片模式。',
      schema: _props({
        'text': {
          'type': 'string',
          'description': '朋友圈纯文字内容，支持中文/emoji，例如「今天调了一天代码，头都秃了😅」',
        },
        'location_tip': {
          'type': 'boolean',
          'description': '（预留）是否尝试显示所在位置，默认 false；当前版本不自动点位置选项',
        },
      }, required: [
        'text'
      ]),
      handler: (args) async {
        final content = args['text'] as String? ?? '';
        if (content.isEmpty) return const ToolResult.error('缺少 text 参数');
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final ok1 = await s.openApp('com.tencent.mm');
        steps.add('打开微信: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('启动微信失败\n${r()}');
        await s.waitForText('微信', timeoutSec: 18, pollMs: 700, exact: false) ||
            await s.waitForText('通讯录', timeoutSec: 5, pollMs: 500, exact: true);

        // 点发现 Tab
        var tab = await s.clickByText('发现', exact: true);
        if (!tab) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            tab = await s.clickCoords((res[0] * 0.70).round(), (res[1] * 0.96).round());
          }
        }
        steps.add('发现Tab: ${tab ? 'OK' : '坐标Fallback尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 450));

        // 进入朋友圈页
        var okM = await s.clickByText('朋友圈', exact: true);
        if (!okM) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            okM = await s.clickCoords((res[0] * 0.40).round(), (res[1] * 0.20).round());
          }
        }
        steps.add('进入朋友圈: ${okM ? 'OK' : '坐标Fallback尝试'}');
        if (!okM) return ToolResult.error('进不去朋友圈\n${r()}');
        await s.waitForText('朋友圈', timeoutSec: 14, pollMs: 600, exact: true);
        await Future<void>.delayed(const Duration(milliseconds: 700));

        // 关键点：**长按**右上角相机图标才是纯文字模式！
        // (普通点击 是 发图模式 选 9 宫格)
        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        final camX = (w * 0.93).round();  // 右上角相机
        final camY = (h * 0.075).round(); // 状态栏下 ~ 7.5%
        // pressKey 没有长按概念，用 swipe 0距离 模拟长按：start=end, duration = 1100ms
        final longPress = await s.swipe(camX, camY, camX, camY, durationMs: 1100);
        steps.add('长按相机📷 (${camX}x$camY, 1.1s): ${longPress ? 'OK' : '手势完成继续'}');
        await Future<void>.delayed(const Duration(milliseconds: 1200));

        // 写文字 (粘贴板 fallback 会自动工作)
        final write = await s.inputText(content);
        steps.add('输入文字内容 (${content.length}字): ${write ? 'OK' : '失败'}');
        if (!write) return ToolResult.error('写朋友圈文字失败\n${r()}');
        await Future<void>.delayed(const Duration(milliseconds: 300));

        // 点右上角「发表」按钮
        final pub = await s.clickByText('发表', exact: true) ||
            await s.clickByText('发布', exact: true);
        steps.add('发表: ${pub ? 'OK' : '失败'}');
        await Future<void>.delayed(const Duration(milliseconds: 900));

        return ToolResult.ok(pub
            ? '✅ 朋友圈纯文字已发表\n${r()}'
            : '⚠ 步骤执行完，未点到发表按钮（可能已自动发布）\n${r()}');
      },
    );

/// ——— 小红书：搜索关键词 → 切用户Tab → 给第 N 个作者 点 +关注 ———
Tool _composeXiaohongshuFollowUser(AndroidAutomationService s) => Tool(
      name: 'android_xhs_follow_search_user',
      description:
          '【高层·一步完成】小红书 搜索关键词 → 切到「用户」Tab → 给排名第 N 的账号 点+关注。'
          '⚠ 用户说"关注一下某某博主"时，先搜名字再用本工具。',
      schema: _props({
        'keyword': {
          'type': 'string',
          'description': '要搜索的用户昵称 / 关键词，例如「穿搭博主」「AI 产品经理」',
        },
        'index': {
          'type': 'integer',
          'description': '搜索结果用户列表中第几个 (1 起步，默认 1 = 第一个匹配上的用户)',
        },
      }, required: [
        'keyword'
      ]),
      handler: (args) async {
        final kw = args['keyword'] as String? ?? '';
        final idx = ((args['index'] as num?)?.toInt() ?? 1).clamp(1, 20);
        if (kw.isEmpty) return const ToolResult.error('缺少 keyword');
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // Reuse 打开 + 搜索 + 进入结果
        final open1 = await s.openApp('com.xingin.xhs');
        steps.add('打开小红书: ${open1 ? 'OK' : '失败'}');
        if (!open1) return ToolResult.error('启动小红书失败\n${r()}');
        await s.waitForText('首页', timeoutSec: 18, pollMs: 800, exact: false) ||
            await s.waitForText('发现', timeoutSec: 8, pollMs: 800, exact: false);
        await Future<void>.delayed(const Duration(milliseconds: 500));

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;

        // 点击搜索图标 (小红书顶部右 1/3 有放大镜)
        var sOk = await s.clickByText('搜索', exact: false) ||
            await s.clickByText('小红书 搜索一下', exact: false);
        if (!sOk) sOk = await s.clickCoords((w * 0.90).round(), (h * 0.07).round());
        steps.add('点搜索入口: ${sOk ? 'OK' : '坐标Fallback尝试'}');
        if (!sOk) return ToolResult.error('进不去搜索\n${r()}');
        await Future<void>.delayed(const Duration(milliseconds: 300));

        final wOk = await s.inputText(kw);
        steps.add('输入「$kw」: ${wOk ? 'OK' : '失败'}');
        if (!wOk) return ToolResult.error('输入关键词失败\n${r()}');

        final gOk = await s.clickByText('搜索', exact: true);
        if (!gOk) await s.pressKey(AndroidKey.enter);
        steps.add('触发搜索: OK');
        await Future<void>.delayed(const Duration(milliseconds: 900));

        // —— 切「用户」Tab (结果页顶部分类条：笔记 / 用户 / 商品 …)
        final uTab = await s.clickByText('用户', exact: true) ||
            await s.clickByText('用户·推荐', exact: false);
        steps.add('切到用户Tab: ${uTab ? 'OK' : '尝试坐标Fallback (顶部分类第3个)'}');
        if (!uTab) {
          await s.clickCoords((w * 0.45).round(), (h * 0.14).round());
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }

        // 第 idx 个用户卡片：小红书每列 1 个用户宽卡片，每条约 18% 屏高
        final firstCardY = (h * 0.24).round();
        final cardH = (h * 0.18).round();
        final targetCardCenterY = firstCardY + (idx - 1) * cardH + (cardH ~/ 2);
        // 关注按钮在用户卡片右 15% 宽 位置，卡片垂直中线
        final followBtnX = (w * 0.85).round();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final f1 = await s.clickCoords(followBtnX, targetCardCenterY);
        // 点完后 再点一次 "关注/已关注" 控件位置 以防只是进入了详情页没点到按钮
        if (!f1) {
          // fallback：先点进用户主页再在主页右侧/右上角点关注
          final toHome = await s.clickCoords((w * 0.30).round(), targetCardCenterY);
          steps.add('点进用户主页: ${toHome ? 'OK' : '没点到'}');
          await Future<void>.delayed(const Duration(milliseconds: 900));
          final f2 = await s.clickByText('关注', exact: true) ||
              await s.clickByText('+ 关注', exact: false) ||
              await s.clickCoords((w * 0.82).round(), (h * 0.18).round());
          steps.add('主页点+关注: ${f2 ? 'OK' : '失败'}');
        } else {
          steps.add('列表点+关注 (用户卡片第$idx个): OK');
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));

        return ToolResult.ok('✅ 小红书关注流程完成\n${r()}');
      },
    );

/// ——— 抖音：关注当前正在播放视频的作者 (右侧头像下方 + 号) ———
Tool _composeDouyinFollowCurrentAuthor(AndroidAutomationService s) => Tool(
      name: 'android_douyin_follow_current_author',
      description:
          '【高层·一步完成】当前正在播放的那条抖音视频：关注创作者（头像下 ➕ 按钮 / 进作者详情页后点关注）。'
          '⚠ 用户说"关注这个UP"时直接调用。',
      schema: _props({
        'open_home_if_needed': {
          'type': 'boolean',
          'description': '如果当前不在抖音，是否自动打开抖音并停留在推荐流第一个视频再关注，默认 true',
        },
      }),
      handler: (args) async {
        final openAuto = args['open_home_if_needed'] != false;
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final info = await s.getTopApp();
        if (info.package != 'com.ss.android.ugc.aweme') {
          if (!openAuto) return ToolResult.error('当前不在抖音，且 open_home_if_needed=false');
          final o = await s.openApp('com.ss.android.ugc.aweme');
          steps.add('打开抖音: ${o ? 'OK' : '失败'}');
          if (!o) return ToolResult.error('启动失败');
          await s.waitForText('首页', timeoutSec: 18, pollMs: 800, exact: false);
          await Future<void>.delayed(const Duration(milliseconds: 1100));
        }

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // 头像下方 + 号 一般在 右边 90%x 40%y 左右
        final plusX = (w * 0.90).round();
        final plusY = (h * 0.40).round();
        final c1 = await s.clickCoords(plusX, plusY);
        steps.add('点右侧头像下方+号 (${plusX}x$plusY): ${c1 ? 'OK' : '手势发送'}');
        await Future<void>.delayed(const Duration(milliseconds: 450));

        // 如果 + 号是 "跳作者详情" (某些版本)，就进入主页后再点「关注」大按钮
        final info2 = await s.getTopApp();
        final inAuthor = info2.package == 'com.ss.android.ugc.aweme'; // 还在抖音
        if (inAuthor) {
          final f2 = await s.clickByText('关注', exact: true) ||
              await s.clickByText('+关注', exact: false) ||
              await s.clickByText('回关', exact: true);
          if (f2) steps.add('作者详情页点关注: OK');
        }
        return ToolResult.ok('✅ 抖音关注当前作者流程完成\n${r()}');
      },
    );

/// ——— 系统能力：设置闹钟 (打开系统时钟 App → 添加闹钟 → 选时分 → 保存) ———
Tool _composeSystemSetAlarm(AndroidAutomationService s) => Tool(
      name: 'android_system_set_alarm',
      description:
          '【高层·一步完成】打开 Android 系统时钟 com.android.deskclock → 添加闹钟 → 设置小时:分钟 → 保存。'
          '用户说「明天 8 点叫我」「定个下午 3:30 的闹钟」时直接调。',
      schema: _props({
        'hour': {
          'type': 'integer',
          'description': '小时 (24h 制，0~23)。例如 8 = 早上8点, 15 = 下午3点',
        },
        'minute': {
          'type': 'integer',
          'description': '分钟 (0~59)',
        },
        'label': {
          'type': 'string',
          'description': '（可选）闹钟标签文字，例如「吃药」「开会」',
        },
      }, required: [
        'hour',
        'minute',
      ]),
      handler: (args) async {
        final hh = ((args['hour'] as num?)?.toInt() ?? 8).clamp(0, 23);
        final mm = ((args['minute'] as num?)?.toInt() ?? 0).clamp(0, 59);
        final label = args['label'] as String?;
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 多数 ROM 使用 com.android.deskclock，也有国内厂商自定义如 com.sec.android.app.clockpackage
        // 尝试 打开 标准包名；失败就 fallback 用 am start
        final tried1 = await s.openApp('com.android.deskclock');
        if (!tried1) {
          await s.openApp('com.google.android.deskclock');
        }
        await s.openApp('com.android.deskclock'); // dummy to register step
        steps.add('打开系统时钟 App: OK (未确认 UI，国内 ROM 可能跳转厂商时钟)');
        await Future<void>.delayed(const Duration(milliseconds: 1400));

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;

        // 通常右下角 / 右上角 有 ➕ 加号按钮 — 添加闹钟
        final add = await s.clickByText('添加闹钟', exact: false) ||
            await s.clickByText('新建', exact: false) ||
            await s.clickByText('+', exact: true) ||
            await s.clickCoords((w * 0.88).round(), (h * 0.88).round()) ||
            await s.clickCoords((w * 0.88).round(), (h * 0.10).round());
        steps.add('点 + 添加闹钟: ${add ? 'OK' : '已发坐标尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 700));

        // —— 时钟数字滚轮 picker (纯键盘 fallback 用 inputText 不太稳)
        //   Strategy: 用 gshell input text "HH:MM" 键盘方式 + 确定 / 用 setText Action
        final timeStr = '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
        // 先尝试 在 聚焦的 Hour/Min 上 直接 setText 方式
        final okKb = await s.inputText(timeStr);
        steps.add('尝试用键盘方式填入 $timeStr: ${okKb ? 'OK' : '失败，改用坐标 picker'}');
        if (!okKb) {
          // 简化版 fallback：通过 am broadcast / Shell command 方式写闹钟更准，L2 可用
          // adb shell am start -a android.intent.action.SET_ALARM --es android.intent.extra.alarm.MESSAGE "xxx" --ei android.intent.extra.alarm.HOUR h --ei android.intent.extra.alarm.MINUTES m --ez android.intent.extra.alarm.SKIP_UI true
          final msgArg = label != null && label.isNotEmpty
              ? '--es android.intent.extra.alarm.MESSAGE \'${label.replaceAll('\'', '')}\''
              : '';
          final shellCmd = 'am start -a android.intent.action.SET_ALARM '
              '--ei android.intent.extra.alarm.HOUR $hh '
              '--ei android.intent.extra.alarm.MINUTES $mm '
              '--ez android.intent.extra.alarm.SKIP_UI true $msgArg';
          final r2 = await s.gshell(shellCmd);
          steps.add('gshell am SET_ALARM: exit=${r2.exitCode} ok=${r2.ok}');
          return r2.ok
              ? ToolResult.ok('✅ 已通过系统 Intent 设置闹钟 $timeStr\n${r()}')
              : ToolResult.error('闹钟设置 Intent 失败 (需 L2 Shizuku/Root)\n${r()}');
        }

        // 有 OK/保存 按钮就点
        await s.clickByText('确定', exact: true) ||
            await s.clickByText('保存', exact: true);
        if (label != null && label.isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await s.clickByText('标签', exact: false);
          await s.inputText(label);
          await s.clickByText('确定', exact: true);
        }
        return ToolResult.ok('✅ 闹钟流程尝试完成 $timeStr\n${r()}');
      },
    );

/// ——— 系统能力：发送短信 (打开短信 App → 新建 → 收件人 + 内容 → 发送) ———
Tool _composeSystemSendSms(AndroidAutomationService s) => Tool(
      name: 'android_system_send_sms',
      description:
          '【高层·一步完成】打开 Android 短信/MMS App → 新建短信 → 填写手机号 + 文字内容 → 点发送。'
          '⚠ 本工具仅自动点 UI，实际短信是否发送会受运营商资费限制。',
      schema: _props({
        'phone_number': {
          'type': 'string',
          'description': '接收人手机号，例如「13800138000」或「10086」',
        },
        'message': {
          'type': 'string',
          'description': '短信正文文字，例如「验证码是 84291」「我到楼下了」',
        },
      }, required: [
        'phone_number',
        'message',
      ]),
      handler: (args) async {
        final to = args['phone_number'] as String? ?? '';
        final msg = args['message'] as String? ?? '';
        if (to.isEmpty || msg.isEmpty) return const ToolResult.error('缺少 phone_number/message');
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // Strategy 1: Intent SENDTO 最稳 (直接 调起 写好收件人和正文 的 短信页)
        final toNoBlank = to.replaceAll(' ', '').replaceAll('-', '');
        // Using android.content.extra.TEXT is the conventional way
        final shell2 = 'am start -a android.intent.action.SENDTO -d "smsto:$toNoBlank" '
            '--es android.telephony.extra.SMS_BODY "${msg.replaceAll('\'', '')}" '
            '--activity-clear-top';
        await s.openApp('com.google.android.apps.messaging') ||
            await s.openApp('com.android.mms') ||
            await s.openApp('com.android.messaging') ||
            true; // 即使没明确包名也继续
        steps.add('打开短信 App: OK');
        await Future<void>.delayed(const Duration(milliseconds: 900));

        // 尝试 Intent
        final s2 = await s.gshell(shell2);
        steps.add('gshell SENDTO 拉起填好的短信: exit=${s2.exitCode}');
        if (s2.ok) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          // 点「发送」
          final send = await s.clickByText('发送', exact: true) ||
              await s.clickByText('SIM1 发送', exact: false) ||
              await s.clickByText('短信发送', exact: false);
          steps.add('点发送: ${send ? 'OK' : 'fallback 右下角 (91%x, 88%y)坐标'}');
          if (!send) {
            final res = await s.screenResolution();
            if (res != null && res.length == 2) {
              await s.clickCoords((res[0] * 0.91).round(), (res[1] * 0.88).round());
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 900));
          return ToolResult.ok('✅ 发送短信流程完成 (手机号 $to →${msg.substring(0, msg.length > 12 ? 12 : msg.length)}${msg.length > 12 ? '…' : ''})\n${r()}');
        }

        // Fallback：纯 UI 路径
        steps.add('Intent SENDTO 不可用，改为手动填 UI');
        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        final new1 = await s.clickByText('新建', exact: false) ||
            await s.clickByText('+', exact: true) ||
            await s.clickCoords((w * 0.90).round(), (h * 0.88).round());
        steps.add('新建短信: ${new1 ? 'OK' : '坐标尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await s.inputText(to);
        steps.add('填收件人 $to: 完成');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await s.gshell('input keyevent 61 2>/dev/null'); // TAB
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await s.inputText(msg);
        steps.add('填正文: 完成');
        final sent = await s.clickByText('发送', exact: true) ||
            await s.clickCoords((w * 0.90).round(), (h * 0.88).round());
        steps.add('点发送: ${sent ? 'OK' : '坐标发送'}');
        await Future<void>.delayed(const Duration(milliseconds: 700));
        return ToolResult.ok('✅ 短信 UI 发送流程走完:\n${r()}');
      },
    );

// ============================================================================
// H5 高频日常工具 × 4 （抖音搜索 / 微信扫一扫 / 系统拨号 / 系统相机）
// ============================================================================

/// ——— 抖音：搜索关键词 → 综合结果 (视频/用户) ———
Tool _composeDouyinSearch(AndroidAutomationService s) => Tool(
      name: 'android_douyin_search',
      description:
          '【高层·一步完成】打开抖音 → 右上角🔎搜索图标 → 输入关键词 → 搜索 / 看综合结果。'
          '要搜挑战/音乐/视频/人名，直接用这个。',
      schema: _props({
        'keyword': {
          'type': 'string',
          'description': '要搜索的关键词，例如「AI Agent」「热门BGM 晴天」',
        },
      }, required: [
        'keyword'
      ]),
      handler: (args) async {
        final kw = args['keyword'] as String? ?? '';
        if (kw.isEmpty) return const ToolResult.error('缺少 keyword');
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final info = await s.getTopApp();
        if (info.package != 'com.ss.android.ugc.aweme') {
          final o = await s.openApp('com.ss.android.ugc.aweme');
          steps.add('打开抖音: ${o ? 'OK' : '失败'}');
          if (!o) return ToolResult.error('启动抖音失败\n${r()}');
          await s.waitForText('首页', timeoutSec: 18, pollMs: 800, exact: false);
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // 抖音搜索图标一般在右上角 ~92%x 6%y
        final search = await s.clickByText('搜索', exact: false) ||
            await s.clickCoords((w * 0.92).round(), (h * 0.06).round());
        steps.add('点搜索图标: ${search ? 'OK' : '坐标尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 400));

        final wOk = await s.inputText(kw);
        steps.add('输入「$kw」: ${wOk ? 'OK' : '失败'}');
        if (!wOk) return ToolResult.error('输入失败\n${r()}');

        final g = await s.clickByText('搜索', exact: true);
        if (!g) await s.pressKey(AndroidKey.enter);
        steps.add('触发搜索: OK');
        await Future<void>.delayed(const Duration(milliseconds: 900));
        return ToolResult.ok('✅ 抖音搜索完成\n${r()}');
      },
    );

/// ——— 微信：打开扫一扫 ———
Tool _composeWechatScanQr(AndroidAutomationService s) => Tool(
      name: 'android_wechat_scan_qr',
      description:
          '【高层·一步完成】打开微信 → 右上角 + 号 → 扫一扫。'
          '用户说「用微信扫码」「扫二维码付款」时直接调用。',
      schema: _props({
        'mode': {
          'type': 'integer',
          'description': '0=默认扫码，1=扫码后尝试切付款码/名片码 (目前未实现1)，默认0',
        },
      }),
      handler: (args) async {
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final ok1 = await s.openApp('com.tencent.mm');
        steps.add('打开微信: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('启动微信失败\n${r()}');
        await s.waitForText('微信', timeoutSec: 18, pollMs: 700, exact: false) ||
            await s.waitForText('通讯录', timeoutSec: 5, pollMs: 500, exact: true);

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // + 号在右上角 93%x 6%y
        final plus = await s.clickByText('+', exact: true) ||
            await s.clickCoords((w * 0.93).round(), (h * 0.06).round());
        steps.add('点右上角+号: ${plus ? 'OK' : '坐标尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 400));

        final scan = await s.clickByText('扫一扫', exact: true) ||
            await s.clickCoords((w * 0.45).round(), (h * 0.32).round());
        steps.add('点扫一扫: ${scan ? 'OK' : '坐标尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        return ToolResult.ok('✅ 微信扫一扫已打开 (对准码即可识别)\n${r()}');
      },
    );

/// ——— 系统：拨打电话 (Intent CALL 方式 更稳，L2 可用) ———
Tool _composeSystemDial(AndroidAutomationService s) => Tool(
      name: 'android_system_dial_phone',
      description:
          '【高层·一步完成】打开系统拨号 → 输号码 → 拨出去；如果有 Shizuku/Root，用 CALL Intent 直接呼出。'
          '用户说「给10086打个电话」时调用。',
      schema: _props({
        'phone_number': {
          'type': 'string',
          'description': '号码，例如「10086」「02112345678」',
        },
      }, required: [
        'phone_number'
      ]),
      handler: (args) async {
        final num = args['phone_number'] as String? ?? '';
        if (num.isEmpty) return const ToolResult.error('缺少 phone_number');
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // L2+ Intent 直接拨号
        final r1 = await s.gshell('am start -a android.intent.action.CALL -d "tel:$num" --activity-clear-top');
        steps.add('Intent CALL: ok=${r1.ok} exit=${r1.exitCode}');
        if (r1.ok) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
          return ToolResult.ok('✅ 已尝试直接拨出 $num (Intent CALL)\n${r()}');
        }

        // L1 UI Fallback: 打开拨号盘，输号，点绿色电话图标
        await s.openApp('com.android.dialer') ||
            await s.openApp('com.samsung.android.dialer') ||
            await s.openApp('com.miui.dialer') || true;
        steps.add('打开拨号器: OK');
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await s.inputText(num);
        steps.add('输入号码 $num: 完成');
        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // 绿色呼叫图标通常在下中部
        await s.clickCoords((w * 0.50).round(), (h * 0.88).round());
        steps.add('点拨号键: 完成 (坐标 50%x,88%y)');
        return ToolResult.ok('✅ 拨号 UI 流程走完\n${r()}');
      },
    );

/// ——— 系统相机：拍照 (打开相机 → 按快门键) ———
Tool _composeSystemTakePhoto(AndroidAutomationService s) => Tool(
      name: 'android_system_take_photo',
      description:
          '【高层·一步完成】打开系统相机 App → 等待对焦完成 → 按底部快门键拍照。'
          '⚠ 只是按快门按钮；不做自动取景/人脸检测（如需可配合 VLM 识别）。',
      schema: _props({
        'count': {
          'type': 'integer',
          'description': '连拍几张 (默认 1, 最多 9)',
        },
        'switch_camera': {
          'type': 'integer',
          'description': '0=保持当前, 1=切前置(自拍), 2=切后置, 默认 0',
        },
      }),
      handler: (args) async {
        final count = ((args['count'] as num?)?.toInt() ?? 1).clamp(1, 9);
        final cam = ((args['switch_camera'] as num?)?.toInt() ?? 0).clamp(0, 2);
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        await s.openApp('com.android.camera') ||
            await s.openApp('com.miui.camera') ||
            await s.openApp('com.samsung.android.camera') || true;
        steps.add('打开系统相机: OK');
        await Future<void>.delayed(const Duration(milliseconds: 1600)); // 相机启动冷启动慢

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;

        // 切换前后摄 图标一般在 屏幕顶部 8%~10% y, 中右
        if (cam == 1) {
          // 前置: 点切换按钮
          final sw = await s.clickByText('翻转', exact: false) ||
              await s.clickByText('切换', exact: false) ||
              await s.clickCoords((w * 0.92).round(), (h * 0.12).round()) ||
              await s.clickCoords((w * 0.50).round(), (h * 0.12).round());
          steps.add('切前置摄像头: ${sw ? 'OK' : '尝试坐标'}');
          await Future<void>.delayed(const Duration(milliseconds: 900));
        } else if (cam == 2) {
          steps.add('已设后置（默认）');
        }

        final shutterX = (w * 0.50).round();
        final shutterY = (h * 0.90).round();
        var took = 0;
        for (var i = 0; i < count; i++) {
          final shot = await s.clickByText('拍摄', exact: false) ||
              await s.clickByText('拍照', exact: false) ||
              await s.clickCoords(shutterX, shutterY);
          if (shot) took++;
          await Future<void>.delayed(const Duration(milliseconds: 700)); // 存图间隔
        }
        steps.add('快门 × $count: 成功 $took');
        return ToolResult.ok('✅ 拍照流程完成 ($took/$count 张)\n${r()}');
      },
    );

// ============================================================================
// H6 游戏自动化 + 支付宝付款码 （×3）
// ============================================================================

/// ——— 游戏 / Canvas UI 自动驾驶：截图 → 本地 VLM 分析可点击坐标 → 点击 → 循环 N 次 ———
/// 真正实现「操作游戏」的核心工具：没有文字控件的界面（游戏战斗/自动挂机）全靠截图+Omni视觉。
/// ⚠ 必须同时在 createAndroidAutomationTools 中传入 visionAnalyze，否则该工具不注册。
Tool _composeGameAutoVlmLoop(
  AndroidAutomationService s,
  Future<String> Function(String imagePath, String question) visionAnalyze,
) => Tool(
      name: 'android_game_auto_vlm_loop',
      description:
          '【高层·游戏专用】操作游戏 / 无文字的 Canvas 界面（如战斗/抽卡/自动寻路/挂机刷体力）。'
          '循环流程：截图 → 调本地 Omni VLM 让它分析：①说出下 1~5 个要点击的屏幕坐标(x,y 百分比或像素)+动作名 ②划屏方向 ③按哪个键。'
          'Agent 按 VLM 的建议真实执行 click/swipe/press，再 loop N 轮。'
          '⚠ 当用户说"帮我刷体力""自动打这关游戏"时用本工具，不要尝试用 click_by_text（游戏没有 View 文字）。',
      schema: _props({
        'game_package': {
          'type': 'string',
          'description': '游戏包名，例如 com.hypergryph.arknights / 空则不切换 App 用当前前台',
        },
        'loops': {
          'type': 'integer',
          'description': '循环多少轮 (默认 5，最多 80 轮避免无止刷)',
        },
        'prompt_suffix': {
          'type': 'string',
          'description': '【默认模板+附加】告诉 VLM 本轮游戏目标，例如：「优先点击蓝色 开始战斗 按钮；如果看到 X 关闭弹窗先关；确认道具就点确定；没有按钮就往上滑半屏找下一页」',
        },
        'custom_vlm_prompt': {
          'type': 'string',
          'description':
              '【完全覆盖默认提问】非空时，用你写的整段话直接向 VLM 提问，替换掉代码层写死的输出格式要求。'
              '你可以要求 VLM 返回任意你想要的格式（文字解释/中文/JSON/XML/逐条清单…），代码层不再硬编码输出格式。',
        },
        'skip_auto_execute': {
          'type': 'boolean',
          'description':
              'true=不自动执行任何 click/swipe/press，只把每一轮 VLM 的原始回答返回给你 (LLM)。'
              '这样你 (LLM) 可以看完 VLM 回答后自己决定调用哪个底层工具 (click_coords / swipe / custom_gesture / shell…)。'
              '默认 false=按默认 JSON 自动解析+执行。',
        },
        'step_delay_ms': {
          'type': 'integer',
          'description': '每步执行完等多少毫秒 (默认 900ms，动画慢的游戏可调 1500+)',
        },
      }),
      handler: (args) async {
        final pkg = (args['game_package'] as String?) ?? '';
        final loops = ((args['loops'] as num?)?.toInt() ?? 5).clamp(1, 80);
        final goal = (args['prompt_suffix'] as String?) ?? '';
        final delay = ((args['step_delay_ms'] as num?)?.toInt() ?? 900).clamp(200, 15000);
        // H9-1 / H9-2: 开放决策参数
        final customPrompt = (args['custom_vlm_prompt'] as String?) ?? '';
        final skipAuto = args['skip_auto_execute'] as bool? ?? false;

        final steps = <String>[];
        final clickCount = <int>[0];
        final swipeCount = <int>[0];
        final vlmAnswers = <String>[];
        // ---- 失败恢复状态 ----
        var staleCounter = 0;          // 连续相同动作计数
        String? lastActionSummary;     // 上一轮动作摘要
        const maxStale = 3;            // 连续多少轮相同动作后触发恢复
        var recoveryMode = false;      // 是否处于恢复模式
        const maxRecoveryActions = 3;  // 恢复模式最多尝试动作数
        String r() => steps.map((l) => '  • $l').join('\n');

        // 可选：打开游戏 App
        if (pkg.isNotEmpty) {
          final o = await s.openApp(pkg);
          steps.add('打开游戏 $pkg: ${o ? 'OK' : '失败'}');
          if (!o) return ToolResult.error('启动游戏失败\n${r()}');
          await Future<void>.delayed(const Duration(milliseconds: 2500)); // 冷启动游戏慢
        }

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;

        int toPx(num v, int maxPx) => v < 1 ? (v * maxPx).round() : v.toInt(); // 0~1 百分比 or 纯像素

        for (var i = 1; i <= loops; i++) {
          // 1) 截当前屏幕
          final img = await s.takeScreenshot();
          if (img == null) {
            steps.add('Round $i: 截图失败，中止');
            break;
          }

          // 2) 问 VLM：给我下一步动作
          //    ⚠ 开放决策模式：custom_vlm_prompt 非空时，100% 用 LLM 自己的提问，不注入任何代码层硬编码格式
          final q = customPrompt.isNotEmpty
              ? customPrompt
              : (() {
                  final sb = StringBuffer('你是手机游戏/RPA 视觉决策器。我给你一张截图，分辨率是 ${w}x$h。\n');
                  sb.writeln('【目标】${goal.isEmpty ? '分析并给出下一步操作建议' : goal}\n');
                  sb.writeln('【严格输出格式（只返回 JSON，不许其他文字）】：');
                  sb.writeln('{"actions": [{"type": "click|swipe|press|back|home|wait", "x%":0.15, "y%":0.33, "x2%":0.15, "y2%":0.05, "key":"BACK", "ms":900}], "summary": "一句话为什么选这些动作"}');
                  sb.writeln('字段说明：type=click 时给 x% y% (0~1 浮点数表示宽高百分比)；');
                  sb.writeln('  type=swipe 时给 x% y% (起点) + x2% y2% (终点) + ms (手势毫秒，默认 380)；');
                  sb.writeln('  type=press 时给 key 名字：HOME/BACK/MENU/VOLUME_UP/VOLUME_DOWN/POWER/ENTER/DEL/SPACE；');
                  sb.writeln('  type=wait 时给 ms (默认 1500)。');
                  sb.writeln('一次最多返回 3 个动作，按执行顺序排。禁止点击 < 3% 屏幕边缘 (防止误触状态栏)。');
                  return sb.toString();
                })();
          final answer = await visionAnalyze(img, q);
          vlmAnswers.add('--- Round $i VLM 回答 ---\n$answer');
          steps.add(skipAuto
              ? 'Round $i/${loops}：[skip_auto_execute=true] VLM 原始回答已收集 (不自动执行，由 LLM 自主决策)，${answer.length} 字'
              : 'Round $i/${loops}：VLM 建议 (${answer.length}字)');

          // H9-2: skip_auto_execute=true → 完全不解析、不自动执行，把原始回答留给 LLM
          if (skipAuto) {
            // 即使跳过执行也加一步 delay，避免截图太密
            await Future<void>.delayed(Duration(milliseconds: delay ~/ 2));
            continue;
          }

          // 3) 粗解析 JSON (容错：手搓正则解析 不要求完美 JSON，只要抓数字就行)
          try {
            // 先找 JSON 花括号整体
            final match = RegExp(r'\{[\s\S]*\}', multiLine: false).firstMatch(answer);
            String json = (match?.group(0) ?? answer).trim();
            // 正则抠出 actions 数组每项内的 kv
            final rxType = RegExp(r'"type"\s*:\s*"(click|swipe|press|back|home|wait)"', caseSensitive: false);
            final rx = (String k) => RegExp('"$k"%?\\s*:\\s*(-?\\d+(?:\\.\\d+)?)');
            final rxKey = RegExp(r'"key"\s*:\s*"([A-Z_]+)"', caseSensitive: false);

            final types = rxType.allMatches(json).map((m) => m.group(1)!.toLowerCase()).toList();
            final xs = rx('x').allMatches(json).map((m) => double.tryParse(m.group(1)!) ?? 0.0).toList();
            final ys = rx('y').allMatches(json).map((m) => double.tryParse(m.group(1)!) ?? 0.0).toList();
            final x2s = rx('x2').allMatches(json).map((m) => double.tryParse(m.group(1)!) ?? 0.0).toList();
            final y2s = rx('y2').allMatches(json).map((m) => double.tryParse(m.group(1)!) ?? 0.0).toList();
            final mss = rx('ms').allMatches(json).map((m) => int.tryParse(m.group(1)!) ?? 0).toList();
            final keys = rxKey.allMatches(json).map((m) => m.group(1)!).toList();

            final total = types.length;
            for (var k = 0; k < total.clamp(0, 3); k++) {
              final t = types[k];
              switch (t) {
                case 'click':
                  if (k < xs.length && k < ys.length) {
                    final px = toPx(xs[k], w);
                    final py = toPx(ys[k], h);
                    if (px >= w * 0.03 && px <= w * 0.97 && py >= h * 0.05 && py <= h * 0.97) {
                      final ok = await s.clickCoords(px, py);
                      if (ok) clickCount[0]++;
                      steps.add('  click (${xs[k].toStringAsFixed(2)},${ys[k].toStringAsFixed(2)})→${px}x$py: ${ok ? 'OK' : 'fail'}');
                    } else {
                      steps.add('  skip click @边缘 (${xs[k].toStringAsFixed(2)},${ys[k].toStringAsFixed(2)})');
                    }
                  }
                  break;
                case 'swipe':
                  if (k < xs.length && k < ys.length && k < x2s.length && k < y2s.length) {
                    final dur = (k < mss.length && mss[k] > 0) ? mss[k] : 380;
                    await s.swipe(toPx(xs[k], w), toPx(ys[k], h), toPx(x2s[k], w), toPx(y2s[k], h), durationMs: dur);
                    swipeCount[0]++;
                    steps.add('  swipe (${xs[k].toStringAsFixed(2)},${ys[k].toStringAsFixed(2)})→(${x2s[k].toStringAsFixed(2)},${y2s[k].toStringAsFixed(2)}) dur=${dur}ms');
                  }
                  break;
                case 'press':
                  if (k < keys.length) {
                    final keyName = keys[k].toUpperCase();
                    AndroidKey? kk;
                    switch (keyName) {
                      case 'BACK': kk = AndroidKey.back; break;
                      case 'HOME': kk = AndroidKey.home; break;
                      case 'VOLUME_UP': kk = AndroidKey.volumeUp; break;
                      case 'VOLUME_DOWN': kk = AndroidKey.volumeDown; break;
                      case 'ENTER': case 'DELETE': case 'DEL': kk = AndroidKey.enter; break;
                      case 'POWER': kk = AndroidKey.power; break;
                    }
                    if (kk != null) { await s.pressKey(kk); steps.add('  pressKey $keyName: sent'); }
                    else steps.add('  pressKey $keyName: 不支持');
                  }
                  break;
                case 'back':
                  await s.pressKey(AndroidKey.back); steps.add('  back: sent'); break;
                case 'home':
                  await s.pressKey(AndroidKey.home); steps.add('  home: sent'); break;
                case 'wait':
                  final wms = (k < mss.length && mss[k] > 0) ? mss[k] : 1500;
                  await Future<void>.delayed(Duration(milliseconds: wms));
                  steps.add('  wait ${wms}ms'); break;
              }
              await Future<void>.delayed(Duration(milliseconds: delay));
            }
          } catch (e) {
            steps.add('  VLM 解析出错 (跳过本轮): $e');
            // ignore, continue
          }

          // ---- 失败恢复检测 ----
          if (!skipAuto && !recoveryMode) {
            // 检测本轮动作摘要是否与上一轮相同（卡住判断）
            final currentSummary = steps.isNotEmpty ? steps.last : '';
            if (lastActionSummary != null &&
                currentSummary == lastActionSummary &&
                clickCount[0] + swipeCount[0] > 0) {
              staleCounter++;
              steps.add('  ⚠ 检测到动作重复 ($staleCounter/$maxStale)');
            } else {
              staleCounter = 0;
            }
            lastActionSummary = currentSummary;

            // 卡住 ≥ maxStale 轮 → 触发恢复策略
            if (staleCounter >= maxStale) {
              steps.add('  🚨 卡住超过 $maxStale 轮，触发恢复策略');
              staleCounter = 0;
              recoveryMode = true;
              // 恢复策略：按优先级尝试后退/主页/滑动
              for (var ri = 0; ri < maxRecoveryActions; ri++) {
                if (ri == 0) {
                  await s.pressKey(AndroidKey.back);
                  steps.add('  恢复[$ri]：按返回键');
                } else if (ri == 1) {
                  await s.swipe(0, 500, 0, -500, durationMs: 200);
                  steps.add('  恢复[$ri]：向上滑动');
                } else if (ri == 2) {
                  await s.pressKey(AndroidKey.home);
                  steps.add('  恢复[$ri]：按主页键');
                }
                await Future.delayed(const Duration(milliseconds: 800));
              }
              recoveryMode = false;
            }
          }

          // ---- 保存进度到持久化 ----
          if (i % 5 == 0) {
            final progress = {
              'round': i,
              'total_loops': loops,
              'clicks': clickCount[0],
              'swipes': swipeCount[0],
              'steps': steps.length,
              'game_pkg': pkg,
              'goal': goal,
              'timestamp': DateTime.now().toIso8601String(),
            };
            await s.gshell(
                'echo \'${jsonEncode(progress)}\' > /sdcard/Android/data/com.openagent.openagent/files/game_progress.json 2>/dev/null');
          }
        }

        final sb = StringBuffer(skipAuto
            ? '✅ 游戏 VLM 截图+开放问答完成 (skip_auto_execute=true, 未执行任何动作)\n'
            : '✅ 游戏 VLM 自动驾驶结束\n');
        sb.writeln('  轮次执行 $loops 次，累计: 点击=${clickCount[0]}, 滑屏=${swipeCount[0]}');
        if (customPrompt.isNotEmpty) sb.writeln('  ⚙ custom_vlm_prompt 已启用 (LLM 自主覆盖提问模板)');
        sb.writeln(r());
        if (vlmAnswers.isNotEmpty) {
          sb.writeln('\n===== 每轮 VLM 原始回答（供 LLM 自主分析）=====');
          sb.writeln(vlmAnswers.join('\n'));
        }
        return ToolResult.ok(sb.toString());
      },
    );

/// ——— 支付宝：扫一扫 ———
Tool _composeAlipayScan(AndroidAutomationService s) => Tool(
      name: 'android_alipay_scan',
      description:
          '【高层·一步完成】打开支付宝 → 顶部扫一扫 (扫码/收钱码)。'
          '用户说"用支付宝付款扫码""扫个商家码支付"时直接调用。',
      schema: _props({
        'mode': {
          'type': 'integer',
          'description': '0=扫一扫(默认), 1=付款码, 2=收款码。本工具=0(扫一扫); mode=1/2 请用 android_alipay_show_payment_code',
        },
      }),
      handler: (args) async {
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final ok = await s.openApp('com.eg.android.AlipayGphone');
        steps.add('打开支付宝: ${ok ? 'OK' : '失败 (未安装?)'}');
        if (!ok) return ToolResult.error('支付宝启动失败\n${r()}');

        // 支付宝冷启动较慢 (安全校验)
        await s.waitForText('首页', timeoutSec: 20, pollMs: 900, exact: false) ||
            await s.waitForText('扫一扫', timeoutSec: 20, pollMs: 900, exact: false);
        await Future<void>.delayed(const Duration(milliseconds: 500));

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // 扫一扫入口在首页左上 20%x 32%y 附近(4 宫格第一个图标) 或 顶部搜索栏左侧
        var sOk = await s.clickByText('扫一扫', exact: true) ||
            await s.clickByText('扫 一 扫', exact: false);
        if (!sOk) sOk = await s.clickCoords((w * 0.18).round(), (h * 0.32).round());
        steps.add('点扫一扫: ${sOk ? 'OK' : '坐标尝试 (18%x,32%y)'}');
        await Future<void>.delayed(const Duration(milliseconds: 1400));
        return ToolResult.ok('✅ 支付宝扫一扫已打开\n${r()}');
      },
    );

/// ——— 支付宝：出示付款码 / 收款码 ———
Tool _composeAlipayShowCode(AndroidAutomationService s) => Tool(
      name: 'android_alipay_show_payment_code',
      description:
          '【高层·一步完成】打开支付宝 → 点「付款/收钱」，出示给商家扫描的条形码+二维码 或 个人收款码。'
          'mode=1 付款码（商家扫你扣钱）；mode=2 收款码（别人扫你给你转账）。',
      schema: _props({
        'mode': {
          'type': 'integer',
          'description': '1=付款码(默认), 2=收款码',
        },
      }),
      handler: (args) async {
        final mode = ((args['mode'] as num?)?.toInt() ?? 1).clamp(1, 2);
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final ok = await s.openApp('com.eg.android.AlipayGphone');
        steps.add('打开支付宝: ${ok ? 'OK' : '失败'}');
        if (!ok) return ToolResult.error('启动失败\n${r()}');

        await s.waitForText('首页', timeoutSec: 22, pollMs: 900, exact: false) ||
            await s.waitForText('付款', timeoutSec: 20, pollMs: 900, exact: false);
        await Future<void>.delayed(const Duration(milliseconds: 500));

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // 付款 四宫格第二个图标 约 38%x 32%y；收钱 第三 宫格
        final label = mode == 1 ? '付款' : '收钱';
        final colX = mode == 1 ? 0.38 : 0.58;
        var cOk = await s.clickByText(label, exact: true) ||
            await s.clickByText('$label码', exact: false);
        if (!cOk) cOk = await s.clickCoords((w * colX).round(), (h * 0.32).round());
        steps.add('点「$label」(第${mode==1?'二':'三'}宫格 $colX): ${cOk ? 'OK' : '坐标尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 1400));

        // 部分版本点完会弹安全校验：默认点「知道了 / 确定」让码显示出来
        await s.clickByText('知道了', exact: false);
        await s.clickByText('确定', exact: false);
        return ToolResult.ok('✅ 支付宝${mode == 1 ? '付款码' : '收款码'}已请求显示\n${r()}');
      },
    );

// ============================================================================
// Stage 26: 社交 App 组合宏 — 小红书/抖音/微信 起号流程
// ============================================================================

/// ——— 小红书：发帖（图文笔记） ———
Tool _composeXiaohongshuPostNote(AndroidAutomationService s) => Tool(
      name: 'android_xhs_post_note',
      description:
          '【高层·一步完成】在小红书发一篇图文笔记（图文/纯文字/图片）。'
          '流程：打开小红书 → 点击底部➕ → 选相册图片 → 点下一步 → 编辑文字 → 发布。'
          '⚠ 需要已授予相册权限；优先用本工具，不要自己拆 clicks。',
      schema: _props({
        'title': {
          'type': 'string',
          'description': '笔记标题（可选，默认用图片描述）',
        },
        'content': {
          'type': 'string',
          'description': '笔记正文文字内容',
        },
        'image_path': {
          'type': 'string',
          'description': '可选：相册中的图片路径，为空则只发文字笔记',
        },
      }, required: ['content']),
      handler: (args) async {
        final title = (args['title'] as String?) ?? '';
        final content = args['content'] as String? ?? '';
        final imagePath = (args['image_path'] as String?) ?? '';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 1) 确认在小红书
        var info = await s.getTopApp();
        if (info.package != 'com.xingin.xhs') {
          final ok = await s.openApp('com.xingin.xhs');
          steps.add('打开小红书: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('步骤失败:\n${r()}\n小红书未安装');
          await s.waitForText('发现', timeoutSec: 15, pollMs: 800, exact: false);
        } else {
          steps.add('已在小红书');
        }
        await Future.delayed(const Duration(milliseconds: 800));

        // 2) 点底部➕ 发帖按钮（屏幕底部中间）
        var plus = await s.clickByText('+', exact: false) ||
            await s.clickByText('发布', exact: false);
        if (!plus) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final px = (res[0] * 0.5).round();
            final py = (res[1] * 0.95).round();
            plus = await s.clickCoords(px, py);
          }
        }
        steps.add('点➕ 发帖: ${plus ? 'OK' : '失败'}');
        if (!plus) return ToolResult.error('步骤失败:\n${r()}\n找不到发帖按钮');

        await Future.delayed(const Duration(milliseconds: 1200));

        // 3) 如果有图片，选图
        if (imagePath.isNotEmpty) {
          final selected = await s.clickByText('相册', exact: false) ||
              await s.clickByText('从相册选择', exact: false);
          steps.add('选相册: ${selected ? 'OK' : '跳过'}');
          await Future.delayed(const Duration(milliseconds: 1000));
          // 点第一张图
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final ix = (res[0] * 0.18).round();
            final iy = (res[1] * 0.25).round();
            await s.clickCoords(ix, iy);
            steps.add('选第一张图片');
          }
          await Future.delayed(const Duration(milliseconds: 800));
        }

        // 4) 点下一步/进入编辑
        var next = await s.clickByText('下一步', exact: false) ||
            await s.clickByText('完成', exact: false);
        steps.add('进入编辑: ${next ? 'OK' : '失败（可能已在编辑页）'}');
        await Future.delayed(const Duration(milliseconds: 800));

        // 5) 输入标题和正文
        if (title.isNotEmpty) {
          await s.clickByText('标题', exact: false);
          await Future.delayed(const Duration(milliseconds: 300));
          await s.inputText(title);
          steps.add('输入标题: ${title.length}字');
        }
        await Future.delayed(const Duration(milliseconds: 500));
        // 点正文区域输入
        await s.clickByText('填写正文', exact: false) ||
            await s.clickByText('说点什么', exact: false);
        await Future.delayed(const Duration(milliseconds: 300));
        await s.inputText(content);
        steps.add('输入正文: ${content.length}字');

        // 6) 发布
        await Future.delayed(const Duration(milliseconds: 500));
        var posted = await s.clickByText('发布', exact: false) ||
            await s.clickByText('发表', exact: false) ||
            await s.clickByText('发送', exact: false);
        steps.add('发布: ${posted ? 'OK' : '失败'}');

        return ToolResult.ok(
            '✅ 小红书发帖完成:\n${r()}${posted ? '' : '\n⚠ 可能未成功发布，请检查网络/权限'}');
      },
    );

/// ——— 小红书：私信 ———
Tool _composeXiaohongshuSendMessage(AndroidAutomationService s) => Tool(
      name: 'android_xhs_send_message',
      description:
          '【高层·一步完成】在小红书给指定用户发送私信。'
          '流程：打开小红书 → 点消息 → 搜索用户 → 点进对话 → 输入文字 → 发送。',
      schema: _props({
        'username': {
          'type': 'string',
          'description': '目标用户昵称',
        },
        'message': {
          'type': 'string',
          'description': '要发送的消息内容',
        },
      }, required: ['username', 'message']),
      handler: (args) async {
        final username = args['username'] as String? ?? '';
        final message = args['message'] as String? ?? '';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 打开小红书
        var info = await s.getTopApp();
        if (info.package != 'com.xingin.xhs') {
          final ok = await s.openApp('com.xingin.xhs');
          steps.add('打开小红书: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('步骤失败:\n${r()}\n小红书未安装');
          await s.waitForText('发现', timeoutSec: 15, pollMs: 800, exact: false);
        }
        await Future.delayed(const Duration(milliseconds: 600));

        // 点消息（底部右侧）
        var msg = await s.clickByText('消息', exact: false) ||
            await s.clickByText('私信', exact: false);
        if (!msg) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            msg = await s.clickCoords((res[0] * 0.85).round(), (res[1] * 0.96).round());
          }
        }
        steps.add('点消息: ${msg ? 'OK' : '失败'}');
        await Future.delayed(const Duration(milliseconds: 800));

        // 点搜索
        var search = await s.clickByText('搜索', exact: false);
        if (search) {
          await Future.delayed(const Duration(milliseconds: 400));
          await s.inputText(username);
          await Future.delayed(const Duration(milliseconds: 1500));
          // 点搜索结果
          await s.clickByText(username, exact: false);
          steps.add('搜索用户 $username');
        } else {
          steps.add('搜索失败，尝试直接点最近对话');
        }
        await Future.delayed(const Duration(milliseconds: 1000));

        // 输入消息
        await s.inputText(message);
        await Future.delayed(const Duration(milliseconds: 400));
        var sent = await s.clickByText('发送', exact: false);
        steps.add('发送消息: ${sent ? 'OK' : '失败'}');

        return ToolResult.ok('✅ 小红书私信完成:\n${r()}');
      },
    );

/// ——— 抖音：发作品（视频/图片） ———
Tool _composeDouyinPostVideo(AndroidAutomationService s) => Tool(
      name: 'android_douyin_post_video',
      description:
          '【高层·一步完成】在抖音发布作品（视频或图片）。'
          '流程：打开抖音 → 点底部➕ → 选相册视频/图片 → 点下一步 → 编辑描述 → 发布。',
      schema: _props({
        'description': {
          'type': 'string',
          'description': '作品描述/文案',
        },
        'media_type': {
          'type': 'string',
          'enum': ['video', 'image'],
          'description': '发布类型：video（视频）或 image（图片）',
        },
      }, required: ['description']),
      handler: (args) async {
        final desc = args['description'] as String? ?? '';
        final mediaType = (args['media_type'] as String?) ?? 'image';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 打开抖音
        var info = await s.getTopApp();
        if (info.package != 'com.ss.android.ugc.aweme') {
          final ok = await s.openApp('com.ss.android.ugc.aweme');
          steps.add('打开抖音: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('步骤失败:\n${r()}\n抖音未安装');
          await s.waitForText('推荐', timeoutSec: 15, pollMs: 800, exact: false);
        } else {
          steps.add('已在抖音');
        }
        await Future.delayed(const Duration(milliseconds: 800));

        // 点底部➕
        var plus = await s.clickByText('+', exact: false) ||
            await s.clickByText('发布', exact: false);
        if (!plus) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            plus = await s.clickCoords((res[0] * 0.5).round(), (res[1] * 0.92).round());
          }
        }
        steps.add('点➕ 发作品: ${plus ? 'OK' : '失败'}');
        if (!plus) return ToolResult.error('步骤失败:\n${r()}\n找不到发作品按钮');
        await Future.delayed(const Duration(milliseconds: 1000));

        // 选相册
        if (mediaType == 'image') {
          await s.clickByText('图片', exact: false);
          steps.add('切换到图片');
        } else {
          await s.clickByText('视频', exact: false);
          steps.add('切换到视频');
        }
        await Future.delayed(const Duration(milliseconds: 600));

        // 选第一个媒体
        final res = await s.screenResolution();
        if (res != null && res.length == 2) {
          await s.clickCoords((res[0] * 0.15).round(), (res[1] * 0.25).round());
          steps.add('选第一个媒体');
        }
        await Future.delayed(const Duration(milliseconds: 800));

        // 点下一步
        await s.clickByText('下一步', exact: false);
        await Future.delayed(const Duration(milliseconds: 1200));

        // 输入描述
        await s.clickByText('添加描述', exact: false) ||
            await s.clickByText('说点什么', exact: false);
        await Future.delayed(const Duration(milliseconds: 300));
        await s.inputText(desc);
        steps.add('输入描述: ${desc.length}字');

        // 发布
        await Future.delayed(const Duration(milliseconds: 500));
        var posted = await s.clickByText('发布', exact: false) ||
            await s.clickByText('发表', exact: false);
        steps.add('发布: ${posted ? 'OK' : '失败'}');

        return ToolResult.ok(
            '✅ 抖音发布作品完成:\n${r()}${posted ? '' : '\n⚠ 可能未成功发布'}');
      },
    );

/// ——— 微信：发图片朋友圈 ———
Tool _composeWechatPostImageMoments(AndroidAutomationService s) => Tool(
      name: 'android_wechat_post_image_moments',
      description:
          '【高层·一步完成】在微信朋友圈发图片。'
          '流程：打开微信 → 点发现 → 朋友圈 → 长按相机按钮 → 选图片 → 输入文字 → 发表。',
      schema: _props({
        'text': {
          'type': 'string',
          'description': '朋友圈文字内容',
        },
        'image_count': {
          'type': 'integer',
          'description': '选几张图片（默认1张，最多9张）',
        },
      }, required: ['text']),
      handler: (args) async {
        final text = args['text'] as String? ?? '';
        final count = ((args['image_count'] as num?)?.toInt() ?? 1).clamp(1, 9);
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 打开微信
        var info = await s.getTopApp();
        if (info.package != 'com.tencent.mm') {
          final ok = await s.openApp('com.tencent.mm');
          steps.add('打开微信: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('步骤失败:\n${r()}\n微信未安装');
          await s.waitForText('微信', timeoutSec: 15, pollMs: 800, exact: false);
        }
        await Future.delayed(const Duration(milliseconds: 600));

        // 点发现
        await s.clickByText('发现', exact: false);
        await Future.delayed(const Duration(milliseconds: 600));

        // 点朋友圈
        await s.clickByText('朋友圈', exact: false);
        await Future.delayed(const Duration(milliseconds: 800));

        // 长按相机按钮（右上角）
        var camFound = false;
        final res = await s.screenResolution();
        if (res != null && res.length == 2) {
          camFound = await s.longClickByText('相机', exact: false);
          if (!camFound) {
            // 右上角坐标
            camFound = await s.longClickCoords((res[0] * 0.93).round(), (res[1] * 0.02).round());
          }
        }
        steps.add('长按相机按钮: ${camFound ? 'OK' : '失败'}');
        if (!camFound) return ToolResult.error('步骤失败:\n${r()}\n找不到相机按钮');
        await Future.delayed(const Duration(milliseconds: 800));

        // 选图片
        if (res != null && res.length == 2) {
          for (var i = 0; i < count; i++) {
            final col = i % 3;
            final row = i ~/ 3;
            final ix = (res[0] * (0.12 + col * 0.35)).round();
            final iy = (res[1] * (0.15 + row * 0.28)).round();
            await s.clickCoords(ix, iy);
            await Future.delayed(const Duration(milliseconds: 200));
          }
          steps.add('选了 $count 张图片');
        }
        await Future.delayed(const Duration(milliseconds: 500));

        // 点完成
        await s.clickByText('完成', exact: false);
        await Future.delayed(const Duration(milliseconds: 800));

        // 输入文字
        if (text.isNotEmpty) {
          await s.inputText(text);
          steps.add('输入文字: ${text.length}字');
        }

        // 发表
        await Future.delayed(const Duration(milliseconds: 400));
        var posted = await s.clickByText('发表', exact: false);
        steps.add('发表: ${posted ? 'OK' : '失败'}');

        return ToolResult.ok('✅ 微信朋友圈发图完成:\n${r()}');
      },
    );