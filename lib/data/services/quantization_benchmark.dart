/// Quantization benchmark framework.
enum QuantBits { int3, int4, int8, fp16 }

enum QuantGranularity { perChannel, perToken, perGroup }

class QuantConfig {
  final QuantBits visionBits, languageBits;
  final QuantGranularity granularity;
  const QuantConfig(
      {required this.visionBits,
      required this.languageBits,
      this.granularity = QuantGranularity.perChannel});
  String get label =>
      'V${visionBits.name}_L${languageBits.name}_${granularity.name}';
}

class QuantizationBenchmark {
  final List<QuantConfig> _configs = [];

  void addConfig(QuantConfig config) {
    _configs.add(config);
  }

  void addPresets() {
    _configs.addAll([
      const QuantConfig(
          visionBits: QuantBits.int8, languageBits: QuantBits.fp16),
      const QuantConfig(
          visionBits: QuantBits.int4, languageBits: QuantBits.int8),
      const QuantConfig(
          visionBits: QuantBits.int3, languageBits: QuantBits.int4),
      const QuantConfig(
          visionBits: QuantBits.int4, languageBits: QuantBits.int4)
    ]);
  }

  QuantConfig? bestConfig(
          {double accuracyWeight = 0.4,
          double speedWeight = 0.3,
          double memoryWeight = 0.3}) =>
      _configs.isEmpty ? null : _configs.first;
  List<QuantConfig> get configs => List.unmodifiable(_configs);
}
