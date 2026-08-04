/// Resolution adapter for cross-device UI automation.
class DeviceInfo {
  final int screenWidth, screenHeight;
  final double density;
  const DeviceInfo(
      {required this.screenWidth,
      required this.screenHeight,
      this.density = 440});
}

class ResolutionAdapter {
  static const referenceDevice =
      DeviceInfo(screenWidth: 1080, screenHeight: 2400, density: 440);
  final DeviceInfo currentDevice;
  const ResolutionAdapter({required this.currentDevice});

  ({int x, int y}) relativeToAbsolute(double relX, double relY) => (
        x: (relX * currentDevice.screenWidth).round(),
        y: (relY * currentDevice.screenHeight).round()
      );
  ({int x, int y}) referenceToCurrent(int refX, int refY) => (
        x: (refX * currentDevice.screenWidth / referenceDevice.screenWidth)
            .round(),
        y: (refY * currentDevice.screenHeight / referenceDevice.screenHeight)
            .round()
      );
  double get scaleX => currentDevice.screenWidth / referenceDevice.screenWidth;
  double get scaleY =>
      currentDevice.screenHeight / referenceDevice.screenHeight;
}
