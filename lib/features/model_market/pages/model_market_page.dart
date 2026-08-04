// Model market: browse available models, download with progress,
// delete, and set the active model for chat.
import 'package:flutter/material.dart';

import '../../../data/models/models.dart';
import '../../../data/repositories/model_repository.dart';
import '../../../data/services/file_storage_service.dart';
import '../../../data/services/model_download_service.dart';

class ModelMarketPage extends StatefulWidget {
  const ModelMarketPage({
    super.key,
    required this.storage,
    required this.onActiveModelChanged,
  });

  final FileStorageService storage;
  final Future<void> Function(String?) onActiveModelChanged;

  @override
  State<ModelMarketPage> createState() => _ModelMarketPageState();
}

class _ModelMarketPageState extends State<ModelMarketPage> {
  late final ModelRepository _repo;
  late final ModelDownloadService _downloader;
  List<ModelInfo> _catalogue = const [];
  Set<String> _downloaded = {};
  String? _downloadingId;
  String _downloadingFile = '';
  double _progress = 0;
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _repo = ModelRepository(widget.storage);
    _downloader = ModelDownloadService(widget.storage);
    _load();
  }

  Future<void> _load() async {
    _catalogue = await _repo.catalogue();
    _downloaded = (await _repo.downloadedModelIds()).toSet();
    // Load the active model from config so the "当前使用" indicator
    // is correct when the page is recreated (e.g. after navigating
    // back from chat).
    final config = await widget.storage.loadAppConfig();
    _activeId = config.activeModelId;
    if (mounted) setState(() {});
  }

  Future<void> _download(ModelInfo model) async {
    // Cancel any in-progress download before starting a new one.
    await _downloader.cancel();
    setState(() {
      _downloadingId = model.id;
      _downloadingFile = '';
      _progress = 0;
    });
    var completed = false;
    await for (final p in _downloader.download(model)) {
      if (!mounted || _downloadingId != model.id) return;
      if (p.isError) {
        setState(() => _downloadingId = null);
        _snack('下载失败 (${p.file}): ${p.error}');
        return;
      }
      if (p.fraction >= 1.0) completed = true;
      setState(() {
        _progress = p.fraction;
        _downloadingFile = p.file;
      });
    }
    if (!mounted || _downloadingId != model.id) return;
    // Stream ended without reaching 100% — likely cancelled.
    if (!completed) {
      setState(() => _downloadingId = null);
      return;
    }
    setState(() {
      _downloaded.add(model.id);
      _downloadingId = null;
      _downloadingFile = '';
    });
    // Auto-activate the model after download so the user can start
    // chatting immediately without manually clicking "使用".
    // _setActive shows its own confirmation snack.
    await _setActive(model);
  }

  Future<void> _cancelDownload() async {
    await _downloader.cancel();
    setState(() {
      _downloadingId = null;
      _downloadingFile = '';
      _progress = 0;
    });
    _snack('已取消下载');
  }

  Future<void> _delete(ModelInfo model) async {
    await _repo.delete(model.id);
    setState(() {
      _downloaded.remove(model.id);
      if (_activeId == model.id) _activeId = null;
    });
    widget.onActiveModelChanged(null);
    _snack('已删除 ${model.name}');
  }

  Future<void> _setActive(ModelInfo model) async {
    setState(() => _activeId = model.id);
    await widget.onActiveModelChanged(model.id);
    _snack('已切换为 ${model.name}，返回对话页即可使用');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _downloader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模型市场')),
      body: ListView.builder(
        itemCount: _catalogue.length,
        itemBuilder: (_, i) => _modelCard(_catalogue[i]),
      ),
    );
  }

  Widget _modelCard(ModelInfo m) {
    final isDownloaded = _downloaded.contains(m.id);
    final isDownloading = _downloadingId == m.id;
    final isActive = _activeId == m.id;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(m.name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Chip(
              label: Text(m.quant, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            if (m.type == ModelType.omni)
              const Chip(
                label: Text('多模态', style: TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
              ),
          ]),
          const SizedBox(height: 4),
          Text(m.description,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
              '${((m.sizeMb ?? 0) / 1024).toStringAsFixed(1)} GB · 需 ${(m.ramMb ?? 0) ~/ 1024 + 1}GB 内存',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          if (isDownloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text(
                  _downloadingFile.isEmpty
                      ? '准备中… ${(_progress * 100).toStringAsFixed(0)}%'
                      : '$_downloadingFile  ${(_progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: _cancelDownload,
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: '取消',
                ),
              ),
            ]),
          ] else ...[
            const SizedBox(height: 8),
            Row(children: [
              if (!isDownloaded)
                FilledButton.tonalIcon(
                  onPressed: () => _download(m),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('下载'),
                )
              else ...[
                FilledButton.icon(
                  onPressed: isActive ? null : () => _setActive(m),
                  icon:
                      Icon(isActive ? Icons.check : Icons.play_arrow, size: 18),
                  label: Text(isActive ? '当前使用' : '使用'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _delete(m),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: '删除',
                ),
              ],
            ]),
          ],
        ]),
      ),
    );
  }
}
