// MnnOmniSession: multimodal LLM session over MNN-LLM's Omni engine.
//
// Mirrors MnnLlmSession's isolate-based streaming model, but adds a
// [chatStream] overload that accepts media file paths (images / audio) which
// are forwarded to the C engine's mnn_omni_chat. The Omni engine decodes
// images and audio internally and drives a Qwen2.5-Omni-style model that can
// reason about both text and media in a single response.
//
// Threading model is identical to MnnLlmSession: a worker isolate runs the
// blocking mnn_omni_chat call and forwards token chunks to the main isolate
// via a SendPort, keeping the UI responsive.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'mnn_llm_bindings.dart';
import 'mnn_llm_session.dart' show MnnChatResult, MnnChatStatus;

/// A live multimodal LLM session. Create one per Omni model; reuse across
/// turns.
///
/// Typical usage:
/// ```dart
/// final session = await MnnOmniSession.create();
/// await session.load('/path/to/Qwen2.5-Omni-7B-MNN/config.json');
/// await for (final chunk in session.chatStream(
///   '描述这张图片',
///   mediaPaths: ['/tmp/img.jpg'],
/// )) {
///   print(chunk);
/// }
/// await session.dispose();
/// ```
class MnnOmniSession {
  MnnOmniSession._(this._handle, this._bindings);

  final Pointer<MnnOmni> _handle;
  final MnnLlmBindings _bindings;
  bool _disposed = false;
  Isolate? _worker;

  static Future<MnnOmniSession> create() async {
    final bindings = MnnLlmBindings(loadMnnLlmLibrary());
    final handle = bindings.mnnOmniCreate();
    if (handle == nullptr) {
      throw StateError('mnn_omni_create returned null');
    }
    return MnnOmniSession._(handle, bindings);
  }

  Future<void> load(String configPath) async {
    _checkAlive();
    final ptr = configPath.toNativeUtf8();
    try {
      final r = _bindings.mnnOmniLoad(_handle, ptr);
      if (r != 0) {
        throw StateError('mnn_omni_load failed (code $r) for $configPath');
      }
    } finally {
      calloc.free(ptr);
    }
  }

  Future<void> setConfig(Map<String, dynamic> config) async {
    _checkAlive();
    // Reuse MnnLlmSession's JSON convention.
    final json = _encodeJson(config);
    final ptr = json.toNativeUtf8();
    try {
      final r = _bindings.mnnOmniSetConfig(_handle, ptr);
      if (r != 0) {
        throw StateError('mnn_omni_set_config failed (code $r)');
      }
    } finally {
      calloc.free(ptr);
    }
  }

  /// Start a streaming chat. [mediaPaths] are absolute file paths to images
  /// (jpg/png) or audio (wav) the model should consider alongside [prompt].
  /// When [mediaPaths] is empty (the default), this is a plain text turn.
  /// The stream emits text chunks as they are generated.
  Stream<String> chatStream(String prompt,
      {List<String> mediaPaths = const []}) {
    _checkAlive();
    final controller = StreamController<String>(sync: true);
    final receivePort = ReceivePort();

    Isolate.spawn(
      _runOmniWorker,
      _OmniJob(_handle.address, prompt, mediaPaths, receivePort.sendPort),
    ).then((isolate) {
      _worker = isolate;
    }).catchError((Object e, StackTrace st) {
      controller.addError(e, st);
      controller.close();
      receivePort.close();
    });

    MnnChatResult? result;
    receivePort.listen((message) {
      if (message is String) {
        controller.add(message);
      } else if (message is _OmniDone) {
        result = MnnChatResult(_statusFromCode(message.code), message.msg);
        receivePort.close();
      }
    }, onDone: () {
      if (result != null && result!.status == MnnChatStatus.error) {
        controller.addError(StateError(result!.message ?? 'inference error'));
      }
      controller.close();
      _worker = null;
    });

    controller.onCancel = () => stop();
    return controller.stream;
  }

  void stop() {
    if (!_disposed) _bindings.mnnOmniStop(_handle);
  }

  void reset() {
    _checkAlive();
    _bindings.mnnOmniReset(_handle);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _bindings.mnnOmniDestroy(_handle);
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
  }

  void _checkAlive() {
    if (_disposed) throw StateError('MnnOmniSession has been disposed');
  }

  static String _encodeJson(Map<String, dynamic> config) {
    return jsonEncode(config);
  }

  static MnnChatStatus _statusFromCode(int code) {
    switch (code) {
      case 0:
        return MnnChatStatus.ok;
      case 1:
        return MnnChatStatus.maxTokens;
      case 2:
        return MnnChatStatus.cancelled;
      default:
        return MnnChatStatus.error;
    }
  }
}

class _OmniDone {
  final int code;
  final String? msg;
  _OmniDone(this.code, [this.msg]);
}

class _OmniJob {
  final int handleAddress;
  final String prompt;
  final List<String> mediaPaths;
  final SendPort sendPort;
  _OmniJob(this.handleAddress, this.prompt, this.mediaPaths, this.sendPort);
}

/// Worker isolate entry point for Omni chat. Mirrors _runChatWorker but
/// marshals the media-paths array into a native `const char**` before calling
/// mnn_omni_chat.
void _runOmniWorker(_OmniJob job) {
  final bindings = MnnLlmBindings(loadMnnLlmLibrary());
  final handle = Pointer<MnnOmni>.fromAddress(job.handleAddress);
  final promptPtr = job.prompt.toNativeUtf8();

  // Allocate a contiguous `const char**` array and copy each media path.
  // calloc gives zero-initialised memory so any unused slot is NULL.
  final mediaCount = job.mediaPaths.length;
  final mediaArrayPtr =
      mediaCount > 0 ? calloc<Pointer<Utf8>>(mediaCount) : nullptr;
  final tempPtrs = <Pointer<Utf8>>[];
  for (var i = 0; i < mediaCount; i++) {
    final p = job.mediaPaths[i].toNativeUtf8();
    tempPtrs.add(p);
    mediaArrayPtr[i] = p;
  }

  final streamCb = NativeCallable<StreamCbC>.isolateLocal(
    (Pointer<Utf8> data, Pointer<Void> _) {
      job.sendPort.send(data.toDartString());
      return 0;
    },
    exceptionalReturn: 0,
  );

  final doneCb = NativeCallable<DoneCbC>.isolateLocal(
    (int status, Pointer<Utf8> msg, Pointer<Void> _) {
      final text = msg == nullptr ? null : msg.toDartString();
      job.sendPort.send(_OmniDone(status, text));
    },
  );

  bindings.mnnOmniChat(
    handle,
    promptPtr,
    mediaArrayPtr,
    mediaCount,
    streamCb.nativeFunction,
    doneCb.nativeFunction,
    Pointer<Void>.fromAddress(0),
  );

  streamCb.close();
  doneCb.close();
  for (final p in tempPtrs) {
    calloc.free(p);
  }
  if (mediaArrayPtr != nullptr) calloc.free(mediaArrayPtr);
  calloc.free(promptPtr);
}
