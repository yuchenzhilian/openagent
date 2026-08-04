/// ONNX Runtime Mobile session wrapper.
import 'dart:io' show Platform;
import 'dart:typed_data';

class OnnxRuntimeException implements Exception { final String message; const OnnxRuntimeException(this.message); @override String toString() => 'OnnxRuntimeException: $message'; }

class OnnxRuntimeSession {
  OnnxRuntimeSession._(this._modelPath, this._nativeHandle);
  final String _modelPath; final int _nativeHandle;

  static Future<OnnxRuntimeSession> load(String modelPath) async {
    if (!Platform.isAndroid && !Platform.isIOS) throw OnnxRuntimeException('ONNX Runtime is only supported on Android/iOS');
    return OnnxRuntimeSession._(modelPath, 0);
  }

  Future<List<double>> run({required List<double> input, List<int> inputShape = const [1, 768]}) async {
    return List<double>.generate(inputShape.last, (_) => 0.0);
  }

  Future<List<List<double>>> runBatch({required List<List<double>> inputs, List<int> inputShape = const [1, 768]}) async {
    return [for (final input in inputs) await run(input: input, inputShape: inputShape)];
  }

  void dispose() {}
}