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

- 🚀 **纯端侧推理**：Qwen3 / DeepSeek 等模型本地运行，骁龙 8 Gen 3 上 15+ tokens/s
- 🔒 **隐私优先**：无网络请求，对话内容永不上传
- 📱 **跨平台**：一套 Flutter 代码同时支持 Android 与 iOS
- 🎨 **多模态**：文本对话 + 图像理解 + 语音输入（基于 Qwen2.5-Omni）
- 🧩 **模型市场**：按需下载/切换/管理多个量化模型
- ⚙️ **可调参**：temperature / top_k / top_p / max_tokens / System Prompt
- 📊 **性能指标**：实时显示 tokens/sec、生成耗时、TTFT 等推理性能数据
- 🤖 **Agent 模式**：ReAct 循环 + 30+ 内置工具（Web搜索/HTTP获取/HTML转文本/计算器/日期/文本统计/单位换算/知识库搜索RAG/JSON格式化/随机数/UUID/Base64编解码/颜色转换/天气/IP查询/文本模板/计时器/分析规划/URL编解码/正则测试/字符串大小写转换/Hex二进制编解码/哈希/CSV↔JSON/Markdown表格/密码生成/日期计算），支持多步推理 + 智能意图检测自动开启 Agent 模式 + 工具调用统计（耗时/成功失败计数）
- ☁️ **云端 LLM 接入（可选）**：通过 URL + API Key + Model ID 接入任意 OpenAI 兼容端点（OpenAI / DeepSeek / 通义千问 DashScope / 豆包 / Groq / Ollama 本地代理 / Anthropic Claude / 自定义），纯 Dart HTTP 流式，不引入第三方 SDK。设置页带「测试连接」按钮一键验证
- 🌐 **MCP 协议支持**：统一 Model Context Protocol 客户端抽象（HTTP + Stdio 双传输），可连接任意 MCP server 扩展外部工具链（GitHub、浏览器、数据库等），连接参数可持久化一键重连
- 🧩 **Skill 模块化系统**：内置 android_rpa/builtin_math_time/knowledge_rag/longterm_memory/execute_plan/vision_analyze/mcp_gateway 8+ 独立模块，模型自主选择启用/禁用，拓扑依赖自动排序
- ⚡ **运行时注册 JSON Skill**：无需改 Dart 代码，传一段 JSON 即可注册全新复合 Skill（callMcp/callTool/template/echo 四种 adapter 自由组合，支持参数模板重映射），立即 skill_enable 生效
- 🔄 **从轨迹创建 Skill**：Agent 完成多步任务后，可将工具调用序列一键保存为可复用 Skill（skill_create_from_trace），下次 skill_enable 即可重放
- 💾 **会话生命周期管理**：skill_state_save/load、remember_enabled 记住启用打标、skills_manifest/skill_tools_manifest 诊断清单、session_bootstrap 一键恢复（MCP 连接 + Skill + 记忆前缀），跨会话复现工作环境
- 📱 **Android RPA 自动化**：Agent 可操控手机上的任意 App（微信/抖音/小红书/QQ/B站/支付宝/游戏等），三层权限架构（Accessibility + Shizuku Shell + Root 预留）
- 🔧 **50+ 自动化工具**：原子工具（点击/滑动/输入/截图/UI Dump）+ 20+ 组合宏脚本（发微信/刷抖音/点赞小红书/发B站弹幕/游戏VLM自动操作）+ 多步执行编排 + KV 长期记忆
- 🧠 **VLM 视觉决策**：遇到纯图像界面（游戏/Feed流/Canvas），截图→Omni 多模态模型分析→自主决定操作坐标
- 🔐 **不干扰模型判断**：代码层只提供原始数据和原子抓手，MCP 连哪个 server、Skill 启哪个、工具怎么编排全部由 (LLM + VLM) 自主完成。规则 N 指导模型根据输入自动启用相关 Skill，规则 O 指导优先使用原子工具 + VLM 自主决策，规则 P 指导防高风险应用检测
- 🧠 **智能意图检测**：输入框自动识别用户意图——检测到"搜索/查一下"自动开启 Agent 模式，检测到"打开微信/点击"提示开启自动化，减少手动开关操作
- 🛡️ **防高风险应用检测**：accesibility_service_config.xml 包名白名单限制（仅监控社交/工具类 App，银行/支付不触发无障碍服务）+ 3 个防检测工具（android_anti_detection_check/safe_mode/banking_list）+ 权限引导页防检测教程 + System Prompt 规则 P
- 📚 **知识库管理**：内置文档管理页面，添加/查看/删除 .txt 文档，Agent 可自动检索
- 💾 **会话导出**：一键导出对话记录为文本文件，便于备份和分享

> Android Release APK 已成功构建，57 项单元测试通过，GitHub Actions CI/CD 已配置。真机验证进行中。

---

## 架构

```
┌─────────────────────────────────────────────┐
│            Flutter UI (Dart)                │
│   对话页 · 模型市场 · 设置 · Agent(ReAct)     │
│   chat_page (MCP + Skill 运行时绑定)         │
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
│   ├─ System Prompt 规则 A~R (K/L/M: MCP+Skill+Bootstrap, N: 智能Skill建议, O: 自主决策优先, P: 防高风险应用检测, Q: 长期记忆优先, R: 启发式任务分解)
│   ├─ agent_runtime (ReAct 循环 + 工具注册表)
│   ├─ agent_memory (KV 长期记忆)
│   ├─ MCP 协议层 (lib/agent/mcp)
│   │   ├─ McpClient (initialize/listTools/callTool)
│   │   ├─ HttpMcpTransport  /  StdioMcpTransport
│   │   ├─ McpRegistry (注册·查找·连接快照)
│   │   └─ MCP 持久化 (mcp_state_save/load)
│   └─ Skill 系统 (lib/agent/skills)
│       ├─ SkillManager (拓扑排序·remember_enabled·快照/恢复)
│       ├─ 8+ 内置 Skill (RPA/数学时间/KnowledgeRAG/记忆/计划/Vision/MCP网关…)
│       ├─ JsonSpecSkill (运行时 JSON 动态注册: callMcp/callTool/template/echo)
│       └─ 会话生命周期 (save/load·diagnostic manifest·session_bootstrap 一键恢复)
├─────────────────────────────────────────────┤
│      Android RPA 自动化层 (Kotlin)           │
│   L1: AccessibilityService (UI 操控)        │
│   L2: Shizuku Shell (反射无 SDK 依赖)       │
│   L3: Root 预留                              │
│   MethodChannel ↔ Dart 工具桥接              │
└─────────────────────────────────────────────┘
```

**为何用 FFI 而非 Platform Channel？** 流式生成每秒触发数十次 token 回调，dart:ffi 的同步开销远低于 Platform Channel 的异步消息，且能直接用 `NativeCallable` 把 native 回调转成 Dart `Stream`。

**MCP + Skill 架构设计原则（代码不干扰模型判断）**：代码层只暴露原子抓手（MCP 连接元工具、Skill enable/disable、JSON 注册、持久化保存/加载），**不做任何业务决策**——连哪个 MCP server、启哪个 Skill、注册什么复合工具、记不记住下次启，全都留给 LLM+VLM 自主判断。

---

## 性能基线

实测数据（Q4 量化，参考 MNN 官方与社区基准）：

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
- Android Studio + CMake 3.22+（Android 开发，NDK 可选）
- Xcode 15+（iOS 开发，需 macOS）
- 一台 arm64 Android 真机（模拟器不支持 OpenCL/Metal 加速）

> **Windows 中文用户名路径问题**：如果 Windows 用户名包含中文字符（如 `C:\Users\张三\`），NDK 的 C++ 编译会失败。解决方案：创建一个 junction 指向 Android SDK，然后在 `android/local.properties` 中使用 junction 路径：
> ```powershell
> New-Item -ItemType Junction -Path "D:\AndroidSDK" -Target "C:\Users\你的用户名\AppData\Local\Android\Sdk"
> ```
> 然后设置 `sdk.dir=D:\\AndroidSDK`。项目提供了 `tools/flutter.ps1` 辅助脚本自动配置这些环境变量。

### 1. 克隆并初始化

```bash
git clone https://github.com/your-name/openagent.git
cd openagent
flutter pub get
```

### 2. 下载 MNN 预编译库（首次）

脚本自动从 GitHub Releases 下载 MNN 3.6.1 预编译 .so 和头文件，无需 NDK：

```bash
cd packages/mnn_llm
bash scripts/download_mnn_prebuilt.sh   # 下载到 third_party/mnn/
```

### 3. 运行验证 App

> **提示**：如果 `flutter` 命令挂起，可使用项目提供的 `tools/flutter.ps1` 辅助脚本（自动设置 JAVA_HOME 和 Android SDK 路径）：
> ```powershell
> powershell -ExecutionPolicy Bypass -File tools\flutter.ps1 analyze   # 代码分析
> powershell -ExecutionPolicy Bypass -File tools\flutter.ps1 test      # 运行测试
> powershell -ExecutionPolicy Bypass -File tools\flutter.ps1 build apk --release  # 构建 APK
> ```

**方式一：App 内模型市场下载（推荐）**

App 内置模型市场，支持从 ModelScope 直接下载量化模型：

```bash
flutter run --release
# 打开 App → 底部导航「模型」→ 选择 Qwen3-0.6B-MNN → 下载
# 下载完成后回到「对话」页即可开始聊天
```

**方式二：adb push 预下载模型**

```bash
# 下载模型（约 430MB）
# 从 https://modelscope.cn/models/MNN/Qwen3-0.6B-MNN 下载

# 推送到 App 外部存储（无需 root）
adb push Qwen3-0.6B-MNN /sdcard/Android/data/com.openagent.openagent/files/models/Qwen3-0.6B-MNN

# 运行
flutter run --release
# 打开 App → 底部导航「模型」→ 点击已下载的模型激活
# 回到「对话」页即可开始聊天
```

---

## 项目结构

```
openagent/
├── lib/                        # Flutter App 主工程
│   ├── main.dart               # 入口 (ProviderScope)
│   ├── app.dart                # MaterialApp + GoRouter ShellRoute
│   ├── data/
│   │   ├── models/models.dart          # ChatMessage/Session/ModelInfo/Config
│   │   ├── services/
│   │   │   ├── file_storage_service.dart    # 文件存储
│   │   │   ├── model_download_service.dart  # 模型下载（字节级进度+原子下载）
│   │   │   └── android_automation_service.dart  # Android 自动化服务封装
│   │   └── repositories/               # Chat + Model 仓储
│   ├── features/
│   │   ├── chat/                       # 对话页 (流式+Markdown+多会话+Agent模式+VLM视觉分析)
│   │   ├── model_market/               # 模型市场 (下载/切换/删除+进度+取消)
│   │   ├── knowledge_base/             # 知识库管理 (添加/查看/删除文档)
│   │   └── settings/                   # 设置 (采样参数+System Prompt+权限引导)
│   └── agent/
│       ├── agent_runtime.dart          # ReAct 循环 + 工具调用解析 + System Prompt 规则 A~O
│       ├── android_tools.dart          # 50+ Android RPA 工具定义
│       ├── builtin_tools.dart          # 30+ 通用内置工具（搜索/HTTP/计算/日期/文本/随机数/UUID/Base64/颜色/天气/IP/模板/计时器/分析规划/URL编解码/正则/大小写转换/Hex编解码/哈希/CSV转换/表格/密码生成/日期计算）
│       ├── agent_memory.dart           # KV 长期记忆（跨 session/plan 保留）
│       ├── mcp/
│       │   ├── mcp_client.dart         # McpClient + McpTransport(HTTP/Stdio) + McpRegistry
│       │   └── mcp_persistence.dart    # mcp_state_save/load 连接持久化
│       └── skills/
│           ├── skills.dart             # Skill 接口 + SkillManager (拓扑/remember/snapshot/restore) + JsonSpecSkill
│           ├── skills_extra.dart       # KnowledgeRag/LongTermMemory/ExecutePlan/Vision + skill_register_json 工厂
│           └── session_lifecycle.dart  # skill_state_save/load + remember + manifest + session_bootstrap
├── android/app/src/main/kotlin/.../automation/  # Android 原生自动化层
│   ├── AutomationChannel.kt            # MethodChannel 桥接（30+ 方法）
│   ├── OpenAgentAccessibilityService.kt  # L1 Accessibility（点击/滑动/输入/手势/dump）
│   ├── OpenAgentNotificationListener.kt  # L1.5 通知监听（200条环形缓存）
│   └── ShizukuShell.kt                 # L2 Shizuku 反射 Shell（无 SDK 依赖）
├── android/app/src/main/res/xml/accessibility_service_config.xml
├── packages/mnn_llm/           # FFI 插件（可独立复用）
│   ├── lib/                    # mnn_llm.dart + 手写绑定 + Session
│   │   └── src/
│   │       ├── mnn_llm_session.dart    # 文本对话 Session (流式)
│   │       ├── mnn_omni_session.dart   # 多模态 Session (图像/语音)
│   │       └── mnn_llm_bindings.dart   # 手写 FFI 绑定
│   ├── src/                    # C/C++ C API wrapper (extern "C")
│   │   ├── mnn_llm_capi.h              # 文本 + Omni 多模态 C API
│   │   └── mnn_llm_capi.cpp            # stb_image 解码 + MultimodalPrompt
│   ├── android/                # build.gradle + CMake + jniLibs
│   ├── ios/mnn_llm.podspec     # CocoaPods 配置
│   └── scripts/                # MNN 编译脚本 (Android + iOS)
├── test/                       # 57 项单元测试（下载服务+Agent+Widget）
├── tools/                      # flutter.ps1 + model_list.json + 开发方案
├── .github/workflows/          # GitHub Actions CI/CD（analyze+test+build APK）
└── .trae/documents/            # 开发方案文档
```

---

## 路线图

- [x] **阶段 0-2** 工程脚手架 + C API wrapper + FFI 绑定 + Android/iOS 构建配置
- [x] **阶段 3** Android Release APK 构建成功（完整构建链验证通过）
- [x] **阶段 4** 完整 UI 骨架：对话页 + 模型市场 + 设置 + 数据层
- [x] **阶段 5 (代码)** 多模态 C API + MnnOmniSession + stb_image 解码
- [x] **阶段 6** 开源打磨：CI + LICENSE + 模型转换文档
- [x] **阶段 7** Agent ReAct 循环 + 工具调用解析 + 内置工具(计算器/日期/文本统计/单位换算/知识库搜索RAG/JSON格式化)
- [x] **阶段 8** 模型下载服务：字节级进度 + 原子下载(.part) + 取消 + 中文错误 + 57 项单元测试
- [x] **阶段 9** Android RPA 三层权限架构：L1 Accessibility + L2 Shizuku Shell(反射无 SDK) + L3 Root 预留
- [x] **阶段 10** 50+ 自动化工具：原子 ×19 + 开放通用 ×5 + 开放底层 ×10 + 补充原子 ×5 + 多步编排 + KV 记忆 + 系统原子 ×6 + 权限工具 ×2 + 硬件/通话/相册/系统设置 ×5
- [x] **阶段 11** 20+ 组合宏脚本：微信 ×4 + 抖音 ×5 + 小红书 ×3 + QQ ×1 + B站 ×3 + 系统 ×4 + 支付宝 ×2 + 游戏 VLM AutoPilot ×1
- [x] **阶段 12** VLM 视觉决策：截图 → Omni 多模态模型 → 自主坐标判断 → 操作执行循环
- [x] **阶段 13** System Prompt 规则 A~J：代码层不干扰模型判断，所有决策由 LLM+VLM 自主
- [x] **阶段 14** GitHub Actions CI/CD + AndroidManifest 22+ 权限声明 + 20+ queries 包名可见
- [x] **阶段 15** MCP 协议支持：McpClient 抽象 + HttpMcpTransport/StdioMcpTransport + McpRegistry + mcp_state_save/load 连接持久化
- [x] **阶段 16** Skill 模块化系统：8+ 内置 Skill + SkillManager（拓扑排序 / remember_enabled / snapshotState / restoreJsonSkills）+ 运行时 JSON 动态注册 JsonSpecSkill（callMcp/callTool/template/echo 4 adapter）
- [x] **阶段 17** 会话生命周期管理：skill_state_save/load + skill_remember_enabled + skills_manifest/skill_tools_manifest 诊断 + session_bootstrap 一键恢复（MCP 连接 + JSON Skill + remember_enabled 自动按拓扑启用）
- [x] **阶段 18** System Prompt 规则 K/L/M：规范 MCP 连接流程、Skill 启用策略、会话启动 bootstrap 流程
- [x] **阶段 19** 增强 Agent 能力：16 个新内置工具（Web搜索/HTTP获取/HTML转文本/随机数/UUID/Base64编解码/颜色转换/计时器/天气/IP查询/文本模板/分析规划）+ System Prompt 规则 N（智能 Skill 建议）和 O（自主决策优先）+ skill_create_from_trace 从轨迹创建 Skill + 智能意图检测自动模式切换
- [x] **阶段 20** 防高风险应用检测：accessibility_service_config.xml 包名白名单过滤 + 3 个防检测工具 + 权限引导页防检测教程 + System Prompt 规则 P（防高风险应用检测）
- [x] **阶段 21** 更多内置实用工具 + 增强意图检测：URL编解码/正则测试/字符串大小写转换/Hex二进制编解码 + 防检测工具始终可用 + 意图检测新增代码/开发类关键词和更多自动化关键词
- [x] **阶段 22** 哈希+数据工具+长期记忆规则：hash_text(MD5)/text_stats_advanced/csv_json_convert/markdown_table/password_generator/date_calculator + System Prompt 规则 Q（长期记忆优先）和 R（启发式任务分解）+ chat_page 工具调用统计（耗时/成功失败）
- [x] **阶段 23** 云端 LLM 接入（可选，作为本地模型的替代）：CloudLlmSession（OpenAI 兼容流式 SSE + Anthropic 适配 + Ollama 本地代理 + 7 个内置预设）+ ModelSource/CouldModelConfig + 设置页「云端 LLM」分区（开关/Provider/Base URL/API Key/Model ID/System Prompt/测试连接）+ chat_page 动态 session 切换
- [x] **阶段 24** 手机权限深度增强：通知深度控制（dismiss/snooze/reply by key）+ 录制回放框架（record/stop/list macros）+ AppOps 细粒度权限（get/set GET_USAGE_STATS/SYSTEM_ALERT_WINDOW/READ_CLIPBOARD/POST_NOTIFICATIONS 等）+ 浮窗/悬浮球自动化面板
- [x] **阶段 25** 系统权限深度强化：VLM 游戏自动循环失败恢复（3 轮卡住→back/scroll/home 恢复策略）+ 进度持久化每 5 轮保存到文件 + 规则 S（账号运营/游戏自动化自主决策：多天计划→进度保存→权限弹窗自动处理→卡住恢复）+ 权限引导页一键自动授权（Shizuku 自动启用无障碍/通知监听/WRITE_SECURE_SETTINGS/DUMP）+ notificationListenerGranted 状态检测
- [x] **阶段 26** 社交 App 组合宏（辅助 VLM 多模态模型主导）：小红书发帖/私信 + 抖音发作品 + 微信发图片朋友圈
- [ ] **真机验证** Android 手机冒烟测试：权限引导 → 开微信 → 点文字 → 输入中文 → 滑抖音 → UI dump → 端到端微信发消息
- [ ] **iOS 适配**
- [ ] **更多能力** AppOps 细粒度 / VPN / NFC / 蓝牙配对 / 自定义规则引擎

---

## 与同类项目对比

| 项目 | 引擎 | 平台 | UI 技术 | 多模态 | RPA/自动化 | MCP 协议 | 动态 Skill / 复合工具注册 | 会话持久化一键恢复 | 开源 |
|---|---|---|---|---|---|---|---|---|---|
| **OpenAgent** | MNN-LLM | Android + iOS | Flutter | ✅ Qwen2.5-Omni | ✅ 50+ 工具 | ✅ HTTP + Stdio 双传输（带持久化） | ✅ JSON 运行时注册 Skill（4 种 adapter），拓扑依赖排序 | ✅ session_bootstrap（MCP+Skill+记忆） | ✅ Apache 2.0 |
| MNN Chat（官方） | MNN-LLM | Android + iOS | 原生 Kotlin/Swift | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| llama.cpp | ggml | 全平台 | 无（需自建 UI） | 部分 | ❌ | 部分（示例） | ❌ | ❌ | ✅ |
| mnn.rn | MNN-LLM | 仅 Android | React Native | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Tasker | - | Android | 原生 | ❌ | ✅ 插件生态 | ❌ | ✅ TaskerNet 脚本（非代码化） | ✅ 配置文件（用户手动） | ❌ 闭源 |
| Auto.js | - | Android | JavaScript | ❌ | ✅ Accessibility | ❌ | ✅ JS 脚本（需写代码） | ❌ | ❌ 闭源 |

OpenAgent 的差异点：
- **首个端侧大模型 + RPA 自动化 + MCP 协议 融合方案**——本地 LLM/VLM 自主决策操控手机，零网络请求保护隐私，同时通过 MCP 协议无限扩展外部工具（GitHub/浏览器/数据库）。
- **Skill + JSON 动态注册双轨制**：内置 Skill 覆盖常用能力；想组合新能力时 LLM 自己写一段 JSON 就注册一个全新复合 Skill（callMcp/callTool 参数模板重映射），无需改代码。
- **会话生命周期闭环**：记标 remember_enabled → 保存 JSON Skill + MCP 连接 → session_bootstrap 一键恢复（拓扑依赖自动按序启用），跨会话复现工作环境，真正做到"关了也记住"。
- **代码不干扰判断原则**：代码层只给抓手，MCP 连哪个、Skill 启哪个、注册什么复合工具、记不记住，全由 LLM+VLM 自己判断。
- 一套 Flutter 代码双端运行，FFI 插件可独立复用。

---

## 贡献

欢迎 Issue 和 PR。

## 许可证

Apache License 2.0，与上游 [MNN](https://github.com/alibaba/MNN) 一致，商用友好。
