// Hand-written FFI bindings for the MNN-LLM C API (mnn_llm_capi.h).
//
// We bind manually instead of using ffigen so the plugin has zero extra
// toolchain dependencies and the callback typing stays explicit. The C API
// surface is small enough that hand-maintaining these is cheaper than
// wiring up ffigen + libclang.
import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';

/// Opaque handle to the native `mnn_llm` struct.
final class MnnLlm extends Opaque {}

/// Opaque handle to the native `mnn_omni` struct (multimodal engine).
final class MnnOmni extends Opaque {}

/// Native signature for the streaming token callback.
typedef StreamCbC = Int32 Function(Pointer<Utf8> data, Pointer<Void> userData);

/// Native signature for the completion callback.
typedef DoneCbC = Void Function(
    Int32 status, Pointer<Utf8> msg, Pointer<Void> userData);

/// Dart-side signature for the streaming token callback.
typedef StreamCbDart = int Function(Pointer<Utf8> data, Pointer<Void> userData);

/// Dart-side signature for the completion callback.
typedef DoneCbDart = void Function(
    int status, Pointer<Utf8> msg, Pointer<Void> userData);

/// Loads the native library on the current platform.
DynamicLibrary loadMnnLlmLibrary() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libmnn_llm.so');
  }
  if (Platform.isIOS || Platform.isMacOS) {
    // Statically linked into the app binary on iOS.
    return DynamicLibrary.process();
  }
  throw UnsupportedError(
      'MNN-LLM plugin does not support ${Platform.operatingSystem} yet.');
}

/// Thin wrapper around the C symbols. Every lookup is resolved lazily.
class MnnLlmBindings {
  MnnLlmBindings(this.lib);

  final DynamicLibrary lib;

  late final Pointer<MnnLlm> Function() mnnLlmCreate = lib.lookupFunction<
      Pointer<MnnLlm> Function(),
      Pointer<MnnLlm> Function()>('mnn_llm_create');

  late final int Function(Pointer<MnnLlm> llm, Pointer<Utf8> configPath)
      mnnLlmLoad = lib.lookupFunction<
          Int32 Function(Pointer<MnnLlm>, Pointer<Utf8>),
          int Function(Pointer<MnnLlm>, Pointer<Utf8>)>('mnn_llm_load');

  late final int Function(Pointer<MnnLlm> llm, Pointer<Utf8> jsonConfig)
      mnnLlmSetConfig = lib.lookupFunction<
          Int32 Function(Pointer<MnnLlm>, Pointer<Utf8>),
          int Function(Pointer<MnnLlm>, Pointer<Utf8>)>('mnn_llm_set_config');

  late final int Function(
      Pointer<MnnLlm> llm,
      Pointer<Utf8> prompt,
      Pointer<NativeFunction<StreamCbC>> streamCb,
      Pointer<NativeFunction<DoneCbC>> doneCb,
      Pointer<Void> userData) mnnLlmChat = lib.lookupFunction<
          Int32 Function(
              Pointer<MnnLlm>,
              Pointer<Utf8>,
              Pointer<NativeFunction<StreamCbC>>,
              Pointer<NativeFunction<DoneCbC>>,
              Pointer<Void>),
          int Function(
              Pointer<MnnLlm>,
              Pointer<Utf8>,
              Pointer<NativeFunction<StreamCbC>>,
              Pointer<NativeFunction<DoneCbC>>,
              Pointer<Void>)>('mnn_llm_chat');

  late final void Function(Pointer<MnnLlm> llm) mnnLlmStop = lib.lookupFunction<
      Void Function(Pointer<MnnLlm>),
      void Function(Pointer<MnnLlm>)>('mnn_llm_stop');

  late final void Function(Pointer<MnnLlm> llm) mnnLlmReset = lib
      .lookupFunction<Void Function(Pointer<MnnLlm>),
          void Function(Pointer<MnnLlm>)>('mnn_llm_reset');

  late final Pointer<Utf8> Function(Pointer<MnnLlm> llm) mnnLlmGetMetrics = lib
      .lookupFunction<Pointer<Utf8> Function(Pointer<MnnLlm>),
          Pointer<Utf8> Function(Pointer<MnnLlm>)>('mnn_llm_get_metrics');

  late final void Function(Pointer<Utf8> str) mnnLlmFreeString = lib
      .lookupFunction<Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)>('mnn_llm_free_string');

  late final void Function(Pointer<MnnLlm> llm) mnnLlmDestroy = lib
      .lookupFunction<Void Function(Pointer<MnnLlm>),
          void Function(Pointer<MnnLlm>)>('mnn_llm_destroy');

  // ---- Omni (multimodal) ----

  late final Pointer<MnnOmni> Function() mnnOmniCreate = lib.lookupFunction<
      Pointer<MnnOmni> Function(),
      Pointer<MnnOmni> Function()>('mnn_omni_create');

  late final int Function(Pointer<MnnOmni> omni, Pointer<Utf8> configPath)
      mnnOmniLoad = lib.lookupFunction<
          Int32 Function(Pointer<MnnOmni>, Pointer<Utf8>),
          int Function(Pointer<MnnOmni>, Pointer<Utf8>)>('mnn_omni_load');

  late final int Function(Pointer<MnnOmni> omni, Pointer<Utf8> jsonConfig)
      mnnOmniSetConfig = lib.lookupFunction<
          Int32 Function(Pointer<MnnOmni>, Pointer<Utf8>),
          int Function(Pointer<MnnOmni>, Pointer<Utf8>)>('mnn_omni_set_config');

  late final int Function(
      Pointer<MnnOmni> omni,
      Pointer<Utf8> prompt,
      Pointer<Pointer<Utf8>> mediaPaths,
      int mediaCount,
      Pointer<NativeFunction<StreamCbC>> streamCb,
      Pointer<NativeFunction<DoneCbC>> doneCb,
      Pointer<Void> userData) mnnOmniChat = lib.lookupFunction<
          Int32 Function(
              Pointer<MnnOmni>,
              Pointer<Utf8>,
              Pointer<Pointer<Utf8>>,
              Int32,
              Pointer<NativeFunction<StreamCbC>>,
              Pointer<NativeFunction<DoneCbC>>,
              Pointer<Void>),
          int Function(
              Pointer<MnnOmni>,
              Pointer<Utf8>,
              Pointer<Pointer<Utf8>>,
              int,
              Pointer<NativeFunction<StreamCbC>>,
              Pointer<NativeFunction<DoneCbC>>,
              Pointer<Void>)>('mnn_omni_chat');

  late final void Function(Pointer<MnnOmni> omni) mnnOmniStop = lib
      .lookupFunction<Void Function(Pointer<MnnOmni>),
          void Function(Pointer<MnnOmni>)>('mnn_omni_stop');

  late final void Function(Pointer<MnnOmni> omni) mnnOmniReset = lib
      .lookupFunction<Void Function(Pointer<MnnOmni>),
          void Function(Pointer<MnnOmni>)>('mnn_omni_reset');

  late final void Function(Pointer<MnnOmni> omni) mnnOmniDestroy = lib
      .lookupFunction<Void Function(Pointer<MnnOmni>),
          void Function(Pointer<MnnOmni>)>('mnn_omni_destroy');
}
