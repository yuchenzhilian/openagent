// Downloads MNN-LLM model files from ModelScope into device storage.
//
// A model is a directory of several files (config.json, llm.mnn,
// llm.mnn.weight, llm_config.json, tokenizer.txt, …). The exact file set
// varies per model, so we fetch the repo file listing from the ModelScope
// API and download every blob that looks like a model artifact.
//
// Progress is reported as a byte-level fraction across all files, so the
// progress bar moves smoothly even when one file (llm.mnn.weight) is 99 %
// of the total size.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../models/models.dart';
import 'file_storage_service.dart';

class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.modelId,
    required this.file,
    required this.completedFiles,
    required this.totalFiles,
    required this.fraction,
    this.error,
  });

  final String modelId;
  final String file;
  final int completedFiles;
  final int totalFiles;
  final double fraction; // 0.0 .. 1.0
  final String? error;

  bool get isError => error != null;
}

class ModelDownloadService {
  ModelDownloadService(this._storage);

  final FileStorageService _storage;
  Dio? _dio;
  CancelToken? _cancelToken;

  // Fallback file set used when the ModelScope file-listing API is
  // unreachable. Not every model ships every file — downloads are
  // best-effort and 404s are skipped rather than treated as fatal.
  static const _fallbackFiles = <String>[
    'config.json',
    'llm.mnn',
    'llm.mnn.weight',
    'llm_config.json',
    'tokenizer.txt',
  ];

  // Files that are never model artifacts and should be skipped.
  static const _skipFiles = <String>{
    '.gitattributes',
    'configuration.json',
    'README.md',
    'LICENSE',
  };

  Dio _ensureDio() {
    _dio ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 30),
    ));
    return _dio!;
  }

  Stream<ModelDownloadProgress> download(ModelInfo model) {
    final controller = StreamController<ModelDownloadProgress>();
    _runDownload(model, controller);
    return controller.stream;
  }

  Future<void> _runDownload(
    ModelInfo model,
    StreamController<ModelDownloadProgress> controller,
  ) async {
    final dio = _ensureDio();
    _cancelToken = CancelToken();
    try {
      final dir = await _storage.getModelDir(model.id);
      final fileBaseUrl = buildFileBaseUrl(model.downloadUrl);
      final files = await _fetchFileListWithSize(model.downloadUrl);

      final totalBytes = files.fold<int>(0, (sum, f) => sum + f.size);
      var downloadedBytes = 0;
      var completedFiles = 0;

      for (final file in files) {
        final savePath = '${dir.path}/${file.name}';
        // Download to a .part temp file first, then rename on success.
        // This ensures the final file only exists if the download
        // completed fully — otherwise isModelDownloaded() could mistake
        // a partially-written llm.mnn.weight for a complete one.
        final partPath = '$savePath.part';
        try {
          await dio.download(
            '$fileBaseUrl${file.name}',
            partPath,
            options: Options(receiveTimeout: const Duration(minutes: 30)),
            cancelToken: _cancelToken,
            onReceiveProgress: (received, total) {
              if (total <= 0) return;
              final double fraction;
              if (totalBytes > 0) {
                fraction =
                    ((downloadedBytes + received) / totalBytes).clamp(0.0, 1.0);
              } else {
                // Fallback (file sizes unknown): estimate progress as
                // (completed files + intra-file fraction) / total files.
                fraction = files.isEmpty
                    ? 0
                    : ((completedFiles + received / total) / files.length)
                        .clamp(0.0, 1.0);
              }
              controller.add(ModelDownloadProgress(
                modelId: model.id,
                file: file.name,
                completedFiles: completedFiles,
                totalFiles: files.length,
                fraction: fraction,
              ));
            },
          );
          // Download completed — atomically rename .part to final name.
          await File(partPath).rename(savePath);
        } on DioException catch (e) {
          // Clean up the partial temp file on any failure.
          await _safeDelete(partPath);
          // 404 = file doesn't exist in this model repo; skip gracefully.
          if (e.response?.statusCode == 404) {
            continue;
          }
          // User cancelled — don't emit error, just stop silently.
          // The caller (UI) already shows a "cancelled" message.
          if (e.type == DioExceptionType.cancel) {
            return;
          }
          controller.add(ModelDownloadProgress(
            modelId: model.id,
            file: file.name,
            completedFiles: completedFiles,
            totalFiles: files.length,
            fraction: totalBytes > 0
                ? downloadedBytes / totalBytes
                : (files.isEmpty ? 0 : completedFiles / files.length),
            error: _friendlyError(e),
          ));
          return;
        }
        downloadedBytes += file.size;
        completedFiles++;
      }

      controller.add(ModelDownloadProgress(
        modelId: model.id,
        file: '',
        completedFiles: files.length,
        totalFiles: files.length,
        fraction: 1.0,
      ));
    } catch (e) {
      controller.add(ModelDownloadProgress(
        modelId: model.id,
        file: '',
        completedFiles: 0,
        totalFiles: 0,
        fraction: 0,
        error: e is DioException ? _friendlyError(e) : e.toString(),
      ));
    } finally {
      _cancelToken = null;
      await controller.close();
    }
  }

  Future<void> cancel() async {
    _cancelToken?.cancel('user cancelled');
    _dio?.close(force: true);
    _dio = null;
  }

  /// Fetch the list of model files (with sizes) from the ModelScope
  /// repo-file API. Falls back to [_fallbackFiles] (with size 0) if the
  /// API is unreachable — in that case progress is file-count-based.
  Future<List<_ModelFile>> _fetchFileListWithSize(String repoUrl) async {
    final apiUrl = buildFileListUrl(repoUrl);
    try {
      final resp = await _ensureDio().get<dynamic>(apiUrl);
      final parsed = parseFileListResponse(resp.data);
      if (parsed.isEmpty) return _fallbackFilesAsModelFiles();
      return parsed.map((f) => _ModelFile(f.name, f.size)).toList();
    } catch (_) {
      return _fallbackFilesAsModelFiles();
    }
  }

  /// Parses a ModelScope file-listing API response into (name, size) pairs.
  ///
  /// Non-artifact files (.gitattributes, README.md, LICENSE, configuration.json,
  /// dotfiles, markdown) are filtered out. Returns an empty list if the
  /// response structure is unexpected.
  static List<({String name, int size})> parseFileListResponse(dynamic data) {
    if (data is! Map) return const [];
    final files = data['Data']?['Files'];
    if (files is! List) return const [];
    final result = <({String name, int size})>[];
    for (final f in files) {
      if (f is! Map) continue;
      final path = f['Path'];
      if (path is! String) continue;
      if (_skipFiles.contains(path)) continue;
      if (path.startsWith('.') || path.endsWith('.md')) continue;
      final size = (f['Size'] as num?)?.toInt() ?? 0;
      result.add((name: path, size: size));
    }
    return result;
  }

  List<_ModelFile> _fallbackFilesAsModelFiles() =>
      _fallbackFiles.map((f) => _ModelFile(f, 0)).toList();

  /// Build the ModelScope file-listing API URL.
  ///   https://modelscope.cn/models/MNN/Qwen3-0.6B-MNN
  ///   → https://modelscope.cn/api/v1/models/MNN/Qwen3-0.6B-MNN/repo/files
  String buildFileListUrl(String repoUrl) {
    final base = buildFileBaseUrl(repoUrl);
    // buildFileBaseUrl returns ".../repo?Revision=master&FilePath="
    // We need ".../repo/files" instead.
    return base.replaceAll('/repo?Revision=master&FilePath=', '/repo/files');
  }

  /// Convert a ModelScope repo URL to its per-file download API base.
  ///   https://modelscope.cn/models/MNN/Qwen3-0.6B-MNN
  ///   → https://modelscope.cn/api/v1/models/MNN/Qwen3-0.6B-MNN/repo?Revision=master&FilePath=
  String buildFileBaseUrl(String repoUrl) {
    final uri = Uri.parse(repoUrl);
    final segments = uri.pathSegments;
    if (segments.length >= 2) {
      final start = segments[0] == 'models' ? 1 : 0;
      final orgModel = segments.sublist(start).join('/');
      return 'https://${uri.host}/api/v1/models/$orgModel/repo?Revision=master&FilePath=';
    }
    return repoUrl;
  }

  void dispose() {
    _dio?.close();
    _dio = null;
  }

  /// Best-effort delete of a file; ignores errors if the file doesn't exist
  /// or cannot be removed (e.g. permissions). Used to clean up `.part`
  /// temp files left over from cancelled/interrupted downloads.
  Future<void> _safeDelete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Ignore — best-effort cleanup.
    }
  }

  /// Maps a [DioException] to a user-friendly Chinese message.
  static String _friendlyError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return '连接超时，请检查网络后重试';
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return '下载超时，文件较大或网络较慢，请耐心重试';
      case DioExceptionType.connectionError:
        return '网络连接失败，请检查网络设置';
      case DioExceptionType.badCertificate:
        return '证书验证失败';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 403) return '访问被拒绝 (403)';
        if (code == 500) return '服务器内部错误 (500)';
        if (code == 502 || code == 503) return '服务暂时不可用 ($code)';
        return '服务器返回错误 ($code)';
      case DioExceptionType.cancel:
        return '已取消';
      case DioExceptionType.unknown:
        return '下载失败: ${e.message ?? e.toString()}';
    }
  }
}

class _ModelFile {
  const _ModelFile(this.name, this.size);
  final String name;
  final int size;
}
