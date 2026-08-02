// Settings: sampling parameters and system prompt. Loads the current
// AppConfig from disk on init, and persists changes via FileStorageService.
import 'package:flutter/material.dart';

import '../../../data/models/models.dart';
import '../../../data/services/file_storage_service.dart';

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

  @override
  void initState() {
    super.initState();
    _systemPromptCtrl = TextEditingController();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    _config = await widget.storage.loadAppConfig();
    _sampling = _config.sampling;
    _systemPromptCtrl.text = _config.systemPrompt;
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final config = _config.copyWith(
      systemPrompt: _systemPromptCtrl.text.trim(),
      sampling: _sampling,
    );
    await widget.storage.saveAppConfig(config);
    widget.onChanged(config);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('设置已保存')));
    }
  }

  @override
  void dispose() {
    _systemPromptCtrl.dispose();
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
        FilledButton(onPressed: _save, child: const Text('保存设置')),
      ]),
    );
  }

  Widget _sectionTitle(String text) => Text(text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600));

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
