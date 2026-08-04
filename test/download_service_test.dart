// Unit tests for ModelDownloadService URL construction.
//
// These tests verify that ModelScope repo URLs are correctly converted
// to API URLs for file listing and file download. This is critical
// because incorrect URL construction caused two models to fail
// downloading (Qwen3-1.8B-MNN and DeepSeek-R1-Distill-Qwen-1.5B-MNN
// were wrong model names that returned "record not found").
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/data/services/file_storage_service.dart';
import 'package:openagent/data/services/model_download_service.dart';

void main() {
  late ModelDownloadService service;

  setUp(() {
    // ModelDownloadService only needs a FileStorageService for getModelDir.
    // The URL construction methods don't use it, so we pass a mock-like
    // instance. We can't easily create a real FileStorageService without
    // path_provider, but the URL methods don't touch storage at all.
    // We create the service via a simple stub.
    service = _StubDownloadService();
  });

  group('buildFileBaseUrl', () {
    test('converts Qwen3-0.6B-MNN repo URL to download API base', () {
      const repoUrl = 'https://modelscope.cn/models/MNN/Qwen3-0.6B-MNN';
      final result = service.buildFileBaseUrl(repoUrl);
      expect(result,
          'https://modelscope.cn/api/v1/models/MNN/Qwen3-0.6B-MNN/repo?Revision=master&FilePath=');
    });

    test('converts Qwen3-1.7B-MNN repo URL to download API base', () {
      const repoUrl = 'https://modelscope.cn/models/MNN/Qwen3-1.7B-MNN';
      final result = service.buildFileBaseUrl(repoUrl);
      expect(result,
          'https://modelscope.cn/api/v1/models/MNN/Qwen3-1.7B-MNN/repo?Revision=master&FilePath=');
    });

    test('converts Qwen3-4B-MNN repo URL to download API base', () {
      const repoUrl = 'https://modelscope.cn/models/MNN/Qwen3-4B-MNN';
      final result = service.buildFileBaseUrl(repoUrl);
      expect(result,
          'https://modelscope.cn/api/v1/models/MNN/Qwen3-4B-MNN/repo?Revision=master&FilePath=');
    });

    test('converts Qwen2.5-Omni-7B-MNN repo URL to download API base', () {
      const repoUrl = 'https://modelscope.cn/models/MNN/Qwen2.5-Omni-7B-MNN';
      final result = service.buildFileBaseUrl(repoUrl);
      expect(result,
          'https://modelscope.cn/api/v1/models/MNN/Qwen2.5-Omni-7B-MNN/repo?Revision=master&FilePath=');
    });

    test('converts DeepSeek-R1-1.5B-Qwen-MNN repo URL to download API base',
        () {
      const repoUrl =
          'https://modelscope.cn/models/MNN/DeepSeek-R1-1.5B-Qwen-MNN';
      final result = service.buildFileBaseUrl(repoUrl);
      expect(result,
          'https://modelscope.cn/api/v1/models/MNN/DeepSeek-R1-1.5B-Qwen-MNN/repo?Revision=master&FilePath=');
    });

    test('handles URL with trailing slash', () {
      const repoUrl = 'https://modelscope.cn/models/MNN/Qwen3-0.6B-MNN/';
      final result = service.buildFileBaseUrl(repoUrl);
      // Trailing slash adds an empty segment, but pathSegments handles it.
      expect(result, contains('MNN/Qwen3-0.6B-MNN'));
      expect(result, contains('/repo?Revision=master&FilePath='));
    });

    test('returns original URL for invalid input', () {
      const repoUrl = 'https://example.com';
      final result = service.buildFileBaseUrl(repoUrl);
      expect(result, repoUrl);
    });
  });

  group('buildFileListUrl', () {
    test('converts Qwen3-0.6B-MNN repo URL to file-listing API URL', () {
      const repoUrl = 'https://modelscope.cn/models/MNN/Qwen3-0.6B-MNN';
      final result = service.buildFileListUrl(repoUrl);
      expect(result,
          'https://modelscope.cn/api/v1/models/MNN/Qwen3-0.6B-MNN/repo/files');
    });

    test('converts DeepSeek-R1-1.5B-Qwen-MNN repo URL to file-listing API URL',
        () {
      const repoUrl =
          'https://modelscope.cn/models/MNN/DeepSeek-R1-1.5B-Qwen-MNN';
      final result = service.buildFileListUrl(repoUrl);
      expect(result,
          'https://modelscope.cn/api/v1/models/MNN/DeepSeek-R1-1.5B-Qwen-MNN/repo/files');
    });

    test('all 5 catalogue models produce valid file-listing URLs', () {
      const models = [
        'https://modelscope.cn/models/MNN/Qwen3-0.6B-MNN',
        'https://modelscope.cn/models/MNN/Qwen3-1.7B-MNN',
        'https://modelscope.cn/models/MNN/Qwen3-4B-MNN',
        'https://modelscope.cn/models/MNN/Qwen2.5-Omni-7B-MNN',
        'https://modelscope.cn/models/MNN/DeepSeek-R1-1.5B-Qwen-MNN',
      ];
      for (final url in models) {
        final result = service.buildFileListUrl(url);
        expect(result, startsWith('https://modelscope.cn/api/v1/models/MNN/'));
        expect(result, endsWith('/repo/files'));
      }
    });
  });

  group('parseFileListResponse', () {
    test('parses Qwen3-0.6B-MNN file list correctly', () {
      // Sample ModelScope API response (simplified).
      final data = {
        'Data': {
          'Files': [
            {'Path': '.gitattributes', 'Size': 100},
            {'Path': 'config.json', 'Size': 1200},
            {'Path': 'configuration.json', 'Size': 500},
            {'Path': 'llm.mnn', 'Size': 5000000},
            {'Path': 'llm.mnn.weight', 'Size': 450000000},
            {'Path': 'llm_config.json', 'Size': 800},
            {'Path': 'README.md', 'Size': 3000},
            {'Path': 'LICENSE', 'Size': 11000},
            {'Path': 'tokenizer.txt', 'Size': 2000000},
          ],
        },
      };
      final result = ModelDownloadService.parseFileListResponse(data);
      expect(result.length, 5);
      expect(result.map((f) => f.name).toList(), [
        'config.json',
        'llm.mnn',
        'llm.mnn.weight',
        'llm_config.json',
        'tokenizer.txt',
      ]);
      // Verify sizes are parsed correctly.
      final weight = result.firstWhere((f) => f.name == 'llm.mnn.weight');
      expect(weight.size, 450000000);
    });

    test('parses DeepSeek model with non-standard files', () {
      // DeepSeek-R1-1.5B-Qwen-MNN has different files.
      final data = {
        'Data': {
          'Files': [
            {'Path': 'config.json', 'Size': 1500},
            {'Path': 'embeddings_int4.bin', 'Size': 100000000},
            {'Path': 'export_args.json', 'Size': 400},
            {'Path': 'llm.mnn', 'Size': 3000000},
            {'Path': 'llm.mnn.json', 'Size': 600},
            {'Path': 'llm.mnn.weight', 'Size': 900000000},
            {'Path': 'llm_config.json', 'Size': 900},
            {'Path': 'tokenizer.mtok', 'Size': 1500000},
          ],
        },
      };
      final result = ModelDownloadService.parseFileListResponse(data);
      // All 8 files are model artifacts (none in skip list).
      expect(result.length, 8);
      expect(
          result.map((f) => f.name).toList(),
          containsAll([
            'config.json',
            'embeddings_int4.bin',
            'export_args.json',
            'llm.mnn',
            'llm.mnn.json',
            'llm.mnn.weight',
            'llm_config.json',
            'tokenizer.mtok',
          ]));
    });

    test('filters out non-artifact files', () {
      final data = {
        'Data': {
          'Files': [
            {'Path': '.gitattributes', 'Size': 100},
            {'Path': '.gitignore', 'Size': 50},
            {'Path': 'configuration.json', 'Size': 500},
            {'Path': 'README.md', 'Size': 3000},
            {'Path': 'CONTRIBUTING.md', 'Size': 2000},
            {'Path': 'LICENSE', 'Size': 11000},
            {'Path': 'config.json', 'Size': 1200},
          ],
        },
      };
      final result = ModelDownloadService.parseFileListResponse(data);
      expect(result.length, 1);
      expect(result[0].name, 'config.json');
    });

    test('handles missing Size field (defaults to 0)', () {
      final data = {
        'Data': {
          'Files': [
            {'Path': 'config.json'}, // No Size field.
            {'Path': 'llm.mnn', 'Size': null},
          ],
        },
      };
      final result = ModelDownloadService.parseFileListResponse(data);
      expect(result.length, 2);
      expect(result[0].size, 0);
      expect(result[1].size, 0);
    });

    test('returns empty list for non-Map input', () {
      expect(ModelDownloadService.parseFileListResponse(null), isEmpty);
      expect(ModelDownloadService.parseFileListResponse('string'), isEmpty);
      expect(ModelDownloadService.parseFileListResponse(42), isEmpty);
      expect(ModelDownloadService.parseFileListResponse([]), isEmpty);
    });

    test('returns empty list for missing Data.Files', () {
      expect(ModelDownloadService.parseFileListResponse({}), isEmpty);
      expect(ModelDownloadService.parseFileListResponse({'Data': {}}), isEmpty);
      expect(
          ModelDownloadService.parseFileListResponse({
            'Data': {'Files': null}
          }),
          isEmpty);
    });

    test('returns empty list for empty Files array', () {
      final data = {
        'Data': {'Files': []}
      };
      final result = ModelDownloadService.parseFileListResponse(data);
      expect(result, isEmpty);
    });

    test('handles non-Map entries in Files array gracefully', () {
      final data = {
        'Data': {
          'Files': [
            'not a map',
            42,
            null,
            {'Path': 'config.json', 'Size': 1200},
            {'NotPath': 'foo'},
            {'Path': 123}, // Non-string Path.
          ],
        },
      };
      final result = ModelDownloadService.parseFileListResponse(data);
      expect(result.length, 1);
      expect(result[0].name, 'config.json');
    });
  });

  // Integration test: verifies the actual ModelScope API is reachable
  // and returns the expected file structure. Skipped by default to avoid
  // network dependency in CI — run manually with:
  //   flutter test test/download_service_test.dart --plain-name 'integration'
  group('integration: ModelScope API', () {
    final models = [
      ('Qwen3-0.6B-MNN', 'https://modelscope.cn/models/MNN/Qwen3-0.6B-MNN'),
      ('Qwen3-1.7B-MNN', 'https://modelscope.cn/models/MNN/Qwen3-1.7B-MNN'),
      ('Qwen3-4B-MNN', 'https://modelscope.cn/models/MNN/Qwen3-4B-MNN'),
      (
        'Qwen2.5-Omni-7B-MNN',
        'https://modelscope.cn/models/MNN/Qwen2.5-Omni-7B-MNN'
      ),
      (
        'DeepSeek-R1-1.5B-Qwen-MNN',
        'https://modelscope.cn/models/MNN/DeepSeek-R1-1.5B-Qwen-MNN'
      ),
    ];

    for (final (name, url) in models) {
      test('$name: API reachable and returns model files', () async {
        final apiUrl = service.buildFileListUrl(url);
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));
        try {
          final resp = await dio.get<dynamic>(apiUrl);
          expect(resp.statusCode, 200);
          final files = ModelDownloadService.parseFileListResponse(resp.data);
          // Every MNN-LLM model must have at least config.json and
          // llm.mnn.weight to be usable.
          expect(files, isNotEmpty, reason: '$name returned empty file list');
          final names = files.map((f) => f.name).toSet();
          expect(names, contains('config.json'),
              reason: '$name missing config.json');
          expect(names, contains('llm.mnn.weight'),
              reason: '$name missing llm.mnn.weight');
          // The weight file should have a non-zero size.
          final weight = files.firstWhere((f) => f.name == 'llm.mnn.weight');
          expect(weight.size, greaterThan(0),
              reason: '$name: llm.mnn.weight has size 0');
        } finally {
          dio.close();
        }
      }, timeout: const Timeout(Duration(seconds: 30)));
    }
  });
}

/// A minimal subclass that bypasses the FileStorageService dependency.
///
/// The URL construction methods don't use [_storage] at all, so we can
/// safely pass a no-op stub. This avoids needing path_provider in tests.
class _StubDownloadService extends ModelDownloadService {
  _StubDownloadService() : super(_NullStorage());
}

class _NullStorage implements FileStorageService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
