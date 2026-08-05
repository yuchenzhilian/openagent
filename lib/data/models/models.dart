// Data models for OpenAgent.
//
// Hand-written immutable classes (no freezed/codegen) so the project compiles
// without `build_runner`. Each model has copyWith + JSON for simple
// persistence via shared_preferences / file storage.
import 'dart:convert';

/// Role of a chat message.
enum MessageRole { system, user, assistant }

MessageRole _roleFromString(String s) => switch (s) {
      'system' => MessageRole.system,
      'assistant' => MessageRole.assistant,
      _ => MessageRole.user,
    };
String _roleToString(MessageRole r) => switch (r) {
      MessageRole.system => 'system',
      MessageRole.assistant => 'assistant',
      MessageRole.user => 'user',
    };

/// A single message in a conversation.
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isStreaming = false,
    this.mediaPaths = const [],
  }) : timestamp = timestamp ?? DateTime.now();

  final MessageRole role;
  String content;
  final DateTime timestamp;
  bool isStreaming;

  /// File paths of images / audio attached to this message (user messages
  /// only). Empty for text-only turns. Persisted so history replay shows the
  /// original attachments.
  final List<String> mediaPaths;

  ChatMessage copyWith({
    MessageRole? role,
    String? content,
    DateTime? timestamp,
    bool? isStreaming,
    List<String>? mediaPaths,
  }) =>
      ChatMessage(
        role: role ?? this.role,
        content: content ?? this.content,
        timestamp: timestamp ?? this.timestamp,
        isStreaming: isStreaming ?? this.isStreaming,
        mediaPaths: mediaPaths ?? this.mediaPaths,
      );

  Map<String, dynamic> toJson() => {
        'role': _roleToString(role),
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        if (mediaPaths.isNotEmpty) 'media_paths': mediaPaths,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: _roleFromString(j['role'] as String? ?? 'user'),
        content: j['content'] as String? ?? '',
        timestamp: j['timestamp'] != null
            ? (DateTime.tryParse(j['timestamp'] as String? ?? '') ??
                DateTime.now())
            : null,
        mediaPaths: (j['media_paths'] as List?)?.whereType<String>().toList() ??
            const [],
      );
}

/// A conversation session.
class ChatSession {
  ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
    this.modelId,
  });

  final String id;
  String title;
  List<ChatMessage> messages;
  final DateTime createdAt;
  String? modelId;

  /// Maximum number of messages to keep. When exceeded, oldest messages are
  /// trimmed from the beginning. Null means no limit.
  static const int? maxMessages = 200;

  /// Appends a message, trimming oldest if [maxMessages] is exceeded.
  void addMessage(ChatMessage msg) {
    messages.add(msg);
    if (maxMessages != null && messages.length > maxMessages!) {
      messages = messages.sublist(messages.length - maxMessages!);
    }
  }

  /// Clears all messages.
  void reset() {
    messages = [];
  }

  ChatSession copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    String? modelId,
  }) =>
      ChatSession(
        id: id ?? this.id,
        title: title ?? this.title,
        messages: messages ?? List.of(this.messages),
        createdAt: createdAt ?? this.createdAt,
        modelId: modelId ?? this.modelId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'modelId': modelId,
      };

  factory ChatSession.fromJson(Map<String, dynamic> j) => ChatSession(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '新对话',
        messages: (j['messages'] as List? ?? [])
            .map((m) => ChatMessage.fromJson(
                m is Map<String, dynamic> ? m : <String, dynamic>{}))
            .toList(),
        createdAt: j['createdAt'] != null
            ? (DateTime.tryParse(j['createdAt'] as String? ?? '') ??
                DateTime.now())
            : DateTime.now(),
        modelId: j['modelId'] as String?,
      );
}

/// Whether a model is text-only or multimodal.
enum ModelType { text, omni }

/// Source of the LLM (on-device or cloud).
enum ModelSource { local, cloud }

/// Cloud LLM configuration. Empty [apiKey] for Ollama (no key required).
class CloudModelConfig {
  const CloudModelConfig({
    this.provider = 'openai',
    this.baseUrl = 'https://api.openai.com/v1',
    this.apiKey = '',
    this.model = 'gpt-4o',
    this.systemPrompt = '',
    this.temperature = 0.7,
    this.maxTokens = 2048,
  });

  /// Provider id: openai / deepseek / qwen / doubao / groq / ollama / anthropic / custom
  final String provider;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String systemPrompt;
  final double temperature;
  final int maxTokens;

  CloudModelConfig copyWith({
    String? provider,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? systemPrompt,
    double? temperature,
    int? maxTokens,
  }) =>
      CloudModelConfig(
        provider: provider ?? this.provider,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        temperature: temperature ?? this.temperature,
        maxTokens: maxTokens ?? this.maxTokens,
      );

  bool get isConfigured => model.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'base_url': baseUrl,
        'api_key': apiKey,
        'model': model,
        'system_prompt': systemPrompt,
        'temperature': temperature,
        'max_tokens': maxTokens,
      };

  factory CloudModelConfig.fromJson(Map<String, dynamic> j) => CloudModelConfig(
        provider: j['provider'] as String? ?? 'openai',
        baseUrl: j['base_url'] as String? ?? 'https://api.openai.com/v1',
        apiKey: j['api_key'] as String? ?? '',
        model: j['model'] as String? ?? 'gpt-4o',
        systemPrompt: j['system_prompt'] as String? ?? '',
        temperature: (j['temperature'] as num?)?.toDouble() ?? 0.7,
        maxTokens: (j['max_tokens'] as num?)?.toInt() ?? 2048,
      );
}

/// Metadata describing a downloadable model (mirrors tools/model_list.json).
class ModelInfo {
  const ModelInfo({
    required this.id,
    required this.name,
    required this.description,
    this.sizeMb,
    this.ramMb,
    required this.quant,
    required this.type,
    required this.downloadUrl,
    required this.configFilename,
  });

  final String id;
  final String name;
  final String description;
  final int? sizeMb;
  final int? ramMb;
  final String quant;
  final ModelType type;
  final String downloadUrl;
  final String configFilename;

  factory ModelInfo.fromJson(Map<String, dynamic> j) => ModelInfo(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        description: j['description'] as String? ?? '',
        sizeMb: (j['size_mb'] as num?)?.toInt(),
        ramMb: (j['ram_mb'] as num?)?.toInt(),
        quant: j['quant'] as String? ?? 'Q4',
        type:
            (j['type'] as String?) == 'omni' ? ModelType.omni : ModelType.text,
        downloadUrl: j['download_url'] as String? ?? '',
        configFilename: j['config_filename'] as String? ?? 'config.json',
      );
}

/// Sampling / generation parameters passed to MNN-LLM at runtime.
class SamplingConfig {
  const SamplingConfig({
    this.temperature = 0.7,
    this.topK = 20,
    this.topP = 0.8,
    this.maxNewTokens = 1024,
    this.repetitionPenalty = 1.05,
  });

  final double temperature;
  final int topK;
  final double topP;
  final int maxNewTokens;
  final double repetitionPenalty;

  SamplingConfig copyWith({
    double? temperature,
    int? topK,
    double? topP,
    int? maxNewTokens,
    double? repetitionPenalty,
  }) =>
      SamplingConfig(
        temperature: temperature ?? this.temperature,
        topK: topK ?? this.topK,
        topP: topP ?? this.topP,
        maxNewTokens: maxNewTokens ?? this.maxNewTokens,
        repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
      );

  /// Serialise to the JSON shape expected by mnn_llm_set_config.
  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'top_k': topK,
        'top_p': topP,
        'max_new_tokens': maxNewTokens,
        'repetition_penalty': repetitionPenalty,
      };

  factory SamplingConfig.fromJson(Map<String, dynamic> j) => SamplingConfig(
        temperature: (j['temperature'] as num?)?.toDouble() ?? 0.7,
        topK: (j['top_k'] as num?)?.toInt() ?? 20,
        topP: (j['top_p'] as num?)?.toDouble() ?? 0.8,
        maxNewTokens: (j['max_new_tokens'] as num?)?.toInt() ?? 1024,
        repetitionPenalty:
            (j['repetition_penalty'] as num?)?.toDouble() ?? 1.05,
      );
}

/// App-wide configuration persisted across launches.
class AppConfig {
  const AppConfig({
    this.activeModelId,
    this.systemPrompt = '',
    this.sampling = const SamplingConfig(),
    this.automation = const AutomationPermissionStatus(),
    this.modelSource = ModelSource.local,
    this.cloud = const CloudModelConfig(),
  });

  final String? activeModelId;
  final String systemPrompt;
  final SamplingConfig sampling;
  final AutomationPermissionStatus automation;
  final ModelSource modelSource;
  final CloudModelConfig cloud;

  AppConfig copyWith({
    String? activeModelId,
    String? systemPrompt,
    SamplingConfig? sampling,
    AutomationPermissionStatus? automation,
    ModelSource? modelSource,
    CloudModelConfig? cloud,
  }) =>
      AppConfig(
        activeModelId: activeModelId ?? this.activeModelId,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        sampling: sampling ?? this.sampling,
        automation: automation ?? this.automation,
        modelSource: modelSource ?? this.modelSource,
        cloud: cloud ?? this.cloud,
      );

  Map<String, dynamic> toJson() => {
        'active_model_id': activeModelId,
        'system_prompt': systemPrompt,
        'sampling': sampling.toJson(),
        'automation': automation.toJson(),
        'model_source': modelSource.name,
        'cloud': cloud.toJson(),
      };

  factory AppConfig.fromJson(Map<String, dynamic> j) => AppConfig(
        activeModelId: j['active_model_id'] as String?,
        systemPrompt: j['system_prompt'] as String? ?? '',
        sampling: j['sampling'] != null && j['sampling'] is Map
            ? SamplingConfig.fromJson(j['sampling'] as Map<String, dynamic>)
            : const SamplingConfig(),
        automation: j['automation'] != null && j['automation'] is Map
            ? AutomationPermissionStatus.fromJson(
                j['automation'] as Map<String, dynamic>)
            : const AutomationPermissionStatus(),
        modelSource: ModelSource.values.firstWhere(
          (e) => e.name == (j['model_source'] as String? ?? 'local'),
          orElse: () => ModelSource.local,
        ),
        cloud: j['cloud'] != null && j['cloud'] is Map
            ? CloudModelConfig.fromJson(j['cloud'] as Map<String, dynamic>)
            : const CloudModelConfig(),
      );

  String encode() => jsonEncode(toJson());
  static AppConfig decode(String s) {
    if (s.isEmpty) return const AppConfig();
    try {
      final decoded = jsonDecode(s);
      if (decoded is! Map) return const AppConfig();
      return AppConfig.fromJson(decoded as Map<String, dynamic>);
    } catch (_) {
      return const AppConfig();
    }
  }
}

/// Runtime status of the Android automation permission layers.
///
/// Used by the Permission Guide page to show authorised / not-yet-granted
/// indicators, and by the Agent runtime to pick the best backend (L1 or L2).
class AutomationPermissionStatus {
  const AutomationPermissionStatus({
    this.accessibilityEnabled = false,
    this.shizukuGranted = false,
    this.screenshotGranted = false,
    this.usageStatsGranted = false,
    this.notificationListenerGranted = false,
    this.warningDismissed = false,
  });

  /// L1 基础层：Android 无障碍服务是否已启用。
  final bool accessibilityEnabled;

  /// L2 进阶层：Shizuku 高级权限是否已授权。
  final bool shizukuGranted;

  /// MediaProjection 截图权限是否授权过。
  final bool screenshotGranted;

  /// PACKAGE_USAGE_STATS (应用使用统计)：让 Agent 能查到当前前台 App。
  final bool usageStatsGranted;

  /// 通知监听权限是否已启用。
  final bool notificationListenerGranted;

  /// 用户是否已了解风险并点击了"我知道了"。
  final bool warningDismissed;

  AutomationPermissionStatus copyWith({
    bool? accessibilityEnabled,
    bool? shizukuGranted,
    bool? screenshotGranted,
    bool? usageStatsGranted,
    bool? notificationListenerGranted,
    bool? warningDismissed,
  }) =>
      AutomationPermissionStatus(
        accessibilityEnabled: accessibilityEnabled ?? this.accessibilityEnabled,
        shizukuGranted: shizukuGranted ?? this.shizukuGranted,
        screenshotGranted: screenshotGranted ?? this.screenshotGranted,
        usageStatsGranted: usageStatsGranted ?? this.usageStatsGranted,
        notificationListenerGranted:
            notificationListenerGranted ?? this.notificationListenerGranted,
        warningDismissed: warningDismissed ?? this.warningDismissed,
      );

  Map<String, dynamic> toJson() => {
        'accessibility': accessibilityEnabled,
        'shizuku': shizukuGranted,
        'screenshot': screenshotGranted,
        'usage_stats': usageStatsGranted,
        'notification_listener': notificationListenerGranted,
        'warning_dismissed': warningDismissed,
      };

  factory AutomationPermissionStatus.fromJson(Map<String, dynamic> j) =>
      AutomationPermissionStatus(
        accessibilityEnabled: j['accessibility'] as bool? ?? false,
        shizukuGranted: j['shizuku'] as bool? ?? false,
        screenshotGranted: j['screenshot'] as bool? ?? false,
        usageStatsGranted: j['usage_stats'] as bool? ?? false,
        notificationListenerGranted:
            j['notification_listener'] as bool? ?? false,
        warningDismissed: j['warning_dismissed'] as bool? ?? false,
      );
}
