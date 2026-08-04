import 'dart:ffi';

class OnnxRuntimeSession {
  OnnxRuntimeSession._();
  static Future<OnnxRuntimeSession> load(String modelPath) async => throw UnimplementedError('ONNX Runtime native plugin not yet integrated');
  Future<Pointer<Float>> run(Pointer<Float> input, List<int> inputShape) async => throw UnimplementedError('ONNX Runtime native plugin not yet integrated');
  void dispose() {}
}