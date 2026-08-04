/// Auto quantization config selector.
import 'quantization_benchmark.dart';

class AutoQuantization {
  static QuantConfig selectForDevice(int totalMemoryMb) {
    if (totalMemoryMb >= 6144) return const QuantConfig(visionBits: QuantBits.int8, languageBits: QuantBits.fp16);
    if (totalMemoryMb >= 4096) return const QuantConfig(visionBits: QuantBits.int4, languageBits: QuantBits.int8);
    return const QuantConfig(visionBits: QuantBits.int3, languageBits: QuantBits.int4);
  }

  static int estimateModelSizeMb(int originalSizeMb, QuantConfig config) {
    double ratio = 1.0;
    for (final bits in [config.visionBits, config.languageBits]) {
      switch (bits) { case QuantBits.fp16: ratio *= 1.0; case QuantBits.int8: ratio *= 0.5; case QuantBits.int4: ratio *= 0.25; case QuantBits.int3: ratio *= 0.1875; }
    }
    return (originalSizeMb * ratio).round();
  }
}