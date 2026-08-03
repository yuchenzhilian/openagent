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

### 2. Agent 模式

- **ReAct 循环**：思考→工具调用→观察结果→下一步决策
- **40+ 内置工具**：计算器、日期、文本统计、单位换算、JSON 格式化、Web 搜索、HTTP 获取、HTML 转文本、随机数、UUID、Base64 编解码、颜色转换、计时器、天气、IP 查询、文本模板、分析规划、URL 编解码、正则测试、字符串大小写转换、Hex 编解码、哈希、CSV↔JSON 转换、Markdown 表格、密码生成、日期计算
- **智能意图检测**：自动识别用户意图，自动切换 Agent 模式
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

### 4. 云端 LLM 接入

- 支持任意 OpenAI 兼容端点（OpenAI / DeepSeek / 通义千问 / 豆包 / Groq / Ollama / Anthropic / 自定义）
- 纯 Dart HTTP 流式实现，不引入第三方 SDK
- 设置页「测试连接」按钮一键验证

### 5. MCP 协议支持

- 统一 Model Context Protocol 客户端抽象
- HTTP + Stdio 双传输
- 连接参数持久化，一键重连
- 支持 GitHub、浏览器、数据库等任意 MCP server

### 6. Skill 模块化系统

- 8+ 内置模块：android_rpa / builtin_math_time / knowledge_rag / longterm_memory / execute_plan / vision_analyze / mcp_gateway 等
- 模型自主选择启用/禁用，拓扑依赖自动排序
- 运行时 JSON 注册 Skill：callMcp / callTool / template / echo 四种 adapter，无需改代码
- 从轨迹创建 Skill：任务完成后可将工具调用序列保存为可复用 Skill
- 会话生命周期管理：状态保存/加载、bootstrap 一键恢复

### 7. 知识库管理

- 内置文档管理页面，添加/查看/删除 .txt 文档
- Agent 可自动检索知识库内容

### 8. 会话导出

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
│   ├─ agent_memory (KV 长期记忆)              │
│   ├─ MCP 协议层 (lib/agent/mcp)             │
│   │   ├─ McpClient (initialize/listTools/callTool)
│   │   ├─ HttpMcpTransport / StdioMcpTransport
│   │   ├─ McpRegistry (注册·查找·连接快照)
│   │   └─ MCP 持久化 (mcp_state_save/load)
│   └─ Skill 系统 (lib/agent/skills)
│       ├─ SkillManager (拓扑排序·remember·快照)
│       ├─ 8+ 内置 Skill
│       ├─ JsonSpecSkill (运行时 JSON 动态注册)
│       └─ 会话生命周期 (save/load·bootstrap)
├─────────────────────────────────────────────┤
│      Android RPA 自动化层 (Kotlin)           │
│   L1: AccessibilityService (UI 操控)        │
│   L2: Shizuku Shell (反射无 SDK 依赖)       │
│   L3: Root 预留                              │
│   MethodChannel ↔ Dart 工具桥接              │
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
│   │   ├── services/
│   │   │   ├── file_storage_service.dart
│   │   │   ├── model_download_service.dart
│   │   │   ├── schedule_service.dart     # 定时任务调度
│   │   │   └── android_automation_service.dart
│   │   └── repositories/
│   ├── features/
│   │   ├── chat/                       # 对话页
│   │   ├── model_market/               # 模型市场
│   │   ├── knowledge_base/             # 知识库
│   │   ├── automation/                 # 权限引导页
│   │   └── settings/                   # 设置页
│   └── agent/
│       ├── agent_runtime.dart          # ReAct 循环 + ToolResult/ToolErrorCode
│       ├── agent_prompt.dart           # System Prompt 模板（外置）
│       ├── agent_memory.dart           # KV 长期记忆
│       ├── android_tools.dart          # 入口（工厂函数）
│       ├── android_tools/              # 6 个子模块，按场景拆分
│       │   ├── android_tools_base.dart
│       │   ├── android_tools_compose.dart
│       │   ├── android_tools_system.dart
│       │   ├── android_tools_permission.dart
│       │   ├── android_tools_advanced.dart
│       │   └── android_tools_phone_manager.dart
│       ├── builtin_tools.dart          # 入口（工厂函数）
│       ├── builtin_tools/              # 3 个子模块，按类别拆分
│       │   ├── builtin_math_time.dart
│       │   ├── builtin_data_utils.dart
│       │   └── builtin_assistant.dart
│       ├── mcp/                        # MCP 协议层
│       └── skills/                     # Skill 系统
├── android/.../automation/             # Android 原生自动化层
│   ├── OpenAgentAccessibilityService    # 无障碍服务（含安全模式手势拦截）
│   ├── OpenAgentNotificationListener    # 通知监听服务
│   ├── OpenAgentForegroundService       # 前台服务（保活，START_STICKY）
│   ├── AutomationChannel               # MethodChannel 桥接
│   └── ShizukuShell                     # Shizuku 反射 shell
├── packages/mnn_llm/                   # FFI 插件
│   ├── lib/src/                        # Dart Session + FFI 绑定
│   ├── src/                            # C API wrapper
│   ├── android/                        # Android 构建配置
│   └── ios/                            # iOS 构建配置
├── test/                               # 单元测试
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

---

## 许可证

Apache License 2.0，与上游 [MNN](https://github.com/alibaba/MNN) 一致，商用友好。