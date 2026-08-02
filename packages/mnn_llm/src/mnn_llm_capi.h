// mnn_llm_capi.h
// C API wrapper for MNN-LLM, exposed to Dart via dart:ffi.
// All exported symbols are extern "C" so dart:ffi can bind to them.
#ifndef MNN_LLM_CAPI_H
#define MNN_LLM_CAPI_H

#include <stddef.h>

// Cross-platform symbol export. On Android/iOS the .so/framework is loaded
// by Dart FFI, so exported symbols must have default visibility. On Windows
// (future) we'd use dllexport/dllimport controlled by MNN_LLM_EXPORTS.
#if defined(_WIN32) || defined(__CYGWIN__)
  #ifdef MNN_LLM_EXPORTS
    #define MNN_LLM_API __declspec(dllexport)
  #else
    #define MNN_LLM_API __declspec(dllimport)
  #endif
#elif defined(__GNUC__) || defined(__clang__)
  #define MNN_LLM_API __attribute__((visibility("default")))
#else
  #define MNN_LLM_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque handle to a LLM instance. */
typedef struct mnn_llm mnn_llm_t;

/* Streaming callback: invoked for each generated text chunk.
 * - data:    UTF-8, NUL-terminated text fragment.
 * - user_data: pointer passed through from the caller (Dart side).
 * Returns: 0 to continue generation, non-zero to request cancellation.
 */
typedef int (*mnn_stream_cb)(const char* data, void* user_data);

/* Completion callback: invoked once when generation ends.
 * - status: 0 = normal finish, 1 = max tokens reached,
 *           2 = user cancelled, 3 = error.
 * - msg:     short status message (may be NULL).
 */
typedef void (*mnn_done_cb)(int status, const char* msg, void* user_data);

/* Result codes. */
enum {
    MNN_OK           =  0,
    MNN_ERR_LOAD     = -1,  /* model loading failed            */
    MNN_ERR_CONFIG   = -2,  /* invalid configuration           */
    MNN_ERR_INFER    = -3,  /* inference error                 */
    MNN_ERR_INVALID  = -4,  /* invalid argument                */
};

/* ---- Lifecycle ---- */

/* Create an idle LLM handle (no model loaded yet). */
MNN_LLM_API mnn_llm_t* mnn_llm_create(void);

/* Load a model from its config.json path.
 * config_path: absolute path to the model's config.json.
 * Returns MNN_OK on success.
 */
MNN_LLM_API int mnn_llm_load(mnn_llm_t* llm, const char* config_path);

/* Update runtime configuration.
 * json_config: JSON string, e.g.
 *   {"temperature":0.7,"top_k":40,"top_p":0.9,"max_new_tokens":512}
 * Returns MNN_OK on success.
 */
MNN_LLM_API int mnn_llm_set_config(mnn_llm_t* llm, const char* json_config);

/* ---- Inference ---- */

/* Run a single-turn chat with streaming output. Blocking; run on a
 * worker isolate/thread from Dart.
 * - prompt:    user input text (UTF-8).
 * - stream_cb: called per text chunk (may be NULL).
 * - done_cb:   called once when generation finishes (may be NULL).
 * - user_data: forwarded to callbacks.
 * Returns MNN_OK on success.
 */
MNN_LLM_API int mnn_llm_chat(mnn_llm_t* llm,
                              const char* prompt,
                              mnn_stream_cb stream_cb,
                              mnn_done_cb done_cb,
                              void* user_data);

/* Request cancellation of the current generation. Safe to call from
 * another thread. The running mnn_llm_chat will return shortly after. */
MNN_LLM_API void mnn_llm_stop(mnn_llm_t* llm);

/* Reset conversation: clear KV cache / history so the next chat starts
 * fresh. Call between unrelated conversations. */
MNN_LLM_API void mnn_llm_reset(mnn_llm_t* llm);

/* ---- Multimodal (Omni) ----
 *
 * Omni models (e.g. Qwen2.5-Omni) extend Llm with image / audio input.
 * A separate handle type is used so the Dart side can model a multimodal
 * session distinctly from a text-only one, even though the underlying
 * engine is the same MNN::Transformer::Llm (Omni is a subclass). */

typedef struct mnn_omni mnn_omni_t;

/* Create an idle Omni handle. Same lifecycle as mnn_llm_create. */
MNN_LLM_API mnn_omni_t* mnn_omni_create(void);

/* Load an Omni model from its config.json path. */
MNN_LLM_API int mnn_omni_load(mnn_omni_t* omni, const char* config_path);

/* Update runtime configuration (sampling params, etc.). */
MNN_LLM_API int mnn_omni_set_config(mnn_omni_t* omni, const char* json_config);

/* Run a multimodal chat with streaming output. Blocking; run on a worker
 * isolate from Dart.
 * - prompt:       user input text (UTF-8).
 * - media_paths:  array of UTF-8 file paths (images / audio). May be NULL
 *                 when media_count == 0.
 * - media_count:  number of entries in media_paths.
 * - stream_cb / done_cb / user_data: same contract as mnn_llm_chat. */
MNN_LLM_API int mnn_omni_chat(mnn_omni_t* omni,
                              const char* prompt,
                              const char** media_paths,
                              int media_count,
                              mnn_stream_cb stream_cb,
                              mnn_done_cb done_cb,
                              void* user_data);

/* Request cancellation of the current Omni generation. */
MNN_LLM_API void mnn_omni_stop(mnn_omni_t* omni);

/* Reset Omni conversation history. */
MNN_LLM_API void mnn_omni_reset(mnn_omni_t* omni);

/* Destroy the Omni handle and release all resources. */
MNN_LLM_API void mnn_omni_destroy(mnn_omni_t* omni);

/* ---- Introspection ---- */

/* Return performance metrics as a JSON string. Caller must free with
 * mnn_llm_free_string. Example:
 *   {"prompt_len":12,"gen_seq_len":48,"prefill_us":12300,
 *    "decode_us":2100000,"ttfa_us":12400} */
MNN_LLM_API char* mnn_llm_get_metrics(mnn_llm_t* llm);

/* Free a string returned by mnn_llm_get_metrics. */
MNN_LLM_API void mnn_llm_free_string(char* str);

/* Destroy the handle and release all resources. */
MNN_LLM_API void mnn_llm_destroy(mnn_llm_t* llm);

#ifdef __cplusplus
}
#endif

#endif /* MNN_LLM_CAPI_H */
