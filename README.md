<div align="center">

# OpenAgent

**On-Device LLM App · MNN-LLM × Flutter**

Pure Local Inference · Multimodal Interaction · Cross-Platform · Privacy-First

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-green.svg)](#)
[![Engine](https://img.shields.io/badge/engine-MNN--LLM%203.6.1-orange.svg)](#)
[![Android CI](https://github.com/yuchenzhilian/openagent/actions/workflows/build_android.yml/badge.svg)](https://github.com/yuchenzhilian/openagent/actions/workflows/build_android.yml)
[![iOS CI](https://github.com/yuchenzhilian/openagent/actions/workflows/build_ios.yml/badge.svg)](https://github.com/yuchenzhilian/openagent/actions/workflows/build_ios.yml)

English (current) | [简体中文](README.zh.md)

</div>

---

## Introduction

OpenAgent is an open-source large model application that runs locally on mobile phones, built on the Alibaba [MNN-LLM](https://github.com/alibaba/MNN) inference engine and [Flutter](https://flutter.dev). All inference is completed on-device, with no network connection required and conversation data never leaving the phone.

- **Pure On-Device Inference**: Qwen3 / DeepSeek and other models run locally
- **Privacy-First**: No network requests, conversation content is never uploaded
- **Cross-Platform**: A single Flutter codebase supports both Android and iOS
- **Multimodal**: Text chat + image understanding + voice input (Qwen2.5-Omni)
- **Agent Mode**: ReAct loop + 190+ tools (170+ Android + 9 iOS + 8 WebView + 25+ built-in), capable of autonomously operating the phone
- **Android RPA Automation**: Three-tier permission system, replacing manual phone operation
- **iOS Shortcuts Integration**: Agent registers Siri voice shortcuts, triggering system-level operations via URL scheme
- **iOS Live Activities Keep-Alive**: Agent displays real-time status on lock screen / Dynamic Island during runtime (iOS 16.1+)
- **Keep-Alive & Hiding**: Foreground service keep-alive + safe mode + Shizuku hiding features + anti-detection popup strategy
- **Cloud LLM Access (Optional)**: Supports OpenAI / Anthropic / Tongyi Qianwen / Doubao / Groq / Ollama, etc.
- **MCP Protocol Support**: HTTP + Stdio dual transport, can connect to any MCP server
- **Skill Modular System**: 8+ built-in modules + JSON runtime registration

---

## Core Features

### 1. Local LLM Inference

- Supports Qwen3 series (0.6B / 1.7B / 4B) and Qwen2.5-Omni (7B multimodal)
- Built-in model marketplace, download quantized models directly within the app
- Adjustable sampling parameters: temperature / top_k / top_p / max_tokens / System Prompt
- Real-time display of tokens/sec, generation time, TTFT, and other performance metrics
- **Adaptive Inference Scheduling**: Automatically switches inference profiles based on device battery, temperature, and available memory (high-performance / normal / power-saving / thermal-throttled / ultra-lightweight)
- **Device Status Monitoring**: Real-time monitoring of battery, temperature, memory, CPU frequency, with 30-second polling event-driven updates
- **Low-End Device Adaptation**: Automatically detects device memory, <4GB recommends smallest model + mmap memory mode + reduced KV Cache window
- **First-Launch Auto Model Recommendation**: Automatically selects the most suitable model based on device RAM (8GB+->4B, 4GB+->1.7B, <4GB->0.6B)
- **GPU Acceleration**: Automatically detects Adreno/Mali GPU and enables OpenCL backend, boosting inference speed by 3-5x
- **Model Warmup**: Automatically executes dummy inference after loading to trigger kernel compilation and OpenCL cache generation, reducing first-query TTFA by 50%+
- **Dynamic Backend Configuration**: Dynamically sets thread count (matching big cores), precision, memory mode, and sampler based on device capabilities
- **Sampling Optimization**: Default topK=20 (reduces sampling computation), mixed sampler, repetition_penalty=1.05

### 2. Agent Mode

- **ReAct Loop**: Think -> tool call -> observe result -> next-step decision
- **40+ Built-in Tools**: Calculator, date, text statistics, unit conversion, JSON formatter, Web search, HTTP fetch, HTML to text, random number, UUID, Base64 encode/decode, color conversion, timer, weather, IP lookup, text template, analysis planning, URL encode/decode, regex testing, string case conversion, Hex encode/decode, hash, CSV<->JSON conversion, Markdown table, password generator, date calculation
- **Constrained Decoding**: Forces valid JSON output in tool-call mode, significantly reducing formatting errors from small models
- **Intent Routing Classifier**: 7-category intent recognition (math/date/knowledge/Web/Android automation/complex task/chitchat), high-confidence direct tool invocation skips ReAct
- **Tool Schema Validation**: Checks required parameters, types, enum values, and ranges before execution, rejecting invalid parameters early
- **Self-Correction Retry Loop**: Automatic exponential backoff retry for network/timeout/resource-contention errors (up to 2 times)
- **KV Cache Management**: H2O heavy-hitter retention policy + sliding window + summary cache, keeping long-conversation memory controllable
- **Tool Call Statistics**: Real-time display of each tool call's duration and success/failure count
- **KV Long-Term Memory**: Cross-session persistence, agent_memory_set/get interface
- **Scheduled Task Scheduling**: Supports three formats: daily:HH:MM / interval:seconds / cron, persisted to local file
- **Smart Notes/Reminders**: Note creation/search/categorization, todo management (priority/mark complete/clear)
- **Daily Briefing**: Summarizes todo items, today's notes, and scheduled task status
- **Quick Assistant**: Calculation, unit conversion, time difference, countdown, random number

### 3. Android RPA Automation

Three-tier permission architecture, the Agent can operate the phone like a human:

| Tier | Capability | Implementation |
|---|---|---|
| **L1** | Screen text recognition, click, swipe, input | AccessibilityService |
| **L2** | Precise coordinate operations, system-level commands, screenshots | Shizuku Shell (no SDK dependency) |
| **L3** | Reserved (Root devices) | - |

**170+ automation tools**, covering all scenarios:

- **Atomic Operations**: Click text/coordinate/ID, swipe, input, key press, screenshot, UI dump, long press, gesture, clipboard
- **Social App Macros**: WeChat send message/mass send/scan QR/Moments like/post image/text Moments, Douyin like/comment/follow/search/post work/batch swipe, Xiaohongshu search/like/follow/post/private message, Bilibili search/post danmaku
- **Game Automation**: VLM autopilot loop (screenshot -> analyze -> operate -> verify -> recover), supports failure recovery (3 rounds stuck -> auto rollback)
- **System Settings**: WiFi, Bluetooth, volume, alarm, SMS, dial, camera
- **App Management**: Open/install/uninstall/disable/clear cache, view permission list/usage ranking
- **File Management**: Storage analysis, large file scan, categorize by type, clean temp files/download directory
- **Deep Clean**: Quick clean, deep clean (all cache + temp files + thumbnails + empty directories + uninstall residuals)
- **Notification Management**: Get notification list, cancel by key, snooze, quick reply
- **Notification Listening**: Real-time notification listening, 200-entry ring buffer
- **Record & Replay**: Record operation sequences (screenrecord + touch events), save/replay
- **Permission Management**: AppOps fine-grained permission get/set, runtime permission request guidance, panoramic permission self-check
- **Anti-Detection**: Check if current foreground app is high-risk, safe mode (Kotlin-side actual gesture interception), 32+ bank/payment/security app blocklist
- **Keep-Alive**: System power-saving whitelist + foreground service (OpenAgentForegroundService, START_STICKY auto-restart)
- **Hiding**: Shizuku hide icon/process + disable accessibility service + safe mode linkage
- **Virtual Location**: Mock GPS set/clear/status check
- **VLM Enhancement**: Screen change detection, screenshot fingerprint hash, region crop analysis
- **VLM Anchorless UI Operation**: Visual Grounding engine + cross-resolution adaptation + 4-level hybrid localization (Accessibility -> VLM -> OCR -> coordinate probing)
- **Operation Chain Fault Tolerance**: Checkpoint system + App state machine + 5-category exception detection and recovery (popup/navigation failure/missing element/timeout/unknown state)

### 4. iOS Automation and Keep-Alive

Since iOS does not have AccessibilityService, RPA capabilities are limited, but are supplemented through the following:

**Siri Shortcuts Integration**:
- Agent can register voice shortcuts (`ios_shortcut_donate`), users trigger Agent tasks via Siri
- Trigger system-level operations via URL scheme (make phone call `tel:`, send SMS `sms:`, open maps `maps:`)
- Open third-party apps (WeChat `weixin://`, Douyin `snssdk1128://`, Alipay `alipay://`, etc.)
- Bidirectional communication: When Siri triggers a shortcut, AppDelegate calls back to the Agent via MethodChannel

**Live Activities Keep-Alive (iOS 16.1+)**:
- Agent automatically starts a Live Activity when it begins running, displaying status on lock screen and Dynamic Island
- Real-time status text update on each tool call ("Thinking..." / "Executing tool: xxx")
- Live Activity automatically ends when Agent completes or exits
- Implemented based on ActivityKit + WidgetKit

**9 iOS-Exclusive Tools**:

| Tool | Description |
|---|---|
| `ios_shortcut_donate` | Register Siri voice shortcut |
| `ios_shortcut_list` | List registered shortcuts |
| `ios_shortcut_trigger` | Trigger system operation via URL scheme |
| `ios_shortcut_delete` | Delete shortcut |
| `ios_open_url` | Open URL (browser/Deeplink) |
| `ios_open_app` | Open third-party app via URL scheme |
| `ios_live_activity_start` | Start Live Activity keep-alive |
| `ios_live_activity_update` | Update Live Activity status |
| `ios_live_activity_end` | End Live Activity |

**Skill Modules**: `ios_shortcuts` + `ios_live_activity`, model enables on demand, automatically no-op on Android.

**In-App WebView Automation (Cross-Platform RPA Alternative)**:

On iOS, unlike Android, native apps cannot be controlled via AccessibilityService. As an alternative, OpenAgent provides web-based automation capabilities through a built-in WebView, available on both Android and iOS:

- `web_navigate` - Navigate to URL in built-in WebView (WeChat web, Douyin H5, etc.)
- `web_execute_js` - Execute arbitrary JavaScript code to manipulate DOM
- `web_get_page_text` - Extract page text content
- `web_click_element` - Click element via CSS selector
- `web_fill_form` - Fill form input fields
- `web_get_url` - Get current page URL
- `web_screenshot` - Screenshot the WebView (can be used for VLM analysis)
- `web_wait_for_element` - Wait for element to appear (with timeout)

**iOS RPA Implementation Path**:

| Approach | Applicable Scenario | App Store Restrictions |
|---|---|---|
| **Siri Shortcuts + URL Scheme** | System-level operations (dial/SMS/maps) + open third-party apps | App Store available |
| **In-App WebView Automation** | Web WeChat/Douyin/H5 app control | App Store available |
| **Live Activities Keep-Alive** | Agent runtime status persistent on lock screen/Dynamic Island | iOS 16.1+, App Store available |
| **XCTest UI Testing Framework** | Deep native app control | TestFlight / Enterprise signing only, cannot be on App Store |

> **App Store Recommendation**: The App Store version should only use the Shortcuts + In-App automation path. TestFlight / Enterprise builds can additionally enable XCTest UI capabilities, but must be clearly annotated.

**iOS Capability Boundary (Clearly Annotated)**:

| Capability | Android | iOS (App Store) | iOS (TestFlight/Enterprise) | Description |
|---|---|---|---|---|
| Accessibility Service RPA | ✅ Fully supported | ❌ Not available | ❌ Not available | iOS has no AccessibilityService equivalent |
| Screen click/swipe/input | ✅ AccessibilityService | ❌ | ⚠️ XCTest UI | XCTest limited to developer mode |
| UI Hierarchy Dump | ✅ | ❌ | ⚠️ XCTest UI | |
| Screenshot Analysis | ✅ MediaProjection | ✅ ReplayKit | ✅ ReplayKit | iOS requires user screen recording authorization |
| App Launch | ✅ Intent + gshell | ✅ URL Scheme | ✅ URL Scheme | iOS limited to apps with registered schemes |
| System Operations (dial/SMS) | ✅ Intent | ✅ URL Scheme | ✅ URL Scheme | `tel:` `sms:` `maps:` |
| Siri Voice Shortcuts | ❌ | ✅ App Intents | ✅ App Intents | iOS 16+ |
| Live Activities Keep-Alive | ❌ | ✅ ActivityKit | ✅ ActivityKit | iOS 16.1+, lock screen/Dynamic Island |
| In-App WebView Automation | ✅ | ✅ | ✅ | Cross-platform, web app control |
| File System Access | ✅ Full | ⚠️ Sandbox restricted | ⚠️ Sandbox restricted | iOS App Sandbox |
| Shell Command Execution | ✅ Shizuku/Root | ❌ | ❌ | iOS not allowed |
| Notification Listening | ✅ NotificationListenerService | ❌ | ❌ | iOS has no equivalent API |
| Call Log/Contacts | ✅ ContentProvider | ⚠️ Limited Contacts | ⚠️ Limited Contacts | iOS limited to contacts read |
| Sensor Access | ✅ Full | ⚠️ Limited | ⚠️ Limited | iOS background sensors restricted |
| Foreground Service Keep-Alive | ✅ Foreground Service | ❌ | ❌ | iOS has no foreground service, relies on Live Activity instead |
| Anti-Detection/Hiding | ✅ Shizuku hiding | ❌ | ❌ | iOS not needed (sandbox isolation) |

> **Summary**: iOS RPA capability is approximately 30% of Android, primarily relying on three paths: Shortcuts + URL Scheme + WebView. The core limitation is the inability to control other native apps' UI.

**Cross-Platform #ifdef Governance**:

Platform differences are managed through a unified abstraction layer, not scattered in UI code:
- `PlatformAutomationService` interface: Unified `isSupported` gate contract
- `PlatformToolFactory` interface: Android/iOS factories each implement, unified registration entry `createPlatformTools()`
- `ToolFactoryContext`: Consolidates factory parameters (service/visionAnalyze/memoryBackend, etc.)
- Graceful degradation: Unsupported platforms register degraded stub tools, returning "This feature is only available on XX platform" prompt

### 5. Cloud LLM Access

- Supports any OpenAI-compatible endpoint (OpenAI / DeepSeek / Tongyi Qianwen / Doubao / Groq / Ollama / Anthropic / custom)
- Pure Dart HTTP streaming implementation, no third-party SDK introduced
- Settings page "Test Connection" button for one-click verification

### 6. MCP Protocol Support

- Unified Model Context Protocol client abstraction
- HTTP + Stdio dual transport
- Connection parameter persistence, one-click reconnect
- Supports any MCP server such as GitHub, browser, database, etc.
- **Capability-based Permission Model**: Each MCP Server can only access its declared tool subset
- **Stdio Sandbox Process Isolation**: Restricts file system access and execution time
- **mDNS LAN Discovery**: Automatically discovers MCP Servers in non-public-network environments

### 7. Skill Modular System

- 8+ built-in modules: android_rpa / ios_shortcuts / ios_live_activity / builtin_math_time / knowledge_rag / longterm_memory / execute_plan / vision_analyze / mcp_gateway, etc.
- Model autonomously selects enable/disable, topological dependency auto-sorting
- Runtime JSON Skill registration: callMcp / callTool / template / echo four adapters, no code changes needed
- Create Skill from trajectory: After task completion, tool call sequence can be saved as a reusable Skill
- **Skill Auto-Synthesis**: Extracts parameterizable templates from multiple similar trajectories via LCS sequence alignment
- **Skill Version Evolution**: Version management + success rate tracking + auto-rollback to best version
- Session lifecycle management: state save/load, bootstrap one-click recovery

### 8. Knowledge Base Management

- Built-in document management page, add/view/delete .txt documents
- Agent can automatically retrieve knowledge base content
- **Semantic Retrieval (RAG)**: ONNX Runtime Mobile + bge-small Embedding model + SQLite HNSW vector index
- **Hybrid Retrieval**: Semantic + keyword RRF fusion ranking, F1 improvement of 5%+ over pure semantic retrieval
- **Three-Tier Cache**: Hot/warm/cold tiering (7-day window), query latency < 200ms

### 9. Long-Term Memory System

- **Memory Importance Scoring**: Comprehensive scoring based on access frequency, timeliness (exponential decay, 7-day half-life), and semantic importance
- **Cross-Session Memory Graph**: Directed graph structure, supports reference/temporal/semantic associations, supports fuzzy recall
- **Three-Tier Memory Compression**: Hot memory (resident in memory), warm memory (GZIP compressed), cold memory (summary archive)
- **Vector Semantic Retrieval**: Supports natural language queries, Top-5 hit rate > 85%

### 10. Heterogeneous Computing Scheduling

- **Device Capability Detection**: Reads real hardware metrics via MethodChannel (GPU model, CPU big/little cores, memory bandwidth, NPU availability, thermal status)
- **Adaptive Backend Selection**: CPU / OpenCL / Vulkan / Metal / NPU dynamic switching
- **GPU Acceleration**: Adreno/Mali GPU auto-enables OpenCL backend, boosting inference speed by 3-5x
- **Thread Optimization**: Thread count matches CPU big core count (not total cores), reducing scheduling overhead
- **Model Warmup**: Executes dummy inference after loading to trigger kernel compilation + OpenCL cache generation
- **Runtime Hot-Switching**: Automatically switches inference backend and sampling parameters based on device status

### 11. Multimodal Quantization

- **Decoupled Quantization**: Vision encoder (ViT) and language model use different quantization bit-widths
- **Auto Configuration Selection**: Automatically selects INT3/INT4/INT8/FP16 scheme based on device memory
- **Quantization Benchmark Framework**: Supports per-channel / per-token / per-group granularity testing

### 12. Session Export

- One-click export of conversation history as text file for easy backup and sharing

---

## Architecture

```
┌─────────────────────────────────────────────┐
│            Flutter UI (Dart)                │
│   Chat · Model Market · Settings · Agent(ReAct) │
├─────────────────────────────────────────────┤
│         mnn_llm plugin (dart:ffi)           │
│   MnnLlmSession -> streaming Stream<String> │
├─────────────────────────────────────────────┤
│      C API Wrapper (extern "C")             │
│   mnn_llm_capi.cpp · callback streaming output │
├─────────────────────────────────────────────┤
│      MNN-LLM C++ Engine                     │
│   Llm / Omni / Tokenizer / Sampler          │
│   OpenCL(Android) · Metal(iOS) acceleration │
├─────────────────────────────────────────────┤
│     Agent Runtime · Extensible Tool Ecosystem Layer │
│   ├─ System Prompt rules A~S (decision guidance) │
│   ├─ agent_runtime (ReAct loop + tool registry)   │
│   │   ├─ Constrained Decoding                │
│   │   ├─ Intent Routing Classifier            │
│   │   ├─ Tool Schema Validation               │
│   │   ├─ Self-Correction Retry Loop (exponential backoff) │
│   │   └─ Adaptive Inference Scheduling (power/thermal aware) │
│   ├─ KV Cache Management                      │
│   │   ├─ H2O Heavy-Hitter Retention Policy    │
│   │   └─ Sliding Window + Summary Cache       │
│   ├─ Long-Term Memory System                  │
│   │   ├─ Memory Importance Scoring            │
│   │   ├─ Cross-Session Memory Graph           │
│   │   ├─ Three-Tier Compression (hot/warm/cold) │
│   │   └─ Vector Semantic Retrieval            │
│   ├─ On-Device RAG                            │
│   │   ├─ ONNX Runtime Mobile + Embedding      │
│   │   ├─ SQLite HNSW Vector Index             │
│   │   ├─ Hybrid Retrieval (semantic+keyword RRF) │
│   │   └─ Three-Tier Cache                     │
│   ├─ MCP Protocol Layer (lib/agent/mcp)       │
│   │   ├─ McpClient (initialize/listTools/callTool) │
│   │   ├─ HttpMcpTransport / StdioMcpTransport │
│   │   ├─ Capability-based Permission Model    │
│   │   ├─ Stdio Sandbox Process Isolation      │
│   │   ├─ mDNS LAN Discovery                   │
│   │   └─ MCP Persistence (mcp_state_save/load) │
│   └─ Skill System (lib/agent/skills)          │
│       ├─ SkillManager (topological sort · remember · snapshot) │
│       ├─ 8+ Built-in Skills                   │
│       ├─ JsonSpecSkill (runtime JSON dynamic registration) │
│       ├─ Trajectory Recording + Auto-Synthesis (LCS sequence alignment) │
│       ├─ Version Evolution & Self-Repair      │
│       └─ Session Lifecycle (save/load · bootstrap) │
├─────────────────────────────────────────────┤
│      Android RPA Automation Layer (Kotlin)   │
│   L1: AccessibilityService (UI control)      │
│   L2: Shizuku Shell (reflection, no SDK dependency) │
│   L3: Root reserved                           │
│   ├─ Checkpoint System + State Machine        │
│   ├─ 5-Category Exception Detection & Recovery │
│   ├─ VLM Anchorless UI Operation              │
│   └─ MethodChannel ↔ Dart Tool Bridge         │
├─────────────────────────────────────────────┤
│      iOS Automation Layer (Swift)            │
│   ├─ Siri Shortcuts (AppIntents/NSUserActivity)│
│   ├─ URL Scheme (UIApplication.shared.open)   │
│   ├─ Live Activities (ActivityKit)            │
│   └─ MethodChannel ↔ Dart Tool Bridge         │
└─────────────────────────────────────────────┘
```

---

## Performance Baseline

| Model | Memory Usage | Snapdragon 8 Gen 3 | A17 Pro | Applicable Scenario |
|---|---|---|---|---|
| Qwen3-0.6B | ~0.6 GB | 30+ t/s | 40+ t/s | Entry-level / Low-end devices |
| Qwen3-1.7B | ~1.3 GB | 18-22 t/s | 25-30 t/s | Daily chat (recommended) |
| Qwen3-4B | ~2.4 GB | 12-15 t/s | 15-20 t/s | Flagship devices · stronger capability |
| Qwen2.5-Omni-7B | ~4.0 GB | 8-10 t/s | 12-15 t/s | Multimodal · requires 8GB+ memory |

---

## Quick Start

### Requirements

- Flutter ≥ 3.22 (including Dart ≥ 3.3)
- Android Studio + CMake 3.22+
- Xcode 15+ (iOS development, requires macOS)
- arm64 Android physical device (emulator does not support OpenCL/Metal acceleration)

### 1. Clone and Initialize

```bash
git clone https://github.com/your-name/openagent.git
cd openagent
flutter pub get
```

### 2. Download MNN Prebuilt Library

```bash
cd packages/mnn_llm
bash scripts/download_mnn_prebuilt.sh
```

### 3. Run

**Option 1: Download via in-app model marketplace (recommended)**

```bash
flutter run --release
# Open App -> bottom navigation "Models" -> select model -> download -> start chatting
```

**Option 2: adb push pre-downloaded model**

```bash
adb push Qwen3-0.6B-MNN /sdcard/Android/data/com.openagent.openagent/files/models/
flutter run --release
```

---

## CI/CD

| Platform | Workflow | Runner | Artifact | Trigger |
|---|---|---|---|---|
| Android | `build_android.yml` | ubuntu-latest | `openagent-release-apk` (APK) | push / PR / tag |
| iOS | `build_ios.yml` | macos-latest | `openagent-release-ios-unsigned` (IPA) | push / PR / tag |

**Pipeline**: checkout -> Flutter setup -> `pub get` -> `flutter analyze` -> `dart format --set-exit-if-changed` -> `flutter test` -> download/build MNN -> `flutter build` -> upload artifact -> GitHub Release (on tag `v*`)

- Android: downloads prebuilt MNN `.so` from GitHub Releases (cached)
- iOS: builds `MNN.framework` from source with Metal acceleration (cached by `build_ios.sh` hash), generates Xcode project via `flutter create`, builds unsigned IPA
- Tag a release (`git tag v1.0.0 && git push --tags`) to auto-publish APK + IPA to GitHub Releases

---

## Project Structure

```
openagent/
├── lib/                        # Flutter App main project
│   ├── main.dart               # Entry point
│   ├── app.dart                # MaterialApp + GoRouter
│   ├── data/
│   │   ├── models/models.dart            # Data models
│   │   ├── rag/                          # On-device RAG system
│   │   │   ├── onnx_runtime_session.dart  # ONNX Runtime wrapper
│   │   │   ├── embedding_service.dart     # Embedding service
│   │   │   ├── vector_index.dart          # SQLite HNSW vector index
│   │   │   ├── hybrid_retriever.dart      # Hybrid retriever
│   │   │   └── knowledge_cache.dart       # Three-tier cache
│   │   ├── services/
│   │   │   ├── device_monitor_service.dart   # Device status monitoring (real hardware data)
│   │   │   ├── device_capability_service.dart # Device capability detection + model recommendation
│   │   │   ├── device_probe_service.dart      # Native device detection MethodChannel wrapper
│   │   │   ├── mnn_config_builder.dart        # Dynamic MNN backend config generation
│   │   │   ├── quantization_benchmark.dart   # Quantization benchmark framework
│   │   │   ├── auto_quantization.dart        # Auto quantization selection
│   │   │   ├── file_storage_service.dart
│   │   │   ├── model_download_service.dart
│   │   │   ├── schedule_service.dart     # Scheduled task scheduling
│   │   │   ├── android_automation_service.dart
│   │   │   ├── ios_automation_service.dart  # iOS automation (Shortcuts + Live Activities)
│   │   │   └── platform_automation_service.dart # Platform abstraction interface (PlatformAutomationService)
│   │   └── repositories/
│   ├── features/
│   │   ├── chat/                       # Chat page
│   │   ├── model_market/               # Model marketplace
│   │   ├── knowledge_base/             # Knowledge base
│   │   ├── automation/                 # Permission guide page
│   │   └── settings/                   # Settings page
│   └── agent/
│       ├── agent_runtime.dart          # ReAct loop + constrained decoding + self-correction
│       ├── agent_prompt.dart           # System Prompt template
│       ├── agent_constants.dart        # Shared constants
│       ├── constraint_decoder.dart     # Constrained decoder
│       ├── intent_classifier.dart      # Intent routing classifier
│       ├── tool_validator.dart         # Schema validator
│       ├── inference_scheduler.dart    # Adaptive inference scheduler
│       ├── kv_cache/                   # KV Cache management
│       │   ├── h2o_strategy.dart       # H2O heavy-hitter strategy
│       │   └── sliding_window.dart     # Sliding window + summary cache
│       ├── memory/                     # Long-term memory system
│       │   ├── memory_scorer.dart      # Memory importance scoring
│       │   ├── memory_graph.dart       # Cross-session memory graph
│       │   ├── memory_compressor.dart  # Three-tier memory compression
│       │   └── vector_memory_backend.dart # Vector semantic memory
│       ├── android_tools.dart          # Entry (factory functions)
│       ├── android_tools/              # 6 submodules
│       ├── ios_tools.dart              # iOS automation tools (Shortcuts + Live Activities)
│       ├── web_tools.dart              # Cross-platform WebView automation tools
│       ├── tool_registry.dart          # Unified platform tool registration (PlatformToolFactory)
│       ├── builtin_tools.dart          # Entry (factory functions)
│       ├── builtin_tools/              # 3 submodules
│       ├── rpa/                        # RPA automation enhancement
│       │   ├── checkpoint_system.dart  # Checkpoint system
│       │   ├── state_machine.dart      # App state machine
│       │   ├── error_recovery.dart     # Exception detection and recovery
│       │   ├── vision_grounding.dart   # VLM visual grounding
│       │   ├── resolution_adapter.dart # Cross-resolution adaptation
│       │   └── hybrid_localizer.dart   # Hybrid localization strategy
│       ├── mcp/                        # MCP protocol layer
│       │   ├── mcp_client.dart
│       │   ├── mcp_persistence.dart
│       │   ├── mcp_security.dart       # Capability permission model
│       │   ├── mcp_sandbox.dart        # Stdio sandbox
│       │   └── mcp_discovery.dart      # mDNS LAN discovery
│       └── skills/                     # Skill system
│           ├── skills.dart, skill_tools.dart, skills_extra.dart
│           ├── session_lifecycle.dart
│           ├── skill_trace_recorder.dart # Trajectory recording
│           ├── skill_synthesizer.dart    # Auto-synthesis
│           └── skill_evolution.dart     # Version evolution
│           └── ios_skills.dart          # iOS Shortcuts + Live Activity Skills
├── android/.../                         # Android native layer
│   ├── DeviceProbe.kt                  # Device hardware detection (MethodChannel)
│   └── automation/                     # Automation layer
├── ios/Runner/                         # iOS native layer
│   ├── AppDelegate.swift               # Channel registration + Shortcuts + Live Activities + Siri callback
│   └── Info.plist                      # NSSupportsLiveActivities + permissions
├── packages/mnn_llm/                   # FFI plugin
├── packages/onnx_runtime/              # ONNX Runtime plugin skeleton
├── test/                               # Unit tests (50+ files)
├── tools/                              # Helper scripts
└── .github/workflows/                  # CI/CD
```

---

## Comparison with Similar Projects

| Project | Engine | Platform | Multimodal | RPA Automation | MCP Protocol | Dynamic Skill | Open Source |
|---|---|---|---|---|---|---|---|
| **OpenAgent** | MNN-LLM | Android + iOS | ✅ | ✅ 190+ tools (170+ Android · 9 iOS · 8 WebView) | ✅ HTTP+Stdio | ✅ JSON runtime | ✅ |
| MNN Chat (Official) | MNN-LLM | Android + iOS | ✅ | ❌ | ❌ | ❌ | ✅ |
| llama.cpp | ggml | All platforms | Partial | ❌ | Partial | ❌ | ✅ |
| Tasker | - | Android | ❌ | ✅ Plugin ecosystem | ❌ | ✅ Scripts | ❌ |
| Auto.js | - | Android | ❌ | ✅ Accessibility | ❌ | ✅ JS scripts | ❌ |

**Differentiators**:
- First on-device LLM + RPA automation + MCP protocol integrated solution
- Local LLM/VLM autonomous decision-making to operate the phone, zero network requests
- Code non-intervention principle: code layer only provides hooks, all decisions made autonomously by the model
- 11 research directions covering inference engine optimization, Agent reliability, RPA fault tolerance, MCP security, system-level power optimization

---

## License

Apache License 2.0, consistent with upstream [MNN](https://github.com/alibaba/MNN), business-friendly.
