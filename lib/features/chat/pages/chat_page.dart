// Full chat page: streaming responses, Markdown rendering, multi-session,
// model loading, multimodal input, and generation cancellation.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import 'package:mnn_llm/mnn_llm.dart';
import '../../../agent/agent_runtime.dart';
import '../../../agent/android_tools.dart';
import '../../../agent/builtin_tools.dart';
import '../../../agent/tool_registry.dart';
import '../../../agent/web_tools.dart';
import '../../../agent/mcp/mcp_client.dart';
import '../../../agent/mcp/mcp_persistence.dart';
import '../../../agent/skills/skills.dart';
import '../../../agent/skills/ios_skills.dart';
import '../../../agent/skills/skill_tools.dart';
import '../../../agent/skills/skills_extra.dart';
import '../../../agent/skills/session_lifecycle.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/chat_repository.dart';
import '../../../data/repositories/model_repository.dart';
import '../../../data/services/android_automation_service.dart';
import '../../../data/services/device_capability_service.dart';
import '../../../data/services/file_storage_service.dart';
import '../../../data/services/ios_automation_service.dart';
import '../../../data/services/mnn_config_builder.dart';
import '../../../agent/inference_scheduler.dart';
import '../widgets/message_bubble.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.storage});

  final FileStorageService storage;

  @override
  State<ChatPage> createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _imagePicker = ImagePicker();
  final _audioRecorder = AudioRecorder();

  late final ChatRepository _chatRepo;
  late final ModelRepository _modelRepo;
  MnnLlmSession? _session;
  MnnOmniSession? _omniSession;
  CloudLlmSession? _cloudSession;
  ModelType _modelType = ModelType.text;
  bool _usingCloud = false;
  List<ChatSession> _sessions = [];
  ChatSession? _current;
  AppConfig _config = const AppConfig();
  bool _isGenerating = false;
  bool _modelLoading = false;
  bool _agentMode = false;
  bool _automationEnabled = false;
  bool _isRecording = false;
  String? _loadedModelId;
  String? _statusLine;

  /// Cached device capability for backend config and model recommendation.
  DeviceCapability? _deviceCapability;

  /// Adaptive inference scheduler for dynamic profile switching.
  InferenceScheduler? _scheduler;

  /// Stats for the current agent run (reset on AgentDoneEvent).
  int _toolCallCount = 0;
  int _toolCallErrorCount = 0;
  final Map<String, DateTime> _toolCallStartTimes = {};

  final AndroidAutomationService _android = AndroidAutomationService.instance;
  final IosAutomationService _ios = IosAutomationService.instance;

  /// Media file paths attached to the next outgoing message. Cleared on send.
  final List<String> _attachedMedia = [];

  @override
  void initState() {
    super.initState();
    _chatRepo = ChatRepository(widget.storage);
    _modelRepo = ModelRepository(widget.storage);
    // Listen for Siri Shortcut invocations on iOS.
    _ios.startListening();
    _bootstrap();
  }

  /// Called by the root app after model / config changes so ChatPage picks
  /// up the latest AppConfig (active model, sampling, system prompt).
  Future<void> reload() async {
    _config = await widget.storage.loadAppConfig();
    if (mounted) setState(() {});
    await _ensureModelLoaded();
  }

  Future<void> _bootstrap() async {
    _config = await widget.storage.loadAppConfig();
    _sessions = await _chatRepo.loadSessions();

    // Detect device capability once on startup for backend config and
    // model recommendation.
    _deviceCapability = await DeviceCapabilityService().detect();

    // Auto-recommend a model if the user hasn't selected one yet.
    if (_config.activeModelId == null && _deviceCapability != null) {
      final recommended =
          DeviceCapability.recommendModel(_deviceCapability!.totalMemoryMb);
      _config = _config.copyWith(activeModelId: recommended);
      await widget.storage.saveAppConfig(_config);
    }

    // Start adaptive inference scheduler for dynamic profile switching.
    _scheduler = InferenceScheduler();
    _scheduler!.start();
    _scheduler!.onProfileChange((profile) {
      // Dynamically adjust max tokens when device state changes.
      if (!_usingCloud && _session != null) {
        final updatedSampling =
            _config.sampling.copyWith(maxNewTokens: profile.maxTokens).toJson();
        if (_config.systemPrompt.isNotEmpty) {
          updatedSampling['system_prompt'] = _config.systemPrompt;
        }
        _session!.setConfig(updatedSampling);
      }
    });

    if (_sessions.isEmpty) {
      _current = ChatSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: '新对话',
        messages: const [],
        createdAt: DateTime.now(),
        modelId: _config.activeModelId,
      );
      _sessions.add(_current!);
    } else {
      _current = _sessions.first;
    }
    if (mounted) setState(() {});
    await _ensureModelLoaded();
  }

  Future<void> _ensureModelLoaded() async {
    // ---- Cloud LLM path (no local model required) ----
    if (_config.modelSource == ModelSource.cloud &&
        _config.cloud.isConfigured) {
      final cloudKey = '${_config.cloud.provider}:${_config.cloud.model}';
      if (cloudKey == _loadedModelId && _cloudSession != null) return;
      _session?.dispose();
      _omniSession?.dispose();
      _cloudSession?.dispose();
      _session = null;
      _omniSession = null;
      setState(() => _modelLoading = true);
      try {
        _cloudSession = await CloudLlmSession.create(
          CloudLlmConfig(
            provider: _mapCloudProvider(_config.cloud.provider),
            apiKey: _config.cloud.apiKey,
            model: _config.cloud.model,
            baseUrl:
                _config.cloud.baseUrl.isEmpty ? null : _config.cloud.baseUrl,
            systemPrompt: _config.cloud.systemPrompt.isNotEmpty
                ? _config.cloud.systemPrompt
                : _config.systemPrompt,
            temperature: _config.cloud.temperature,
            maxTokens: _config.cloud.maxTokens,
          ),
        );
        _usingCloud = true;
        _modelType = ModelType.text; // cloud is text-only
        _loadedModelId = cloudKey;
        _statusLine =
            '☁️ 已连接云端 LLM: ${_config.cloud.provider} / ${_config.cloud.model}';
      } catch (e) {
        _cloudSession = null;
        _loadedModelId = null;
        _statusLine = '云端 LLM 初始化失败: $e';
      } finally {
        if (mounted) setState(() => _modelLoading = false);
      }
      // Cloud LLM doesn't support Agent mode in this initial integration.
      if (_agentMode) {
        _agentMode = false;
      }
      return;
    }

    // ---- Local model path ----
    final modelId = _config.activeModelId;
    if (modelId == null || modelId == _loadedModelId) return;
    _cloudSession?.dispose();
    _cloudSession = null;
    _usingCloud = false;
    final downloaded = await widget.storage.isModelDownloaded(modelId);
    if (!downloaded) {
      _statusLine = '模型 $modelId 未下载，请到模型市场下载';
      if (mounted) setState(() {});
      return;
    }

    // Look up model type (text vs omni) from the catalogue.
    ModelType? type;
    try {
      final catalogue = await _modelRepo.catalogue();
      for (final m in catalogue) {
        if (m.id == modelId) {
          type = m.type;
          break;
        }
      }
    } catch (_) {
      // Catalogue read failure — assume text-only.
    }
    _modelType = type ?? ModelType.text;
    // Agent mode only works with text models — auto-disable for Omni.
    if (_modelType == ModelType.omni) _agentMode = false;

    setState(() => _modelLoading = true);
    try {
      _session?.dispose();
      _omniSession?.dispose();
      _session = null;
      _omniSession = null;

      final configPath = await widget.storage.getModelConfigPath(modelId);
      final sampling = _config.sampling.toJson();
      if (_config.systemPrompt.isNotEmpty) {
        sampling['system_prompt'] = _config.systemPrompt;
      }

      // Merge dynamic backend config (GPU/OpenCL, thread count, memory mode)
      // based on detected device capability.
      if (_deviceCapability != null) {
        sampling
            .addAll(MnnConfigBuilder.buildBackendConfig(_deviceCapability!));
      }

      if (_modelType == ModelType.omni) {
        _omniSession = await MnnOmniSession.create();
        await _omniSession!.load(configPath);
        await _omniSession!.setConfig(sampling);
      } else {
        _session = await MnnLlmSession.create();
        await _session!.load(configPath);
        await _session!.setConfig(sampling);

        // Warm-up: run a minimal dummy inference to trigger MNN kernel
        // compilation and OpenCL cache generation. This significantly
        // reduces TTFA (time to first token) on the first real query.
        if (_deviceCapability != null) {
          final warmupConfig =
              MnnConfigBuilder.buildWarmupConfig(_deviceCapability!);
          await _session!.setConfig(warmupConfig);
          try {
            await for (final _ in _session!.chatStream('hi')) {}
          } catch (_) {
            // Warm-up failure is non-fatal - just skip.
          }
          // Restore the real sampling config and clear warm-up KV cache.
          await _session!.setConfig(sampling);
          _session!.reset();
        }
      }
      _loadedModelId = modelId;
      _statusLine = null;
    } catch (e) {
      _loadedModelId = null;
      _session = null;
      _omniSession = null;
      _statusLine = '模型加载失败: $e\n请检查模型文件是否完整，或重新下载模型。';
    } finally {
      if (mounted) setState(() => _modelLoading = false);
    }
  }

  CloudProvider _mapCloudProvider(String p) {
    switch (p) {
      case 'openai':
        return CloudProvider.openai;
      case 'deepseek':
        return CloudProvider.deepseek;
      case 'qwen':
        return CloudProvider.qwenDashScope;
      case 'doubao':
        return CloudProvider.doubao;
      case 'groq':
        return CloudProvider.groq;
      case 'ollama':
        return CloudProvider.ollama;
      case 'anthropic':
        return CloudProvider.anthropic;
      default:
        return CloudProvider.custom;
    }
  }

  /// Whether the active model supports multimodal input (images / audio).
  bool get _isOmni => _modelType == ModelType.omni;

  /// Whether there is any active session (text or omni or cloud).
  bool get _hasSession =>
      _session != null || _omniSession != null || _cloudSession != null;

  /// Smart intent detection — analyzes user input and auto-enables agent mode
  /// and/or automation when appropriate, so the user doesn't have to toggle
  /// switches manually.
  ///
  /// Returns true if the input triggers agent mode (so caller can decide
  /// whether to proceed with agent or plain chat).
  bool _detectIntent(String input) {
    if (input.isEmpty || _isOmni) return false;

    final lower = input.toLowerCase();

    // ---- Keywords that suggest Android automation ----
    final automationKeywords = [
      '操作手机',
      '打开微信',
      '打开抖音',
      '打开小红书',
      '打开b站',
      '打开bilibili',
      '打开qq',
      '打开支付宝',
      '打开游戏',
      '发微信',
      '发朋友圈',
      '发抖音',
      '点开',
      '帮我点',
      '帮我发',
      '帮我刷',
      '帮我写',
      '帮我输',
      '点击',
      '滑动',
      '截屏',
      '截图',
      '自动化',
      'open wechat',
      'open douyin',
      'open app',
      'click ',
      'tap ',
      'android',
      '自动化',
      '帮我操作',
      '帮我弄',
      '弄一下',
      '打开设置',
      '打开相机',
      '打开相册',
      '打电话',
      '发短信',
    ];

    // ---- Keywords that suggest web search / HTTP ----
    final webSearchKeywords = [
      '搜索',
      '查一下',
      '查一查',
      '找找',
      '网上',
      '搜一下',
      '搜一搜',
      '搜索一下',
      '百度',
      '谷歌',
      'google',
      'search',
      'web',
      '查资料',
      '查信息',
      '查新闻',
      '今天的',
      '天气',
      '实时',
      '查',
      '找',
      '搜',
      '最新',
      '热点',
      '新闻',
    ];

    // ---- Keywords that suggest calculation / math ----
    final mathKeywords = [
      '计算',
      '算一下',
      '算一算',
      '统计',
      '数学',
      '加减乘除',
      'calculate',
      'compute',
      'math',
      'count',
      '求和',
      '平均',
    ];

    // ---- Keywords that suggest code / developer tasks ----
    final codeKeywords = [
      '写代码',
      '编程',
      '代码',
      '函数',
      '写一个',
      'bug',
      'debug',
      'code',
      'function',
      'implement',
      '写个脚本',
    ];

    bool needsAgent = false;
    bool needsAutomation = false;

    // Check automation keywords.
    for (final kw in automationKeywords) {
      if (lower.contains(kw)) {
        needsAgent = true;
        needsAutomation = true;
        break;
      }
    }

    // Check web search keywords.
    if (!needsAgent) {
      for (final kw in webSearchKeywords) {
        if (lower.contains(kw)) {
          needsAgent = true;
          break;
        }
      }
    }

    // Check math keywords.
    if (!needsAgent) {
      for (final kw in mathKeywords) {
        if (lower.contains(kw)) {
          needsAgent = true;
          break;
        }
      }
    }

    // Check code/developer keywords.
    if (!needsAgent) {
      for (final kw in codeKeywords) {
        if (lower.contains(kw)) {
          needsAgent = true;
          break;
        }
      }
    }

    // Apply auto-switches.
    if (needsAgent && !_agentMode) {
      _agentMode = true;
      _snack('🧠 检测到需要工具操作，已自动开启 Agent 模式');
    }

    if (needsAutomation && !_automationEnabled) {
      // Don't auto-toggle automation without user acknowledgment of risk.
      // Instead, just note it.
      _snack('📱 检测到手机操作需求，请手动开启手机自动化开关（📱图标）');
    }

    return needsAgent;
  }

  Future<void> _send() async {
    final prompt = _inputCtrl.text.trim();
    final media = List<String>.of(_attachedMedia);
    if (prompt.isEmpty && media.isEmpty) return;
    if (!_hasSession) {
      _snack('模型尚未加载完成，请稍候或前往模型市场选择已下载的模型');
      return;
    }
    if (_isGenerating) return;

    // Smart intent detection — auto-enable agent mode if needed.
    if (!_agentMode && prompt.isNotEmpty) {
      _detectIntent(prompt);
    }

    final userMsg = ChatMessage(
      role: MessageRole.user,
      content: prompt.isEmpty ? '(图片)' : prompt,
      mediaPaths: media,
    );
    final assistantMsg = ChatMessage(
        role: MessageRole.assistant, content: '', isStreaming: true);

    setState(() {
      _current!.messages.addAll([userMsg, assistantMsg]);
      if (_current!.messages.length == 1) _current!.title = userMsg.content;
      _isGenerating = true;
    });
    _inputCtrl.clear();
    _attachedMedia.clear();
    _scrollToBottom();

    try {
      if (_agentMode && !_isOmni && !_usingCloud && _session != null) {
        await _runAgent(prompt, assistantMsg);
      } else if (_usingCloud && _cloudSession != null) {
        final stream = _cloudSession!.chatStream(prompt);
        await for (final chunk in stream) {
          if (!mounted) return;
          setState(() => assistantMsg.content += chunk);
          _scrollToBottom();
        }
      } else {
        final stream = _isOmni
            ? _omniSession!.chatStream(prompt, mediaPaths: media)
            : _session!.chatStream(prompt);
        await for (final chunk in stream) {
          if (!mounted) return;
          setState(() => assistantMsg.content += chunk);
          _scrollToBottom();
        }
      }
    } catch (e) {
      assistantMsg.content += '\n\n⚠️ 生成出错: $e';
    } finally {
      // Append performance metrics if available (text models only).
      if (!_isOmni && _session != null) {
        final m = _session!.metrics();
        if (m != null) {
          final formatted = _formatMetrics(m);
          if (formatted != null) {
            assistantMsg.content += '\n\n$formatted';
          }
        }
      }
      assistantMsg.isStreaming = false;
      if (mounted) setState(() => _isGenerating = false);
      await _chatRepo.saveSessions(_sessions);
    }
  }

  /// Format MNN-LLM metrics as a compact markdown footer.
  /// Returns null if metrics are insufficient.
  String? _formatMetrics(Map<String, dynamic> m) {
    double? toNum(dynamic v) => v is num ? v.toDouble() : null;
    final genLen = toNum(m['gen_seq_len']);
    final decodeUs = toNum(m['decode_us']);
    final prefillUs = toNum(m['prefill_us']);
    final ttfaUs = toNum(m['ttfa_us']);
    if (genLen == null || decodeUs == null || genLen == 0 || decodeUs == 0) {
      return null;
    }
    final tps = genLen / (decodeUs / 1e6);
    final totalMs = ((prefillUs ?? 0) + decodeUs) / 1e3;
    final ttfaMs = (ttfaUs ?? 0) / 1e3;
    return '<sub>⚡ ${tps.toStringAsFixed(1)} t/s · '
        '生成 ${genLen.toInt()} tokens · ${totalMs.toStringAsFixed(0)}ms · '
        'TTFT ${ttfaMs.toStringAsFixed(0)}ms</sub>';
  }

  /// Run the Agent ReAct loop and stream results into [assistantMsg].
  ///
  /// Tool calls and results are formatted as markdown blockquotes so they
  /// render nicely in the MarkdownBody widget. Token text is appended
  /// directly, matching the non-agent streaming path.
  Future<void> _runAgent(String prompt, ChatMessage assistantMsg) async {
    // Reset KV cache so each ReAct loop starts fresh — the agent includes
    // its own system prompt with tool descriptions, so stale KV context
    // from previous turns would confuse the model.
    _session!.reset();
    final enableAndroidAutomation = _automationEnabled && _android.isSupported;
    final agent = LocalMnnAgentRuntime(
      _session!,
      maxSteps: enableAndroidAutomation ? 20 : 5,
      androidMode: enableAndroidAutomation,
      totalMemoryMb: _deviceCapability?.totalMemoryMb,
    );
    for (final tool in builtinTools()) {
      agent.registerTool(tool);
    }
    // Register RAG tool with knowledge base directory.
    final kbDir = await widget.storage.getKnowledgeBaseDir();
    agent.registerTool(knowledgeSearchTool(kbDir));

    // ================================================================
    // Milestone #9 + #10: MCP Registry + Skill Manager bootstrap.
    //
    // Intent: we create the containers + register the meta-tools
    // (skill_list / skill_enable / skill_disable / skill_register_json /
    // mcp_state_save/load) so that the MODEL can decide, on its own, which
    // skills / MCP servers to wire up and when.
    // The code NEVER calls enable() on any skill itself.
    // ================================================================
    final mcpRegistry = McpRegistry();
    final memPath = await widget.storage.getAgentMemoryPath();
    final mcpStatePath = await widget.storage.getMcpStatePath();
    final skillStatePath = await widget.storage.getSkillStatePath();
    final memBackend = FileAgentMemoryBackend(memPath);
    final skillManager = SkillManager(
      registerAgentTool: agent.registerTool,
      unregisterAgentTool: agent.unregisterTool,
      builtIns: [
        // --- Milestone #9 built-ins (3) ---------------------------------
        AndroidRpaSkill(
          androidService: _android,
          visionAnalyze: _visionAnalyzeImage,
          executeCallback: (name, args) => agent.executeTool(name, args),
          memoryBackend: memBackend,
        ),
        BuiltinMathTimeSkill(),
        McpGatewaySkill(mcpRegistry),
        // --- Milestone #10 fine-grained (4) -----------------------------
        KnowledgeRagSkill(kbDir.path),
        AgentLongTermMemorySkill(memBackend),
        ExecutePlanSkill((name, args) => agent.executeTool(name, args)),
        VisionAnalyzeSkill(_visionAnalyzeImage),
        // --- iOS platform skills (no-op on Android, gated by Platform.isIOS) -
        IosShortcutsSkill(),
        IosLiveActivitySkill(),
      ],
    );
    // ---- Meta-tools: skill_* (+ JSON register) + mcp_state_* + skill_state_* + session_bootstrap + manifests ----
    for (final t in createSkillTools(skillManager)) {
      agent.registerTool(t);
    }
    for (final t in createSkillRegisterJsonTools(
      skillManager: skillManager,
      mcpRegistry: mcpRegistry,
      agentRuntime: agent,
    )) {
      agent.registerTool(t);
    }
    for (final t in createMcpPersistenceTools(mcpRegistry, mcpStatePath)) {
      agent.registerTool(t);
    }
    for (final t in createSkillPersistenceTools(skillManager, skillStatePath)) {
      agent.registerTool(t);
    }
    for (final t in createSkillRememberTools(skillManager)) {
      agent.registerTool(t);
    }
    for (final t in createSkillToolsManifestTools(skillManager, agent)) {
      agent.registerTool(t);
    }
    for (final t in createSessionBootstrapTools(
      skillManager: skillManager,
      mcpRegistry: mcpRegistry,
      mcpStatePath: mcpStatePath,
      skillStatePath: skillStatePath,
      memoryBackend: memBackend,
      extraInfo: {
        'android_supported': _android.isSupported,
        'automation_ui_switch_on': enableAndroidAutomation,
        'android_legacy_preload_on': enableAndroidAutomation
            ? 'yes (60+ android tools preloaded)'
            : 'no; skill_enable android_rpa yourself',
      },
    )) {
      agent.registerTool(t);
    }
    // Register skill_create_from_trace meta-tool.
    agent.registerTool(createSkillFromTraceTool(skillManager));

    // Register anti-detection tools — ALWAYS available so the agent can
    // check whether the current foreground app is high-risk (banking/
    // payment) before attempting any automation.
    for (final t in createAntiDetectionTools(service: _android)) {
      agent.registerTool(t);
    }

    // NOTE: McpRegistry + SkillManager are owned by this function scope;
    // when the agent run is done, they become eligible for GC. MCP servers
    // left connected after run end are leaked on purpose: the model is
    // responsible for calling mcp_disconnect if it cares. If we wanted
    // deterministic cleanup, we could post-await mcpRegistry.disposeAll()
    // after agent.run finishes.

    // Register Android automation tools when explicitly enabled (legacy
    // compat path — when user UI switch is on, pre-load the full set so
    // pre-existing "just toggle the switch and ask" flows still work).
    // The model path is skill_enable android_rpa at the top of the ReAct
    // loop when the UI switch is OFF.
    if (enableAndroidAutomation) {
      for (final t in createAndroidAutomationTools(
        service: _android,
        visionAnalyze: _visionAnalyzeImage,
        executeCallback: (name, args) => agent.executeTool(name, args),
        memoryBackend: FileAgentMemoryBackend(memPath),
      )) {
        agent.registerTool(t);
      }
    }

    // Register cross-platform WebView automation tools (available on all
    // platforms - the iOS RPA alternative for web-based workflows).
    for (final t in createWebAutomationTools()) {
      agent.registerTool(t);
    }

    // Register platform tools via the unified ToolRegistry. On each platform
    // this registers the native tools + degradation stubs for the other
    // platform's tools (so the Agent gets "not available" instead of a
    // missing tool error).
    final platformTools = createPlatformTools(ToolFactoryContext(
      androidService: _android,
      iosService: _ios,
      visionAnalyze: _visionAnalyzeImage,
      executeCallback: (name, args) => agent.executeTool(name, args),
      memoryBackend: FileAgentMemoryBackend(memPath),
    ));
    for (final t in platformTools) {
      agent.registerTool(t);
    }

    // Auto-start Live Activity on iOS so the user sees Agent status in
    // the Lock Screen / Dynamic Island while the ReAct loop runs.
    if (_ios.isSupported) {
      await _ios.startActivity(title: 'Agent 运行中', content: '正在思考...');
    }

    await for (final event in agent.run(prompt)) {
      if (!mounted) {
        if (_ios.isActivityActive) await _ios.endActivity();
        return;
      }
      switch (event) {
        case AgentTokenEvent(:final chunk):
          assistantMsg.content += chunk;
          setState(() {});
          _scrollToBottom();
        case AgentToolCallEvent(:final toolName, :final arguments):
          _toolCallStartTimes[toolName] = DateTime.now();
          _toolCallCount++;
          // Update Live Activity with current tool being executed.
          if (_ios.isActivityActive) {
            _ios.updateActivity('正在执行工具: $toolName');
          }
          final prettyArgs =
              const JsonEncoder.withIndent('  ').convert(arguments);
          assistantMsg.content += '\n\n---\n\n🔧 **调用工具**: `$toolName`\n\n'
              '```json\n$prettyArgs\n```\n\n';
          setState(() {});
          _scrollToBottom();
        case ToolExecutionEvent(:final toolName, :final result):
          if (result.isError) _toolCallErrorCount++;
          final elapsed = _toolCallStartTimes.remove(toolName);
          final elapsedStr = elapsed != null
              ? '⏱ ${DateTime.now().difference(elapsed).inMilliseconds}ms'
              : '';
          final icon = result.isError ? '❌' : '✅';
          assistantMsg.content += '$icon **$toolName 结果** $elapsedStr:\n\n'
              '```\n${result.output}\n```\n\n---\n\n';
          setState(() {});
          _scrollToBottom();
        case AgentDoneEvent():
          // Finalize: append a small stats footer.
          if (_toolCallCount > 0) {
            final okCount = _toolCallCount - _toolCallErrorCount;
            assistantMsg.content +=
                '\n\n> 📊 **工具统计**: 共调用 $_toolCallCount 次，成功 $okCount，失败 $_toolCallErrorCount\n';
            setState(() {});
          }
          // Tokens already streamed; just finalize.
          if (assistantMsg.content.trim().isEmpty && event.answer.isNotEmpty) {
            assistantMsg.content = event.answer;
            setState(() {});
          }
          // Reset for next round.
          _toolCallCount = 0;
          _toolCallErrorCount = 0;
          _toolCallStartTimes.clear();
        case AgentErrorEvent(:final message):
          assistantMsg.content += '\n\n⚠️ $message';
          setState(() {});
      }
    }

    // End Live Activity when the agent run completes.
    if (_ios.isActivityActive) await _ios.endActivity();
  }

  void _stop() {
    _session?.stop();
    _omniSession?.stop();
    _cloudSession?.stop();
  }

  void _newSession() {
    _current = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: '新对话',
      messages: const [],
      createdAt: DateTime.now(),
      modelId: _loadedModelId,
    );
    _session?.reset();
    _omniSession?.reset();
    _sessions.insert(0, _current!);
    setState(() {});
  }

  void _switchSession(ChatSession s) {
    _current = s;
    _session?.reset();
    _omniSession?.reset();
    Navigator.pop(context); // close drawer
    setState(() {});
  }

  Future<void> _deleteSession(ChatSession s) async {
    await _chatRepo.deleteSession(s.id, _sessions);
    if (_current?.id == s.id) {
      _current = _sessions.isEmpty ? null : _sessions.first;
    }
    setState(() {});
  }

  Future<void> _exportSession() async {
    final session = _current;
    if (session == null || session.messages.isEmpty) {
      _snack('当前会话为空，无法导出');
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('# ${session.title}');
    buffer.writeln('# 导出时间: ${DateTime.now().toIso8601String()}');
    buffer.writeln('# 模型: ${_loadedModelId ?? "未指定"}');
    buffer.writeln();

    for (final msg in session.messages) {
      final role = msg.role == MessageRole.user ? '👤 用户' : '🤖 助手';
      buffer.writeln('---');
      buffer.writeln('$role (${msg.timestamp.toIso8601String()}):');
      buffer.writeln(msg.content);
      buffer.writeln();
    }

    final modelsDir = await widget.storage.getModelsDir();
    final exportsDir = Directory('${modelsDir.parent.path}/exports');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }

    final safeTitle =
        session.title.replaceAll(RegExp(r'[^\w\u4e00-\u9fff]'), '_');
    final filename =
        '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.txt';
    final file = File('${exportsDir.path}/$filename');
    await file.writeAsString(buffer.toString());

    _snack('已导出: $filename');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Toggle the Android-automation extension for the Agent runtime.
  ///
  /// On first enable, shows a risk-acknowledgment dialog (re-uses the
  /// AppConfig.automation.warningDismissed flag so it's asked only once).
  Future<void> _toggleAutomation() async {
    // Force Agent mode on if it isn't — automation only works with Agent.
    if (!_agentMode && !_automationEnabled) {
      setState(() => _agentMode = true);
      _snack('已同步开启 Agent 模式，自动化工具需配合 Agent 使用');
    }

    if (!_automationEnabled && !_config.automation.warningDismissed) {
      final go = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.warning_amber, color: Colors.red),
            SizedBox(width: 8),
            Text('使用风险提示'),
          ]),
          scrollable: true,
          content: const Text(
            '开启手机自动化后，Agent 将根据您的指令通过无障碍服务/Shizuku 操作手机上的任意应用（点击、滑动、输入文字等）。\n\n'
            '请您确认了解以下风险：\n'
            '1. 仅在您信任的指令下使用；\n'
            '2. 出现误操作时可随时关闭该开关或停止当前任务；\n'
            '3. 所有操作仅在本设备本地执行，不会上传隐私；\n'
            '4. 您有责任承担自动化产生的后果（如误发消息、误点赞等）。\n\n'
            '若未授权权限，可在下一步跳转到"权限引导页"完成开启。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('我已知晓，继续'),
            ),
          ],
        ),
      );
      if (go != true) return;
      final cfg = await widget.storage.loadAppConfig();
      await widget.storage.saveAppConfig(cfg.copyWith(
          automation: cfg.automation.copyWith(warningDismissed: true)));
      _config = await widget.storage.loadAppConfig();
    }

    setState(() => _automationEnabled = !_automationEnabled);
    if (_automationEnabled) {
      // Quickly show status so the user knows what's enabled.
      final status = await _android.refreshStatus();
      final notReady = !status.accessibilityEnabled && !status.shizukuGranted;
      if (notReady && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('未检测到可用的自动化权限，点击右上角🛡图标前往权限引导页开启。'),
          action: SnackBarAction(
            label: '去开启',
            onPressed: () => context.go('/permission_guide'),
          ),
        ));
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Pick an image from the gallery and add it to [_attachedMedia].
  /// Only available when the active model is multimodal.
  Future<void> _pickImage() async {
    try {
      final xfile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (xfile != null) {
        setState(() => _attachedMedia.add(xfile.path));
      }
    } catch (e) {
      _statusLine = '选图失败: $e';
      setState(() {});
    }
  }

  /// Pick an image from the camera.
  Future<void> _takePhoto() async {
    try {
      final xfile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (xfile != null) {
        setState(() => _attachedMedia.add(xfile.path));
      }
    } catch (e) {
      _statusLine = '拍照失败: $e';
      setState(() {});
    }
  }

  void _removeMedia(int index) {
    setState(() => _attachedMedia.removeAt(index));
  }

  /// Toggle voice recording for multimodal (Omni) models.
  /// Starts recording if not recording, stops and attaches the audio file
  /// if already recording.
  Future<void> _toggleRecording() async {
    if (!_isOmni || !_hasSession) return;

    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        setState(() => _attachedMedia.add(path));
        _snack('语音录制完成');
      }
      return;
    }

    // Check microphone permission.
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _snack('需要麦克风权限才能录制语音');
        return;
      }

      final modelsDir = await widget.storage.getModelsDir();
      final recordingsDir = Directory('${modelsDir.parent.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }
      final path =
          '${recordingsDir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 16000,
        ),
        path: path,
      );
      setState(() => _isRecording = true);
    } catch (e) {
      _snack('录音启动失败: $e');
      setState(() => _isRecording = false);
    }
  }

  /// One-shot Omni VLM analysis helper. Creates a fresh MnnOmniSession
  /// loading the first downloaded Omni model, runs [question] with [imagePath]
  /// as multimodal context, returns the concatenated model answer text.
  /// Throws if no Omni model has been downloaded or the session fails to load.
  Future<String> _visionAnalyzeImage(String imagePath, String question) async {
    final catalogue = await _modelRepo.catalogue();
    final downloaded = await _modelRepo.downloadedModelIds();
    final omniModel = catalogue.cast<ModelInfo?>().firstWhere(
          (m) => m!.type == ModelType.omni && downloaded.contains(m.id),
          orElse: () => null,
        );
    if (omniModel == null) {
      final msg = downloaded.isEmpty
          ? '（当前未下载任何模型）'
          : '当前已下载 ${downloaded.length} 个文本模型（不含多模态）：${downloaded.join('、')}。';
      throw StateError(
          '尚未下载 Omni 多模态模型，无法进行视觉分析。请先在「模型市场」下载任一 Qwen2.5-Omni / 多模态 MNN 模型后再试。\n$msg');
    }
    final configPath = await widget.storage.getModelConfigPath(omniModel.id);
    final sampling = _config.sampling.toJson();
    if (_config.systemPrompt.isNotEmpty) {
      sampling['system_prompt'] = _config.systemPrompt;
    }
    // Apply dynamic backend config for GPU acceleration and thread optimization.
    if (_deviceCapability != null) {
      sampling.addAll(MnnConfigBuilder.buildBackendConfig(_deviceCapability!));
    }
    final session = await MnnOmniSession.create();
    try {
      await session.load(configPath);
      await session.setConfig(sampling);
      final buf = StringBuffer();
      await for (final chunk
          in session.chatStream(question, mediaPaths: [imagePath])) {
        buf.write(chunk);
      }
      final text = buf.toString().trim();
      if (text.isEmpty) {
        throw StateError('Omni 模型分析返回空输出（${omniModel.id}），请检查模型文件完整性后重试。');
      }
      return '【多模态视觉分析 · ${omniModel.name} (${omniModel.id})】\n$text';
    } finally {
      session.dispose();
    }
  }

  @override
  void dispose() {
    _scheduler?.dispose();
    _ios.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _audioRecorder.dispose();
    _session?.dispose();
    _omniSession?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_current?.title ?? 'OpenAgent'),
        actions: [
          if (_modelLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          IconButton(
            icon: Icon(_automationEnabled
                ? Icons.phone_android
                : Icons.phone_android_outlined),
            color: _automationEnabled ? Colors.green.shade700 : null,
            tooltip: _automationEnabled
                ? '手机自动化已开启（操作微信/抖音/游戏等）'
                : '手机自动化：操作微信/抖音/游戏等 (需开启Agent模式)',
            onPressed: _isOmni ? null : _toggleAutomation,
          ),
          IconButton(
            icon: const Icon(Icons.security_outlined),
            tooltip: '自动化权限引导',
            onPressed: () => context.go('/permission_guide'),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: () => context.go('/models'),
            tooltip: '模型市场',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go('/settings'),
            tooltip: '设置',
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _exportSession,
            tooltip: '导出会话',
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _newSession,
            tooltip: '新建对话',
          ),
        ],
      ),
      drawer: _sessionDrawer(),
      body: Column(children: [
        if (_statusLine != null) _statusBanner(),
        Expanded(child: _messageList()),
        _inputBar(),
      ]),
    );
  }

  Widget _statusBanner() => Material(
        color: Colors.amber.shade100,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child:
                    Text(_statusLine!, style: const TextStyle(fontSize: 13))),
          ]),
        ),
      );

  Widget _messageList() {
    final messages = _current?.messages ?? const [];
    if (messages.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.chat_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('开始一段新对话',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          if (_loadedModelId != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('当前模型: $_loadedModelId${_isOmni ? ' (多模态)' : ''}',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
            ),
          if (_agentMode && !_isOmni)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _automationEnabled
                  ? Text(
                      'Agent + 手机自动化模式 · 工具: 基础5项 + 安卓17项（点击/滑动/截图/包名查询/shell直通)',
                      style: TextStyle(
                          color: Colors.green.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    )
                  : Text(
                      'Agent 模式 · 工具: 搜索/HTTP/计算/日期/文本统计/单位换算/知识库/JSON格式化/随机数/UUID/Base64/颜色/天气/IP查询/模板引擎/计时器',
                      style: TextStyle(
                          color: Colors.indigo.shade300, fontSize: 12),
                    ),
            ),
        ]),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (_, i) {
        final m = messages[i];
        if (m.role == MessageRole.assistant) {
          return MessageBubble(
            role: m.role,
            child: m.content.isEmpty && m.isStreaming
                ? const _TypingIndicator()
                : MarkdownBody(data: m.content),
          );
        }
        // User message: show media thumbnails above the text (if any).
        return MessageBubble(
          role: m.role,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m.mediaPaths.isNotEmpty) _messageMediaRow(m.mediaPaths),
              if (m.content.isNotEmpty && m.mediaPaths.isNotEmpty)
                const SizedBox(height: 6),
              if (m.content.isNotEmpty) Text(m.content),
            ],
          ),
        );
      },
    );
  }

  /// Inline media thumbnails rendered inside a user message bubble.
  /// Audio files show an audio icon instead of an image thumbnail.
  Widget _messageMediaRow(List<String> paths) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: paths.map((p) {
        final isAudio = p.endsWith('.m4a') ||
            p.endsWith('.aac') ||
            p.endsWith('.wav') ||
            p.endsWith('.mp3');
        if (isAudio) {
          return Container(
            width: 120,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.audio_file, color: Colors.indigo.shade400, size: 20),
                const SizedBox(width: 6),
                Text('语音消息',
                    style:
                        TextStyle(color: Colors.indigo.shade400, fontSize: 12)),
              ],
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child:
              Image.file(File(p), width: 120, height: 120, fit: BoxFit.cover),
        );
      }).toList(),
    );
  }

  Widget _inputBar() => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_attachedMedia.isNotEmpty) _mediaPreview(),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(children: [
              if (_isOmni)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.attach_file),
                  tooltip: '附件',
                  onSelected: (v) =>
                      v == 'gallery' ? _pickImage() : _takePhoto(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'gallery',
                        child: ListTile(
                          leading: Icon(Icons.photo_outlined),
                          title: Text('相册'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        )),
                    PopupMenuItem(
                        value: 'camera',
                        child: ListTile(
                          leading: Icon(Icons.camera_alt_outlined),
                          title: Text('拍照'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        )),
                  ],
                ),
              // Voice recording button — only for multimodal models.
              if (_isOmni)
                IconButton(
                  icon: Icon(
                    _isRecording ? Icons.stop : Icons.mic_outlined,
                    size: 22,
                    color: _isRecording ? Colors.red : null,
                  ),
                  tooltip: _isRecording ? '停止录音' : '语音输入',
                  onPressed: _hasSession ? _toggleRecording : null,
                ),
              // Agent mode toggle — only for text models.
              IconButton(
                icon: Icon(
                  _agentMode ? Icons.smart_toy : Icons.smart_toy_outlined,
                  size: 22,
                ),
                color:
                    _agentMode ? Theme.of(context).colorScheme.primary : null,
                tooltip: _agentMode ? 'Agent 已开启' : 'Agent 模式',
                onPressed: _isOmni
                    ? null
                    : () => setState(() => _agentMode = !_agentMode),
              ),
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: !_hasSession
                        ? '请先加载模型'
                        : _isOmni
                            ? '输入消息、附加图片或语音...'
                            : _agentMode
                                ? 'Agent 模式 — 输入问题，AI 可调用工具...'
                                : '输入消息...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              _isGenerating
                  ? IconButton.filled(
                      onPressed: _stop,
                      icon: const Icon(Icons.stop),
                      tooltip: '停止',
                    )
                  : IconButton.filled(
                      onPressed: _hasSession ? _send : null,
                      icon: const Icon(Icons.arrow_upward),
                      tooltip: '发送',
                    ),
            ]),
          ),
        ]),
      );

  /// Horizontal scrollable thumbnails of [_attachedMedia], each with a
  /// remove button. Audio files show a microphone icon instead of an image.
  Widget _mediaPreview() {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _attachedMedia.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final path = _attachedMedia[i];
          final isAudio = path.endsWith('.m4a') ||
              path.endsWith('.aac') ||
              path.endsWith('.wav') ||
              path.endsWith('.mp3');
          return Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: isAudio
                  ? Container(
                      width: 72,
                      height: 72,
                      color: Colors.indigo.shade100,
                      child: const Icon(Icons.audio_file,
                          size: 32, color: Colors.indigo),
                    )
                  : Image.file(File(path),
                      width: 72, height: 72, fit: BoxFit.cover),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: GestureDetector(
                onTap: () => _removeMedia(i),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _sessionDrawer() => Drawer(
        child: ListView(children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.indigo),
            child: Text('会话历史',
                style: TextStyle(color: Colors.white, fontSize: 20)),
          ),
          ..._sessions.map((s) => ListTile(
                selected: s.id == _current?.id,
                leading: const Icon(Icons.chat_bubble_outline),
                title:
                    Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _switchSession(s),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _deleteSession(s),
                ),
              )),
        ]),
      );
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}
