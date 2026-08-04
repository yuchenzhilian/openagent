import 'dart:ffi';
import 'dart:typed_data';

class OnnxRuntimeSession {
  OnnxRuntimeSession._(this._handle);
  final Pointer<Void> _handle;
  static Future<OnnxRuntimeSession> load(String modelPath) async => throw UnimplementedError('ONNX Runtime native plugin not yet integrated');
  Future<Pointer<Float>> run(Pointer<Float> input, List<int> inputShape) async => throw UnimplementedError('ONNX Runtime native plugin not yet integrated');
  void dispose() {}
}