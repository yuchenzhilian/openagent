/// Flutter FFI plugin for MNN-LLM — on-device LLM inference powered by
/// Alibaba's MNN engine.
///
/// Quick start (text):
/// ```dart
/// import 'package:mnn_llm/mnn_llm.dart';
///
/// final session = await MnnLlmSession.create();
/// await session.load('/sdcard/models/Qwen3-0.6B-MNN/config.json');
/// await for (final chunk in session.chatStream('你好')) {
///   print(chunk);
/// }
/// await session.dispose();
/// ```
///
/// Multimodal (Omni):
/// ```dart
/// final omni = await MnnOmniSession.create();
/// await omni.load('/sdcard/models/Qwen2.5-Omni-7B-MNN/config.json');
/// await for (final chunk in omni.chatStream(
///   '描述这张图片', mediaPaths: ['/tmp/photo.jpg'],
/// )) {
///   print(chunk);
/// }
/// await omni.dispose();
/// ```
library mnn_llm;

export 'src/mnn_llm_bindings.dart'
    show MnnLlm, MnnOmni, MnnLlmBindings, loadMnnLlmLibrary;
export 'src/mnn_llm_session.dart'
    show MnnLlmSession, MnnChatResult, MnnChatStatus;
export 'src/mnn_omni_session.dart' show MnnOmniSession;
export 'src/cloud_llm_session.dart'
    show CloudLlmSession, CloudLlmConfig, CloudLlmPresets, CloudProvider;
