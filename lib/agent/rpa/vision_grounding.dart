/// Vision grounding engine for anchor-free UI manipulation.
class ScreenRegion { final double x, y, width, height; const ScreenRegion({required this.x, required this.y, required this.width, required this.height}); }
class GroundingResult { final String description; final ScreenRegion? region; final double confidence; final bool found; const GroundingResult({required this.description, this.region, this.confidence = 0.0, this.found = false}); }

class VisionGrounding {
  Future<GroundingResult> ground(String screenshotPath, String description, {Future<String> Function(String imagePath, String prompt)? vlmAnalyze}) async {
    if (vlmAnalyze == null) return GroundingResult(description: description, confidence: 0.0, found: false);
    final prompt = '在屏幕截图中找到"$description"的位置。请返回该元素在屏幕中的相对坐标 (x,y,w,h)，取值范围 0.0-1.0。格式: {x:0.5, y:0.5, w:0.2, h:0.1}';
    final response = await vlmAnalyze(screenshotPath, prompt);
    return _parseVlmResponse(response, description);
  }

  GroundingResult _parseVlmResponse(String response, String description) {
    try {
      final jsonStart = response.indexOf('{'); final jsonEnd = response.lastIndexOf('}');
      if (jsonStart >= 0 && jsonEnd > jsonStart) {
        final json = response.substring(jsonStart, jsonEnd + 1);
        final x = _extractValue(json, 'x'); final y = _extractValue(json, 'y');
        final w = _extractValue(json, 'w'); final h = _extractValue(json, 'h');
        if (x != null && y != null) return GroundingResult(description: description, region: ScreenRegion(x: x.clamp(0.0, 1.0), y: y.clamp(0.0, 1.0), width: w?.clamp(0.0, 1.0) ?? 0.1, height: h?.clamp(0.0, 1.0) ?? 0.1), confidence: 0.8, found: true);
      }
    } catch (_) {}
    return GroundingResult(description: description, confidence: 0.0, found: false);
  }

  double? _extractValue(String text, String key) {
    final match = RegExp('"$key"\\s*:\\s*([0-9.]+)').firstMatch(text);
    return match != null ? double.tryParse(match.group(1)!) : null;
  }

  ({double x, double y}) centerOf(ScreenRegion region) => (x: region.x + region.width / 2, y: region.y + region.height / 2);
}