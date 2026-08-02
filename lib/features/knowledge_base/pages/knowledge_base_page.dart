// Knowledge base manager: list, add, and delete .txt documents used by
// the Agent's RAG (knowledge_search) tool.
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../data/services/file_storage_service.dart';

class KnowledgeBasePage extends StatefulWidget {
  const KnowledgeBasePage({super.key, required this.storage});

  final FileStorageService storage;

  @override
  State<KnowledgeBasePage> createState() => _KnowledgeBasePageState();
}

class _KnowledgeBasePageState extends State<KnowledgeBasePage> {
  List<_KbDoc> _docs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final dir = await widget.storage.getKnowledgeBaseDir();
    final docs = <_KbDoc>[];
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.txt')) {
          final stat = await entity.stat();
          final content = await entity.readAsString();
          docs.add(_KbDoc(
            file: entity,
            name: entity.path.split(Platform.pathSeparator).last,
            sizeBytes: stat.size,
            preview: content.length > 100
                ? '${content.substring(0, 100)}…'
                : content,
            charCount: content.length,
          ));
        }
      }
    }
    docs.sort((a, b) => a.name.compareTo(b.name));
    if (mounted) {
      setState(() {
        _docs = docs;
        _loading = false;
      });
    }
  }

  Future<void> _addDocument() async {
    final nameCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加文档'),
        content: SizedBox(
          width: double.maxFinite,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '文件名',
                    hintText: 'my_notes.txt',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return '请输入文件名';
                    if (!v.trim().endsWith('.txt')) return '文件名须以 .txt 结尾';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: contentCtrl,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: '文档内容',
                    hintText: '粘贴或输入文本内容…',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return '内容不能为空';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result != true) return;
    final dir = await widget.storage.getKnowledgeBaseDir();
    final name = nameCtrl.text.trim();
    final file = File('${dir.path}/$name');
    await file.writeAsString(contentCtrl.text);
    nameCtrl.dispose();
    contentCtrl.dispose();
    _reload();
    _snack('已添加 $name');
  }

  Future<void> _deleteDocument(_KbDoc doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文档'),
        content: Text('确定删除 ${doc.name}？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await doc.file.delete();
    _reload();
    _snack('已删除 ${doc.name}');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('知识库')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDocument,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _docs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.library_books_outlined,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text('知识库为空',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('点击 + 添加文档，或用 adb push 推送 .txt 文件',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 13)),
                      const SizedBox(height: 24),
                      // Show adb push hint
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 32),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const SelectableText(
                          'adb push notes.txt '
                          '/sdcard/Android/data/com.openagent.openagent/'
                          'files/knowledge_base/',
                          style: TextStyle(
                              fontFamily: 'monospace', fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _docs.length,
                  itemBuilder: (_, i) => _docCard(_docs[i]),
                ),
    );
  }

  Widget _docCard(_KbDoc doc) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(doc.name,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          '${_formatSize(doc.sizeBytes)} · ${doc.charCount} 字符',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: '删除',
          onPressed: () => _deleteDocument(doc),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(doc.preview,
                  style: TextStyle(
                      color: Colors.grey.shade700, fontSize: 13, height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _KbDoc {
  final File file;
  final String name;
  final int sizeBytes;
  final String preview;
  final int charCount;

  _KbDoc({
    required this.file,
    required this.name,
    required this.sizeBytes,
    required this.preview,
    required this.charCount,
  });
}
