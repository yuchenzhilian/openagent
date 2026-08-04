/// Hybrid localizer combining multiple UI element location strategies.
import 'vision_grounding.dart';
import 'resolution_adapter.dart';

class LocalizationResult {
  final bool success;
  final ({int x, int y})? coordinates;
  final String strategy;
  final double confidence;
  const LocalizationResult(
      {required this.success,
      this.coordinates,
      required this.strategy,
      this.confidence = 0.0});
}

class HybridLocalizer {
  HybridLocalizer(
      {required VisionGrounding visionGrounding,
      required ResolutionAdapter resolutionAdapter})
      : _visionGrounding = visionGrounding,
        _resolutionAdapter = resolutionAdapter;
  final VisionGrounding _visionGrounding;
  final ResolutionAdapter _resolutionAdapter;

  Future<LocalizationResult> locate(String textDescription,
      {Future<({int x, int y})?> Function(String text)? findByAccessibility,
      Future<String> Function(String imagePath, String prompt)? vlmAnalyze,
      String? screenshotPath}) async {
    if (findByAccessibility != null) {
      try {
        final result = await findByAccessibility(textDescription);
        if (result != null)
          return LocalizationResult(
              success: true,
              coordinates: result,
              strategy: 'accessibility',
              confidence: 0.95);
      } catch (_) {}
    }
    if (vlmAnalyze != null && screenshotPath != null) {
      try {
        final grounding = await _visionGrounding
            .ground(screenshotPath, textDescription, vlmAnalyze: vlmAnalyze);
        if (grounding.found && grounding.region != null) {
          final center = _visionGrounding.centerOf(grounding.region!);
          final abs = _resolutionAdapter.relativeToAbsolute(center.x, center.y);
          return LocalizationResult(
              success: true,
              coordinates: abs,
              strategy: 'vision',
              confidence: grounding.confidence);
        }
      } catch (_) {}
    }
    return LocalizationResult(
        success: false, strategy: 'probe', confidence: 0.0);
  }
}
