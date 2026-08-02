// Loads the model catalogue (from the bundled asset) and tracks which
// models are present on disk via FileStorageService.
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';
import '../services/file_storage_service.dart';

class ModelRepository {
  ModelRepository(this._storage);

  final FileStorageService _storage;
  List<ModelInfo>? _catalogue;

  /// The full catalogue of models available to download.
  Future<List<ModelInfo>> catalogue() async {
    if (_catalogue != null) return _catalogue!;
    final raw = await rootBundle.loadString('tools/model_list.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    _catalogue = (json['models'] as List<dynamic>)
        .map((m) => ModelInfo.fromJson(m as Map<String, dynamic>))
        .toList();
    return _catalogue!;
  }

  /// Models that are already downloaded and ready to load.
  Future<List<String>> downloadedModelIds() async {
    return _storage.listDownloadedModelIds();
  }

  /// True if the model directory exists and contains config.json.
  Future<bool> isDownloaded(String modelId) async {
    return _storage.isModelDownloaded(modelId);
  }

  Future<void> delete(String modelId) async {
    await _storage.deleteModel(modelId);
  }
}
