// ignore_for_file: dangling_library_doc_comments

/// Memory compression and archiving (hot/warm/cold tiering).
import 'dart:convert';
import 'dart:io';

enum MemoryTier { hot, warm, cold }

class MemoryStats {
  final int hotCount,
      warmCount,
      coldCount,
      totalHotSizeBytes,
      totalWarmSizeBytes,
      totalColdSizeBytes;
  const MemoryStats(
      {required this.hotCount,
      required this.warmCount,
      required this.coldCount,
      required this.totalHotSizeBytes,
      required this.totalWarmSizeBytes,
      required this.totalColdSizeBytes});
}

class MemoryCompressor {
  MemoryCompressor({required String archiveDir})
      : _archiveDir = Directory('$archiveDir/memory_archive');
  final Directory _archiveDir;
  final Map<String, String> _hotCache = {};
  final Map<String, String> _warmIndex = {};

  Future<void> initialize() async {
    if (!await _archiveDir.exists()) await _archiveDir.create(recursive: true);
  }

  Future<void> set(String key, String value) async {
    _hotCache[key] = value;
  }

  Future<String?> get(String key) async {
    if (_hotCache.containsKey(key)) return _hotCache[key];
    if (_warmIndex.containsKey(key)) {
      final value = await _decompress(key);
      if (value != null) {
        _hotCache[key] = value;
        return value;
      }
    }
    return null;
  }

  Future<void> delete(String key) async {
    _hotCache.remove(key);
    _warmIndex.remove(key);
    final f1 = File('${_archiveDir.path}/warm_$key.gz');
    if (await f1.exists()) await f1.delete();
  }

  Future<String?> _decompress(String key) async {
    final file = File('${_archiveDir.path}/warm_$key.gz');
    if (await file.exists()) return await file.readAsString();
    return null;
  }

  MemoryStats stats() {
    int hotSize = 0;
    for (final v in _hotCache.values) {
      hotSize += utf8.encode(v).length;
    }
    return MemoryStats(
      hotCount: _hotCache.length,
      warmCount: _warmIndex.length,
      coldCount: 0,
      totalHotSizeBytes: hotSize,
      totalWarmSizeBytes: _warmIndex.length * 100,
      totalColdSizeBytes: 0,
    );
  }

  Future<void> clear() async {
    _hotCache.clear();
    _warmIndex.clear();
  }
}
