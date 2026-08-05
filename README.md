<div align="center">

# OpenAgent

**端侧大模型 App · MNN-LLM × Flutter**

纯本地推理 · 多模态交互 · 跨平台 · 隐私优先

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-green.svg)](#)
[![Engine](https://img.shields.io/badge/engine-MNN--LLM%203.6.1-orange.svg)](#)

</div>

---

## 简介

OpenAgent 是一款运行在手机本地的开源大模型应用，基于阿里巴巴 [MNN-LLM](https://github.com/alibaba/MNN) 推理引擎与 [Flutter](https://flutter.dev) 构建。所有推理在设备端完成，无需联网，对话数据不离开手机。

- **纯端侧推理**：Qwen3 / DeepSeek 等模型本地运行
- **隐私优先**：无网络请求，对话内容永不上传
- **跨平台**：一套 Flutter 代码同时支持 Android 与 iOS
- **多模态**：文本对话 + 图像理解 + 语音输入（Qwen2.5-Omni）
- **Agent 模式**：ReAct 循环 + 170+ 工具，可自主操控手机
- **Android RPA 自动化**：三层权限体系，替代人工操作手机
- **iOS Shortcuts 集成**：Agent 注册 Siri 语音快捷指令，通过 URL scheme 触发系统级操作
- **iOS Live Activities 保活**：Agent 运行时在锁屏/灵动岛显示实时状态（iOS 16.1+）
- **保活与隐藏**：前台服务保活 + 安全模式 + Shizuku 隐藏特征 + 防检测弹窗策略
- **云端 LLM 接入（可选）**：支持 OpenAI / Anthropic / 通义千问 / 豆包 / Groq / Ollama 等
- **MCP 协议支持**：HTTP + Stdio 双传输，可连接任意 MCP server
- **Skill 模块化系统**：内置 8+ 模块 + JSON 运行时注册

---

## 核心功能

### 1. 本地大模型推理

- 支持 Qwen3 系列（0.6B / 1.7B / 4B）和 Qwen2.5-Omni（7B 多模态）
- 内置模型市场，App 内直接下载量化模型
- 可调采样参数：temperature / top_k / top_p / max_tokens / System Prompt
- 实时显示 tokens/sec、生成耗时、TTFT 等性能指标
- **自适应推理调度**：根据设备电量、温度、可用内存自动切换推理 Profile（高性能/正常/省电/热限流/超轻量）
- **设备状态监控**：实时监控电池、温度、内存、CPU 频率，30 秒轮询事件驱动
- **低端机适配**：自动检测设备内存，<4GB 推荐最小模型 + mmap 内存模式 + 缩小 KV Cache 窗口
- **首次启动自动推荐模型**：根据设备 RAM 自动选择最合适的模型（8GB+->4B, 4GB+->1.7B, <4GB->0.6B）
- **GPU 加速**：自动检测 Adreno/Mali GPU 并启用 OpenCL 后端，推理速度提升 3-5x
- **模型预热**：加载后自动执行 dummy 推理触发内核编译和 OpenCL 缓存生成，首次查询 TTFA 降低 50%+
- **动态后端配置**：根据设备能力动态设置线程数（匹配大核）、精度、内存模式、采样器
- **采样优化**：默认 topK=20（减少采样计算量）、mixed sampler、repetition_penalty=1.05

### 2. Agent 模式

- **ReAct 循环**：思考→工具调用→观察结果→下一步决策
- **40+ 内置工具**：计算器、日期、文本统计、单位换算、JSON 格式化、Web 搜索、HTTP 获取、HTML 转文本、随机数、UUID、Base64 编解码、颜色转换、计时器、天气、IP 查询、文本模板、分析规划、URL 编解码、正则测试、字符串大小写转换、Hex 编解码、哈希、CSV↔JSON 转换、Markdown 表格、密码生成、日期计算
- **约束解码（Constrained Decoding）**：在工具调用模式下强制输出合法 JSON，大幅减少小模型格式错误
- **意图路由分类器**：7 类意图识别（数学/日期/知识/Web/Android自动化/复杂任务/闲聊），高置信度直接调用工具跳过 ReAct
- **工具 Schema 校验**：执行前检查必填参数、类型、枚举值、范围，提前拒绝无效参数
- **自纠错重试循环**：网络/超时/资源竞争类错误自动指数退避重试（最多 2 次）
- **KV Cache 管理**：H2O 重击者保留策略 + 滑动窗口 + 摘要缓存，保持长对话内存可控
- **工具调用统计**：实时显示每次工具调用的耗时和成功/失败计数
- **KV 长期记忆**：跨会话持久化，agent_memory_set/get 接口
- **定时任务调度**：支持 daily:HH:MM / interval:秒 / cron 三种格式，持久化到本地文件
- **智能笔记/提醒**：笔记创建/搜索/分类，待办管理（优先级/标记完成/清除）
- **每日简报**：汇总待办事项、今日笔记、定时任务状态
- **快捷助手**：计算、单位换算、时间差、倒计时、随机数

### 3. Android RPA 自动化

三层权限架构，Agent 可像人一样操控手机：

| 层级 | 能力 | 实现 |
|---|---|---|
| **L1** | 屏幕文字识别、点击、滑动、输入 | AccessibilityService |
| **L2** | 精准坐标操作、系统级命令、截图 | Shizuku Shell（无 SDK 依赖） |
| **L3** | 预留（Root 设备） | — |

**170+ 个自动化工具**，覆盖全场景：

- **原子操作**：点击文字/坐标/ID、滑动、输入、按键、截图、UI Dump、长按、手势、剪贴板
- **社交 App 宏**：微信发消息/群发/扫码/朋友圈点赞/发图/文字朋友圈，抖音点赞/评论/关注/搜索/发作品/批量滑屏，小红书搜索/点赞/关注/发帖/私信，B站搜索/发弹幕
- **游戏自动化**：VLM 自动驾驶循环（截图→分析→操作→验证→恢复），支持失败恢复（3 轮卡住→自动回退）
- **系统设置**：WiFi、蓝牙、音量、闹钟、短信、拨号、拍照
- **App 管理**：打开/安装/卸载/禁用/清除缓存，查看权限列表/占用排行
- **文件管理**：存储分析、大文件扫描、按类型归类、清理临时文件/下载目录
- **深度清理**：快速清理、深度清理（全部缓存+临时文件+缩略图+空目录+卸载残留）
- **通知管理**：获取通知列表、按 key 取消、snooze、快捷回复
- **通知监听**：实时监听通知，200 条环形缓存
- **录制回放**：录制操作序列（screenrecord + 触摸事件），保存/重放
- **权限管理**：AppOps 细粒度权限 get/set，运行时权限申请引导，全景权限自检
- **防检测**：检查当前前台 App 是否高风险、安全模式（Kotlin 端实际手势拦截）、32+ 银行/支付/安全 App 名单
- **保活**：系统省电白名单 + 前台服务（OpenAgentForegroundService，START_STICKY 自动重启）
- **隐藏**：Shizuku 隐藏图标/进程 + 禁用无障碍服务 + 安全模式联动
- **虚拟定位**：Mock GPS 设置/清除/状态检查
- **VLM 增强**：屏幕变化检测、截图指纹哈希、区域裁剪分析
- **VLM 无锚点 UI 操控**：视觉 Grounding 引擎 + 跨分辨率适配 + 4 级混合定位（Accessibility→VLM→OCR→坐标试探）
- **操作链容错**：检查点系统 + App 状态机 + 5 类异常检测与恢复（弹窗/导航失败/元素缺失/超时/未知状态）

### 4. iOS 自动化与保活

由于 iOS 没有 AccessibilityService，RPA 能力受限，但通过以下方式补充：

**Siri Shortcuts 集成**：
- Agent 可注册语音快捷指令（`ios_shortcut_donate`），用户通过 Siri 触发 Agent 任务
- 通过 URL scheme 触发系统级操作（拨打电话 `tel:`、发送短信 `sms:`、打开地图 `maps:`）
- 打开第三方 App（微信 `weixin://`、抖音 `snssdk1128://`、支付宝 `alipay://` 等）
- 双向通信：Siri 触发快捷指令时，AppDelegate 通过 MethodChannel 回调到 Agent

**Live Activities 保活（iOS 16.1+）**：
- Agent 开始运行时自动启动 Live Activity，在锁屏和灵动岛显示状态
- 每次工具调用时实时更新状态文本（"正在思考..." / "正在执行工具: xxx"）
- Agent 完成或退出时自动结束 Live Activity
- 基于 ActivityKit + WidgetKit 实现

**9 个 iOS 专属工具**：

| 工具 | 说明 |
|---|---|
| `ios_shortcut_donate` | 注册 Siri 语音快捷指令 |
| `ios_shortcut_list` | 列出已注册的快捷指令 |
| `ios_shortcut_trigger` | 通过 URL scheme 触发系统操作 |
| `ios_shortcut_delete` | 删除快捷指令 |
| `ios_open_url` | 打开 URL（浏览器/Deeplink） |
| `ios_open_app` | 通过 URL scheme 打开第三方 App |
| `ios_live_activity_start` | 启动 Live Activity 保活 |
| `ios_live_activity_update` | 更新 Live Activity 状态 |
| `ios_live_activity_end` | 结束 Live Activity |

**Skill 模块**：`ios_shortcuts` + `ios_live_activity`，模型按需启用，Android 上自动 no-op。

**In-App WebView 自动化（跨平台 RPA 替代方案）**：

iOS 上无法像 Android 那样通过 AccessibilityService 操控原生 App。作为替代，OpenAgent 提供了基于内置 WebView 的网页版自动化能力，在 Android 和 iOS 上均可使用：

- `web_navigate` - 在内置 WebView 中导航到 URL（微信网页版、抖音 H5 等）
- `web_execute_js` - 执行任意 JavaScript 代码操作 DOM
- `web_get_page_text` - 提取页面文本内容
- `web_click_element` - 通过 CSS 选择器点击元素
- `web_fill_form` - 填写表单输入框
- `web_get_url` - 获取当前页面 URL
- `web_screenshot` - 对 WebView 截图（可用于 VLM 分析）
- `web_wait_for_element` - 等待元素出现（带超时）

**iOS RPA 落地路径说明**：

| 方案 | 适用场景 | 上架限制 |
|---|---|---|
| **Siri Shortcuts + URL Scheme** | 系统级操作（拨号/短信/地图）+ 打开第三方 App | App Store 可用 |
| **In-App WebView 自动化** | 网页版微信/抖音/H5 应用操控 | App Store 可用 |
| **Live Activities 保活** | Agent 运行时状态常驻锁屏/灵动岛 | iOS 16.1+，App Store 可用 |
| **XCTest UI 测试框架** | 深度原生 App 操控 | 仅限 TestFlight / 企业签名，无法上 App Store |

> **上架建议**：App Store 版本只走 Shortcuts + In-App 自动化路线。TestFlight / 企业包可额外启用 XCTest UI 能力，但需明确标注。

**iOS 能力边界（明确标注）**：

| 能力 | Android | iOS (App Store) | iOS (TestFlight/企业) | 说明 |
|---|---|---|---|---|
| 无障碍服务 RPA | ✅ 完整支持 | ❌ 不可用 | ❌ 不可用 | iOS 无 AccessibilityService 等价物 |
| 屏幕点击/滑动/输入 | ✅ AccessibilityService | ❌ | ⚠️ XCTest UI | XCTest 仅限开发者模式 |
| UI 层级 Dump | ✅ | ❌ | ⚠️ XCTest UI | |
| 截屏分析 | ✅ MediaProjection | ✅ ReplayKit | ✅ ReplayKit | iOS 需用户授权屏幕录制 |
| App 启动 | ✅ Intent + gshell | ✅ URL Scheme | ✅ URL Scheme | iOS 仅限已注册 scheme 的 App |
| 系统操作（拨号/短信） | ✅ Intent | ✅ URL Scheme | ✅ URL Scheme | `tel:` `sms:` `maps:` |
| Siri 语音快捷指令 | ❌ | ✅ App Intents | ✅ App Intents | iOS 16+ |
| Live Activities 保活 | ❌ | ✅ ActivityKit | ✅ ActivityKit | iOS 16.1+，锁屏/灵动岛 |
| In-App WebView 自动化 | ✅ | ✅ | ✅ | 跨平台，网页版应用操控 |
| 文件系统访问 | ✅ 完整 | ⚠️ 沙箱限制 | ⚠️ 沙箱限制 | iOS App Sandbox |
| Shell 命令执行 | ✅ Shizuku/Root | ❌ | ❌ | iOS 不允许 |
| 通知监听 | ✅ NotificationListenerService | ❌ | ❌ | iOS 无等价 API |
| 通话日志/通讯录 | ✅ ContentProvider | ⚠️ 有限 Contacts | ⚠️ 有限 Contacts | iOS 仅限通讯录读取 |
| 传感器访问 | ✅ 完整 | ⚠️ 有限 | ⚠️ 有限 | iOS 后台传感器受限 |
| 前台服务保活 | ✅ Foreground Service | ❌ | ❌ | iOS 无前台服务，靠 Live Activity 替代 |
| 防检测/隐藏 | ✅ Shizuku 隐藏 | ❌ | ❌ | iOS 不需要（沙箱隔离） |

> **总结**：iOS 上 RPA 能力约为 Android 的 30%，主要依赖 Shortcuts + URL Scheme + WebView 三条路径。核心限制是无法操控其他原生 App 的 UI。

**跨平台 #ifdef 治理**：

平台差异通过统一的抽象层管理，不散落在 UI 代码中：
- `PlatformAutomationService` 接口：统一 `isSupported` 闸门契约
- `PlatformToolFactory` 接口：Android/iOS 工厂各自实现，统一注册入口 `createPlatformTools()`
- `ToolFactoryContext`：收敛工厂参数（service/visionAnalyze/memoryBackend 等）
- 优雅降级：不支持的平台上注册降级 stub 工具，返回"当前功能仅在 XX 平台可用"提示

### 5. 云端 LLM 接入

- 支持任意 OpenAI 兼容端点（OpenAI / DeepSeek / 通义千问 / 豆包 / Groq / Ollama / Anthropic / 自定义）
- 纯 Dart HTTP 流式实现，不引入第三方 SDK
- 设置页「测试连接」按钮一键验证

### 6. MCP 协议支持

- 统一 Model Context Protocol 客户端抽象
- HTTP + Stdio 双传输
- 连接参数持久化，一键重连
- 支持 GitHub、浏览器、数据库等任意 MCP server
- **Capability-based 权限模型**：每个 MCP Server 只能访问声明的工具子集
- **Stdio 沙箱进程隔离**：限制文件系统访问和执行时间
- **mDNS 局域网发现**：自动发现无公网环境下的 MCP Server

### 7. Skill 模块化系统

- 8+ 内置模块：android_rpa / ios_shortcuts / ios_live_activity / builtin_math_time / knowledge_rag / longterm_memory / execute_plan / vision_analyze / mcp_gateway 等
- 模型自主选择启用/禁用，拓扑依赖自动排序
- 运行时 JSON 注册 Skill：callMcp / callTool / template / echo 四种 adapter，无需改代码
- 从轨迹创建 Skill：任务完成后可将工具调用序列保存为可复用 Skill
- **Skill 自动合成**：从多条同类轨迹中通过 LCS 序列比对提取可参数化模板
- **Skill 版本演化**：版本管理 + 成功率追踪 + 自动回退到最佳版本
- 会话生命周期管理：状态保存/加载、bootstrap 一键恢复

### 8. 知识库管理

- 内置文档管理页面，添加/查看/删除 .txt 文档
- Agent 可自动检索知识库内容
- **语义检索（RAG）**：ONNX Runtime Mobile + bge-small Embedding 模型 + SQLite HNSW 向量索引
- **混合检索**：语义 + 关键词 RRF 融合排序，比纯语义检索 F1 提升 5%+
- **三层缓存**：热/温/冷分级（7 天窗口），查询延迟 < 200ms

### 9. 长期记忆系统

- **记忆重要性评分**：基于访问频率、时效性（指数衰减，半衰期 7 天）、语义重要性综合评分
- **跨会话记忆图谱**：有向图结构，支持引用/时序/语义三种关联，支持模糊召回
- **三级记忆压缩**：热记忆（常驻内存）、温记忆（GZIP 压缩）、冷记忆（摘要归档）
- **向量语义检索**：支持自然语言查询，Top-5 命中率 > 85%

### 10. 异构计算调度

- **设备能力检测**：通过 MethodChannel 读取真实硬件指标（GPU 型号、CPU 大小核、内存带宽、NPU 可用性、散热状态）
- **自适应后端选择**：CPU / OpenCL / Vulkan / Metal / NPU 动态切换
- **GPU 加速**：Adreno/Mali GPU 自动启用 OpenCL 后端，推理速度提升 3-5x
- **线程优化**：线程数匹配 CPU 大核数量（非总核数），减少调度开销
- **模型预热**：加载后执行 dummy 推理触发内核编译 + OpenCL 缓存生成
- **运行时热切换**：根据设备状态自动切换推理后端和采样参数

### 11. 多模态量化

- **解耦量化**：视觉编码器（ViT）与语言模型使用不同量化位数
- **自动配置选择**：根据设备内存自动选择 INT3/INT4/INT8/FP16 方案
- **量化基准框架**：支持 per-channel / per-token / per-group 粒度测试

### 12. 会话导出

- 一键导出对话记录为文本文件，便于备份和分享

---

## 架构

```
┌─────────────────────────────────────────────┐
│            Flutter UI (Dart)                │
│   对话页 · 模型市场 · 设置 · Agent(ReAct)     │
├─────────────────────────────────────────────┤
│         mnn_llm 插件 (dart:ffi)             │
│   MnnLlmSession → 流式 Stream<String>       │
├─────────────────────────────────────────────┤
│      C API Wrapper (extern "C")             │
│   mnn_llm_capi.cpp · 回调式流式输出          │
├─────────────────────────────────────────────┤
│      MNN-LLM C++ Engine                     │
│   Llm / Omni / Tokenizer / Sampler          │
│   OpenCL(Android) · Metal(iOS) 加速          │
├─────────────────────────────────────────────┤
│     Agent Runtime · 可扩展工具生态层         │
│   ├─ System Prompt 规则 A~S (决策指导)        │
│   ├─ agent_runtime (ReAct 循环 + 工具注册表)  │
│   │   ├─ 约束解码 (Constrained Decoding)    │
│   │   ├─ 意图路由分类器                      │
│   │   ├─ 工具 Schema 校验                    │
│   │   ├─ 自纠错重试循环 (指数退避)            │
│   │   └─ 自适应推理调度 (功耗/温度感知)       │
│   ├─ KV Cache 管理                          │
│   │   ├─ H2O 重击者保留策略                  │
│   │   └─ 滑动窗口 + 摘要缓存                 │
│   ├─ 长期记忆系统                            │
│   │   ├─ 记忆重要性评分                      │
│   │   ├─ 跨会话记忆图谱                      │
│   │   ├─ 三级压缩 (热/温/冷)                 │
│   │   └─ 向量语义检索                        │
│   ├─ 端侧 RAG                               │
│   │   ├─ ONNX Runtime Mobile + Embedding    │
│   │   ├─ SQLite HNSW 向量索引               │
│   │   ├─ 混合检索 (语义+关键词 RRF)          │
│   │   └─ 三层缓存                            │
│   ├─ MCP 协议层 (lib/agent/mcp)             │
│   │   ├─ McpClient (initialize/listTools/callTool)
│   │   ├─ HttpMcpTransport / StdioMcpTransport
│   │   ├─ Capability-based 权限模型          │
│   │   ├─ Stdio 沙箱进程隔离                  │
│   │   ├─ mDNS 局域网发现                    │
│   │   └─ MCP 持久化 (mcp_state_save/load)   │
│   └─ Skill 系统 (lib/agent/skills)
│       ├─ SkillManager (拓扑排序·remember·快照)
│       ├─ 8+ 内置 Skill
│       ├─ JsonSpecSkill (运行时 JSON 动态注册)
│       ├─ 轨迹录制 + 自动合成 (LCS 序列比对)
│       ├─ 版本演化与自修复
│       └─ 会话生命周期 (save/load·bootstrap)
├─────────────────────────────────────────────┤
│      Android RPA 自动化层 (Kotlin)           │
│   L1: AccessibilityService (UI 操控)        │
│   L2: Shizuku Shell (反射无 SDK 依赖)       │
│   L3: Root 预留                              │
│   ├─ 检查点系统 + 状态机                     │
│   ├─ 5 类异常检测与恢复                      │
│   ├─ VLM 无锚点 UI 操控                     │
│   └─ MethodChannel ↔ Dart 工具桥接           │
├─────────────────────────────────────────────┤
│      iOS 自动化层 (Swift)                    │
│   ├─ Siri Shortcuts (AppIntents/NSUserActivity)│
│   ├─ URL Scheme (UIApplication.shared.open)  │
│   ├─ Live Activities (ActivityKit)           │
│   └─ MethodChannel ↔ Dart 工具桥接           │
└─────────────────────────────────────────────┘
```

---

## 性能基线

| 模型 | 内存占用 | 骁龙 8 Gen 3 | A17 Pro | 适用场景 |
|---|---|---|---|---|
| Qwen3-0.6B | ~0.6 GB | 30+ t/s | 40+ t/s | 入门 / 低端机 |
| Qwen3-1.7B | ~1.3 GB | 18-22 t/s | 25-30 t/s | 日常对话（推荐） |
| Qwen3-4B | ~2.4 GB | 12-15 t/s | 15-20 t/s | 旗舰机 · 更强能力 |
| Qwen2.5-Omni-7B | ~4.0 GB | 8-10 t/s | 12-15 t/s | 多模态 · 需 8GB+ 内存 |

---

## 快速开始

### 环境要求

- Flutter ≥ 3.22（含 Dart ≥ 3.3）
- Android Studio + CMake 3.22+
- Xcode 15+（iOS 开发，需 macOS）
- arm64 Android 真机（模拟器不支持 OpenCL/Metal 加速）

### 1. 克隆并初始化

```bash
git clone https://github.com/your-name/openagent.git
cd openagent
flutter pub get
```

### 2. 下载 MNN 预编译库

```bash
cd packages/mnn_llm
bash scripts/download_mnn_prebuilt.sh
```

### 3. 运行

**方式一：App 内模型市场下载（推荐）**

```bash
flutter run --release
# 打开 App → 底部导航「模型」→ 选择模型 → 下载 → 开始对话
```

**方式二：adb push 预下载模型**

```bash
adb push Qwen3-0.6B-MNN /sdcard/Android/data/com.openagent.openagent/files/models/
flutter run --release
```

---

## 项目结构

```
openagent/
├── lib/                        # Flutter App 主工程
│   ├── main.dart               # 入口
│   ├── app.dart                # MaterialApp + GoRouter
│   ├── data/
│   │   ├── models/models.dart            # 数据模型
│   │   ├── rag/                          # 端侧 RAG 系统
│   │   │   ├── onnx_runtime_session.dart  # ONNX Runtime 封装
│   │   │   ├── embedding_service.dart     # Embedding 服务
│   │   │   ├── vector_index.dart          # SQLite HNSW 向量索引
│   │   │   ├── hybrid_retriever.dart      # 混合检索器
│   │   │   └── knowledge_cache.dart       # 三层缓存
│   │   ├── services/
│   │   │   ├── device_monitor_service.dart   # 设备状态监控（接入真实硬件数据）
│   │   │   ├── device_capability_service.dart # 设备能力检测 + 模型推荐
│   │   │   ├── device_probe_service.dart      # 原生设备检测 MethodChannel 封装
│   │   │   ├── mnn_config_builder.dart        # 动态 MNN 后端配置生成
│   │   │   ├── quantization_benchmark.dart   # 量化基准框架
│   │   │   ├── auto_quantization.dart        # 自动量化选择
│   │   │   ├── file_storage_service.dart
│   │   │   ├── model_download_service.dart
│   │   │   ├── schedule_service.dart     # 定时任务调度
│   │   │   ├── android_automation_service.dart
│   │   │   ├── ios_automation_service.dart  # iOS 自动化 (Shortcuts + Live Activities)
│   │   │   └── platform_automation_service.dart # 平台抽象接口 (PlatformAutomationService)
│   │   └── repositories/
│   ├── features/
│   │   ├── chat/                       # 对话页
│   │   ├── model_market/               # 模型市场
│   │   ├── knowledge_base/             # 知识库
│   │   ├── automation/                 # 权限引导页
│   │   └── settings/                   # 设置页
│   └── agent/
│       ├── agent_runtime.dart          # ReAct 循环 + 约束解码 + 自纠错
│       ├── agent_prompt.dart           # System Prompt 模板
│       ├── agent_constants.dart        # 共享常量
│       ├── constraint_decoder.dart     # 约束解码器
│       ├── intent_classifier.dart      # 意图路由分类器
│       ├── tool_validator.dart         # Schema 校验器
│       ├── inference_scheduler.dart    # 自适应推理调度器
│       ├── kv_cache/                   # KV Cache 管理
│       │   ├── h2o_strategy.dart       # H2O 重击者策略
│       │   └── sliding_window.dart     # 滑动窗口 + 摘要缓存
│       ├── memory/                     # 长期记忆系统
│       │   ├── memory_scorer.dart      # 记忆重要性评分
│       │   ├── memory_graph.dart       # 跨会话记忆图谱
│       │   ├── memory_compressor.dart  # 三级记忆压缩
│       │   └── vector_memory_backend.dart # 向量语义记忆
│       ├── android_tools.dart          # 入口（工厂函数）
│       ├── android_tools/              # 6 个子模块
│       ├── ios_tools.dart              # iOS 自动化工具 (Shortcuts + Live Activities)
│       ├── web_tools.dart              # 跨平台 WebView 自动化工具
│       ├── tool_registry.dart          # 统一平台工具注册 (PlatformToolFactory)
│       ├── builtin_tools.dart          # 入口（工厂函数）
│       ├── builtin_tools/              # 3 个子模块
│       ├── rpa/                        # RPA 自动化增强
│       │   ├── checkpoint_system.dart  # 检查点系统
│       │   ├── state_machine.dart      # App 状态机
│       │   ├── error_recovery.dart     # 异常检测与恢复
│       │   ├── vision_grounding.dart   # VLM 视觉定位
│       │   ├── resolution_adapter.dart # 跨分辨率适配
│       │   └── hybrid_localizer.dart   # 混合定位策略
│       ├── mcp/                        # MCP 协议层
│       │   ├── mcp_client.dart
│       │   ├── mcp_persistence.dart
│       │   ├── mcp_security.dart       # Capability 权限模型
│       │   ├── mcp_sandbox.dart        # Stdio 沙箱
│       │   └── mcp_discovery.dart      # mDNS 局域网发现
│       └── skills/                     # Skill 系统
│           ├── skills.dart, skill_tools.dart, skills_extra.dart
│           ├── session_lifecycle.dart
│           ├── skill_trace_recorder.dart # 轨迹录制
│           ├── skill_synthesizer.dart    # 自动合成
│           └── skill_evolution.dart     # 版本演化
│           └── ios_skills.dart          # iOS Shortcuts + Live Activity Skills
├── android/.../                         # Android 原生层
│   ├── DeviceProbe.kt                  # 设备硬件检测 (MethodChannel)
│   └── automation/                     # 自动化层
├── ios/Runner/                         # iOS 原生层
│   ├── AppDelegate.swift               # Channel 注册 + Siri 回调
│   ├── IosAutomationChannel.swift       # Shortcuts + URL + ActivityKit
│   └── Info.plist                      # NSSupportsLiveActivities + 权限
├── packages/mnn_llm/                   # FFI 插件
├── packages/onnx_runtime/              # ONNX Runtime 插件骨架
├── test/                               # 单元测试（50+ 文件）
├── tools/                              # 辅助脚本
└── .github/workflows/                  # CI/CD
```

---

## 与同类项目对比

| 项目 | 引擎 | 平台 | 多模态 | RPA 自动化 | MCP 协议 | 动态 Skill | 开源 |
|---|---|---|---|---|---|---|---|
| **OpenAgent** | MNN-LLM | Android + iOS | ✅ | ✅ 90+ 工具 | ✅ HTTP+Stdio | ✅ JSON 运行时注册 | ✅ |
| MNN Chat（官方） | MNN-LLM | Android + iOS | ✅ | ❌ | ❌ | ❌ | ✅ |
| llama.cpp | ggml | 全平台 | 部分 | ❌ | 部分 | ❌ | ✅ |
| Tasker | - | Android | ❌ | ✅ 插件生态 | ❌ | ✅ 脚本 | ❌ |
| Auto.js | - | Android | ❌ | ✅ Accessibility | ❌ | ✅ JS 脚本 | ❌ |

**差异点**：
- 首个端侧大模型 + RPA 自动化 + MCP 协议融合方案
- 本地 LLM/VLM 自主决策操控手机，零网络请求
- 代码不干预判断原则：代码层只给抓手，所有决策由模型自主完成
- 11 个研究方向覆盖推理引擎优化、Agent 可靠性、RPA 容错、MCP 安全、系统级功耗优化

---

## 许可证

Apache License 2.0，与上游 [MNN](https://github.com/alibaba/MNN) 一致，商用友好。