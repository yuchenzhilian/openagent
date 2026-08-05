// File system helpers for model storage, session persistence and app config.
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

class FileStorageService {
  /// Base directory for large file storage.
  ///
  /// On Android we use the app-specific external storage directory
  /// (/storage/emulated/0/Android/data/<package>/files/) so models can be
  /// pushed via `adb push` without root. On iOS we fall back to the app's
  /// documents directory (sandboxed, not user-accessible).
  Future<Directory> _baseDir() async {
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) return external;
    }
    return getApplicationDocumentsDirectory();
  }

  /// Root directory holding all downloaded model folders.
  Future<Directory> getModelsDir() async {
    final baseDir = await _baseDir();
    final dir = Directory('${baseDir.path}/models');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Directory for user-uploaded knowledge base documents (.txt files).
  /// Used by the Agent's RAG tool for on-device retrieval.
  Future<Directory> getKnowledgeBaseDir() async {
    final baseDir = await _baseDir();
    final dir = Directory('${baseDir.path}/knowledge_base');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// JSON file path for H14 Agent long-term memory KV.
  /// Stored in the base dir next to models/knowledge_base so it survives
  /// app upgrades and user data clear is the only way to wipe it.
  Future<String> getAgentMemoryPath() async {
    final baseDir = await _baseDir();
    return '${baseDir.path}/agent_memory.json';
  }

  /// JSON file path for Milestone #10 MCP persistence (list of connected
  /// servers with transport params). Model owns save / load decisions; code
  /// never reads/writes this file on its own.
  Future<String> getMcpStatePath() async {
    final baseDir = await _baseDir();
    return '${baseDir.path}/mcp_state.json';
  }

  /// JSON file path for Milestone #11 Skills persistence (json skill specs +
  /// remember_enabled id list). Same ownership rules as mcp_state.
  Future<String> getSkillStatePath() async {
    final baseDir = await _baseDir();
    return '${baseDir.path}/skill_state.json';
  }

  /// Directory for a single model, e.g. .../models/Qwen3-0.6B-MNN/.
  Future<Directory> getModelDir(String modelId) async {
    final modelsDir = await getModelsDir();
    final dir = Directory('${modelsDir.path}/$modelId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Absolute path to a model's config.json (used by MnnLlmSession.load).
  Future<String> getModelConfigPath(String modelId) async {
    final dir = await getModelDir(modelId);
    return '${dir.path}/config.json';
  }

  Future<bool> isModelDownloaded(String modelId) async {
    final dir = await getModelDir(modelId);
    // config.json must exist - it's required by MnnLlmSession.load.
    final hasConfig = await File('${dir.path}/config.json').exists();
    if (!hasConfig) return false;
    // The weight file name varies across MNN model repos
    // (llm.mnn.weight, llm.mnn, model.mnn, ...). Instead of hard-coding
    // one name, check that at least one model artifact exists besides
    // config.json / llm_config.json / tokenizer.txt.
    final entries = await dir.list().toList();
    for (final e in entries) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (name == 'config.json' ||
          name == 'llm_config.json' ||
          name == 'tokenizer.txt' ||
          name.startsWith('.')) {
        continue;
      }
      // Found a non-config artifact (e.g. llm.mnn, llm.mnn.weight,
      // embedding.mnn, ...). Treat the model as downloaded.
      return true;
    }
    return false;
  }

  Future<void> deleteModel(String modelId) async {
    final dir = await getModelDir(modelId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<List<String>> listDownloadedModelIds() async {
    final modelsDir = await getModelsDir();
    if (!await modelsDir.exists()) return const [];
    final entries = await modelsDir.list().toList();
    final result = <String>[];
    for (final d in entries.whereType<Directory>()) {
      final modelId = d.path.split(Platform.pathSeparator).last;
      // Only include models that are fully downloaded (both config.json
      // and llm.mnn.weight exist). This prevents interrupted downloads
      // from appearing as "downloaded" in the model market.
      if (await isModelDownloaded(modelId)) {
        result.add(modelId);
      }
    }
    return result;
  }

  // ---- App config persistence ----

  Future<AppConfig> loadAppConfig() async {
    final file = await _configFile();
    if (!await file.exists()) return const AppConfig();
    return AppConfig.decode(await file.readAsString());
  }

  Future<void> saveAppConfig(AppConfig config) async {
    final file = await _configFile();
    await file.writeAsString(config.encode());
  }

  Future<File> _configFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/app_config.json');
  }

  // ---- Chat sessions persistence ----

  Future<File> sessionsFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/chat_sessions.json');
  }
}
