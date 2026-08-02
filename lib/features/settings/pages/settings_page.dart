// Settings: sampling parameters and system prompt. Loads the current
// AppConfig from disk on init, and persists changes via FileStorageService.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mnn_llm/mnn_llm.dart';

import '../../../data/models/models.dart';
import '../../../data/services/file_storage_service.dart';

class _CloudPreset {
  const _CloudPreset(this.baseUrl, this.model);
  final String baseUrl;
  final String model;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.storage,
    required this.onChanged,
  });

  final FileStorageService storage;
  final ValueChanged<AppConfig> onChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SamplingConfig _sampling = const SamplingConfig();
  AppConfig _config = const AppConfig();
  late TextEditingController _systemPromptCtrl;
  bool _loaded = false;

  Future<void> _loadConfig() async {
    _config = await widget.storage.loadAppConfig();
    _sampling = _config.sampling;
    _systemPromptCtrl.text = _config.systemPrompt;
    _cloud = _config.cloud;
    _useCloud = _config.modelSource == ModelSource.cloud;
    _cloudProviderCtrl.text = _cloud.provider;
    _cloudBaseUrlCtrl.text = _cloud.baseUrl;
    _cloudApiKeyCtrl.text = _cloud.apiKey;
    _cloudModelCtrl.text = _cloud.model;
    _cloudSystemPromptCtrl.text = _cloud.systemPrompt;
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final config = _config.copyWith(
      systemPrompt: _systemPromptCtrl.text.trim(),
      sampling: _sampling,
      modelSource: _useCloud ? ModelSource.cloud : ModelSource.local,
      cloud: _cloud,
    );
    await widget.storage.saveAppConfig(config);
    widget.onChanged(config);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('设置已保存')));
    }
  }

  // ---- Cloud LLM state -------------------------------------------------
  bool _useCloud = false;
  late CloudModelConfig _cloud = const CloudModelConfig();
  late TextEditingController _cloudProviderCtrl;
  late TextEditingController _cloudBaseUrlCtrl;
  late TextEditingController _cloudApiKeyCtrl;
  late TextEditingController _cloudModelCtrl;
  late TextEditingController _cloudSystemPromptCtrl;
  String? _cloudTestStatus;

  @override
  void initState() {
    super.initState();
    _systemPromptCtrl = TextEditingController();
    _cloudProviderCtrl = TextEditingController();
    _cloudBaseUrlCtrl = TextEditingController();
    _cloudApiKeyCtrl = TextEditingController();
    _cloudModelCtrl = TextEditingController();
    _cloudSystemPromptCtrl = TextEditingController();
    _loadConfig();
  }

  @override
  void dispose() {
    _systemPromptCtrl.dispose();
    _cloudProviderCtrl.dispose();
    _cloudBaseUrlCtrl.dispose();
    _cloudApiKeyCtrl.dispose();
    _cloudModelCtrl.dispose();
    _cloudSystemPromptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _sectionTitle('采样参数'),
        _slider(
          label: 'temperature',
          value: _sampling.temperature,
          min: 0, max: 2, divisions: 20,
          format: (v) => v.toStringAsFixed(2),
          onChanged: (v) => setState(() =>
              _sampling = _sampling.copyWith(temperature: v)),
        ),
        _slider(
          label: 'top_k',
          value: _sampling.topK.toDouble(),
          min: 1, max: 100, divisions: 99,
          format: (v) => v.toInt().toString(),
          onChanged: (v) => setState(() =>
              _sampling = _sampling.copyWith(topK: v.toInt())),
        ),
        _slider(
          label: 'top_p',
          value: _sampling.topP,
          min: 0.1, max: 1, divisions: 18,
          format: (v) => v.toStringAsFixed(2),
          onChanged: (v) => setState(() =>
              _sampling = _sampling.copyWith(topP: v)),
        ),
        _slider(
          label: 'max_new_tokens',
          value: _sampling.maxNewTokens.toDouble(),
          min: 64, max: 4096, divisions: 63,
          format: (v) => v.toInt().toString(),
          onChanged: (v) => setState(() =>
              _sampling = _sampling.copyWith(maxNewTokens: v.toInt())),
        ),
        _slider(
          label: 'repetition_penalty',
          value: _sampling.repetitionPenalty,
          min: 1, max: 2, divisions: 20,
          format: (v) => v.toStringAsFixed(2),
          onChanged: (v) => setState(() =>
              _sampling = _sampling.copyWith(repetitionPenalty: v)),
        ),
        const SizedBox(height: 16),
        _sectionTitle('System Prompt'),
        const SizedBox(height: 8),
        TextField(
          controller: _systemPromptCtrl,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '设定模型角色，如：你是一个有帮助的中文助手。',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        _sectionTitle('云端 LLM（可选）'),
        SwitchListTile(
          title: const Text('使用云端 LLM 替代本地推理'),
          subtitle: const Text('开启后使用链接 + API key + 模型 id 接入云端。'),
          value: _useCloud,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => setState(() => _useCloud = v),
        ),
        if (_useCloud) ..._buildCloudSection(),
        const SizedBox(height: 24),
        FilledButton(onPressed: _save, child: const Text('保存设置')),
      ]),
    );
  }

  Widget _sectionTitle(String text) => Text(text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600));

  List<Widget> _buildCloudSection() {
    void applyProviderPreset(String provider) {
      setState(() {
        _cloudProviderCtrl.text = provider;
        final preset = _presetFor(provider);
        _cloudBaseUrlCtrl.text = preset.baseUrl;
        _cloudModelCtrl.text = preset.model;
      });
    }

    return [
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final p in const [
            'openai',
            'deepseek',
            'qwen',
            'doubao',
            'groq',
            'ollama',
            'anthropic',
            'custom',
          ])
            ActionChip(
              label: Text(p),
              onPressed: () => applyProviderPreset(p),
            ),
        ],
      ),
      const SizedBox(height: 8),
      _textField(_cloudProviderCtrl, 'Provider (openai/deepseek/qwen/doubao/groq/ollama/anthropic/custom)'),
      _textField(_cloudBaseUrlCtrl, 'Base URL（留空用默认，可自定义代理）'),
      _textField(_cloudApiKeyCtrl, 'API Key（Ollama 可填任意值）', obscure: true),
      _textField(_cloudModelCtrl, '模型 ID (model id)'),
      _textField(_cloudSystemPromptCtrl, '云端 System Prompt（可选，留空用全局）', maxLines: 3),
      const SizedBox(height: 8),
      Row(children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.wifi_tethering),
          label: const Text('测试连接'),
          onPressed: _testCloudConnection,
        ),
        const SizedBox(width: 12),
        if (_cloudTestStatus != null)
          Expanded(child: Text(_cloudTestStatus!, style: const TextStyle(fontSize: 12))),
      ]),
    ];
  }

  Widget _textField(TextEditingController c, String label,
      {int maxLines = 1, bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: c,
        maxLines: obscure ? 1 : maxLines,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) {
          // Sync into the config so the Save button picks it up.
          _cloud = _cloud.copyWith(
            provider: _cloudProviderCtrl.text.trim(),
            baseUrl: _cloudBaseUrlCtrl.text.trim(),
            apiKey: _cloudApiKeyCtrl.text,
            model: _cloudModelCtrl.text.trim(),
            systemPrompt: _cloudSystemPromptCtrl.text,
          );
        },
      ),
    );
  }

  _CloudPreset _presetFor(String p) {
    switch (p) {
      case 'openai':
        return const _CloudPreset(
            'https://api.openai.com/v1', 'gpt-4o-mini');
      case 'deepseek':
        return const _CloudPreset(
            'https://api.deepseek.com/v1', 'deepseek-chat');
      case 'qwen':
        return const _CloudPreset(
            'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-plus');
      case 'doubao':
        return const _CloudPreset(
            'https://ark.cn-beijing.volces.com/api/v3', 'doubao-pro-32k');
      case 'groq':
        return const _CloudPreset(
            'https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile');
      case 'ollama':
        return const _CloudPreset('http://localhost:11434/v1', 'qwen2.5:7b');
      case 'anthropic':
        return const _CloudPreset('https://api.anthropic.com', 'claude-3-5-sonnet-latest');
      case 'custom':
      default:
        return const _CloudPreset('', '');
    }
  }

  Future<void> _testCloudConnection() async {
    setState(() => _cloudTestStatus = '正在测试...');
    final cfg = _cloud.copyWith(
      provider: _cloudProviderCtrl.text.trim(),
      baseUrl: _cloudBaseUrlCtrl.text.trim(),
      apiKey: _cloudApiKeyCtrl.text,
      model: _cloudModelCtrl.text.trim(),
      systemPrompt: _cloudSystemPromptCtrl.text,
    );
    if (cfg.model.isEmpty) {
      setState(() => _cloudTestStatus = '❌ 缺少 model id');
      return;
    }
    try {
      // Build a session with a tight timeout to avoid hanging the UI.
      final session = await CloudLlmSession.create(
        CloudLlmConfig(
          provider: _mapProvider(cfg.provider),
          apiKey: cfg.apiKey,
          model: cfg.model,
          baseUrl: cfg.baseUrl.isEmpty ? null : cfg.baseUrl,
          maxTokens: 8,
          requestTimeoutSeconds: 15,
        ),
      );
      final stream = session.chatStream('hi');
      final first = await stream.first.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('响应超时'),
      );
      await session.dispose();
      setState(() => _cloudTestStatus = '✅ 成功（"$first"...）');
    } catch (e) {
      setState(() => _cloudTestStatus = '❌ 失败: $e');
    }
  }

  CloudProvider _mapProvider(String p) {
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

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) format,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min, max: max, divisions: divisions,
            label: format(value),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 48, child: Text(format(value), style: const TextStyle(fontSize: 12))),
      ]),
    );
  }
}
