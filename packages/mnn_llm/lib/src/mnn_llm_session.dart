// MnnLlmSession: high-level Dart API over the MNN-LLM C engine.
//
// Threading model
// ---------------
// MNN's `response()` is a blocking, synchronous call that can take seconds to
// minutes. Running it on the main isolate would freeze the UI. Instead,
// `chatStream` spawns a worker isolate that:
//   1. re-opens the native library (DynamicLibrary is per-isolate),
//   2. registers a NativeCallable.isolateLocal callback that synchronously
//      forwards each token chunk to the main isolate via SendPort,
//   3. calls `mnn_llm_chat` (blocking) — the C engine invokes our callback
//      inline as tokens are produced, which in turn calls `sendPort.send`.
//
// `NativeCallable.isolateLocal` is the right tool here: it is invoked
// synchronously from the C call stack (no event-loop hop), so tokens flow
// through without blocking generation, while `SendPort.send` is non-blocking
// and just enqueues a message on the main isolate.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'mnn_llm_bindings.dart';

/// Result reported when a generation finishes.
enum MnnChatStatus { ok, maxTokens, cancelled, error }

class MnnChatResult {
  final MnnChatStatus status;
  final String? message;
  MnnChatResult(this.status, [this.message]);
}

/// A live LLM session. Create one per model; reuse across turns.
///
/// Typical usage:
/// ```dart
/// final session = await MnnLlmSession.create();
/// await session.load('/path/to/model/config.json');
/// await session.setConfig({'temperature': 0.7, 'max_new_tokens': 512});
/// await for (final chunk in session.chatStream('你好')) {
///   stdout.write(chunk);
/// }
/// await session.dispose();
/// ```
class MnnLlmSession {
  MnnLlmSession._(this._handle, this._bindings);

  final Pointer<MnnLlm> _handle;
  final MnnLlmBindings _bindings;
  bool _disposed = false;
  Isolate? _worker;

  /// Construct an empty session (no model loaded).
  static Future<MnnLlmSession> create() async {
    final bindings = MnnLlmBindings(loadMnnLlmLibrary());
    final handle = bindings.mnnLlmCreate();
    if (handle == nullptr) {
      throw StateError('mnn_llm_create returned null');
    }
    return MnnLlmSession._(handle, bindings);
  }

  /// Load a model from its config.json path. Must be called before chat.
  Future<void> load(String configPath) async {
    _checkAlive();
    final ptr = configPath.toNativeUtf8();
    try {
      final r = _bindings.mnnLlmLoad(_handle, ptr);
      if (r != 0) {
        throw StateError('mnn_llm_load failed (code $r) for $configPath');
      }
    } finally {
      calloc.free(ptr);
    }
  }

  /// Update runtime configuration (sampling params, max tokens, ...).
  /// Keys mirror MNN's config.json fields.
  Future<void> setConfig(Map<String, dynamic> config) async {
    _checkAlive();
    final json = jsonEncode(config);
    final ptr = json.toNativeUtf8();
    try {
      final r = _bindings.mnnLlmSetConfig(_handle, ptr);
      if (r != 0) {
        throw StateError('mnn_llm_set_config failed (code $r)');
      }
    } finally {
      calloc.free(ptr);
    }
  }

  /// Start a streaming chat. The returned stream emits text chunks as they
  /// are generated and closes when generation ends (or is cancelled).
  ///
  /// The inference itself runs in a worker isolate; the UI stays responsive.
  /// Call [stop] to cancel mid-generation.
  Stream<String> chatStream(String prompt) {
    _checkAlive();
    final controller = StreamController<String>(sync: true);
    final receivePort = ReceivePort();

    Isolate.spawn(
      _runChatWorker,
      _ChatJob(_handle.address, prompt, receivePort.sendPort),
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
      } else if (message is _DoneSignal) {
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

    controller.onCancel = () {
      stop();
    };
    return controller.stream;
  }

  /// Request cancellation of the current generation (if any).
  void stop() {
    if (!_disposed) _bindings.mnnLlmStop(_handle);
  }

  /// Reset conversation history (KV cache). Call between unrelated chats.
  void reset() {
    _checkAlive();
    _bindings.mnnLlmReset(_handle);
  }

  /// Return the last run's performance metrics, or null if unavailable.
  Map<String, dynamic>? metrics() {
    if (_disposed) return null;
    final ptr = _bindings.mnnLlmGetMetrics(_handle);
    if (ptr == nullptr) return null;
    try {
      return jsonDecode(ptr.toDartString()) as Map<String, dynamic>;
    } finally {
      _bindings.mnnLlmFreeString(ptr);
    }
  }

  /// Release native resources. Safe to call once; the session is unusable
  /// afterwards.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _bindings.mnnLlmDestroy(_handle);
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
  }

  void _checkAlive() {
    if (_disposed) throw StateError('MnnLlmSession has been disposed');
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

/// Internal message: generation finished.
class _DoneSignal {
  final int code;
  final String? msg;
  _DoneSignal(this.code, [this.msg]);
}

/// Job payload sent to the worker isolate.
class _ChatJob {
  final int handleAddress;
  final String prompt;
  final SendPort sendPort;
  _ChatJob(this.handleAddress, this.prompt, this.sendPort);
}

/// Worker isolate entry point: runs the blocking chat and forwards tokens.
void _runChatWorker(_ChatJob job) {
  final bindings = MnnLlmBindings(loadMnnLlmLibrary());
  final handle = Pointer<MnnLlm>.fromAddress(job.handleAddress);
  final promptPtr = job.prompt.toNativeUtf8();

  // Synchronous callback: invoked inline by the C engine. Just enqueue a
  // message to the main isolate — non-blocking, keeps generation going.
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
      job.sendPort.send(_DoneSignal(status, text));
    },
  );

  bindings.mnnLlmChat(
    handle,
    promptPtr,
    streamCb.nativeFunction,
    doneCb.nativeFunction,
    Pointer<Void>.fromAddress(0),
  );

  streamCb.close();
  doneCb.close();
  calloc.free(promptPtr);
}
