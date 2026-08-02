// mnn_llm_capi.cpp
// C API wrapper around MNN::Transformer::Llm.
//
// Design notes:
// - dart:ffi can only bind to C symbols, so every exported function is
//   wrapped in extern "C". The Llm C++ object is hidden behind an opaque
//   handle (struct mnn_llm).
// - Streaming output is implemented via a custom std::stringbuf: MNN writes
//   generated tokens to an ostream, and our StreamCallbackBuf forwards each
//   flushed chunk to the Dart-provided callback. Returning non-zero from the
//   callback sets the stream bad, which short-circuits further writes.
// - Cancellation is cooperative: mnn_llm_stop sets an atomic flag; the
//   stream callback checks it and stops forwarding tokens.
#include "mnn_llm_capi.h"

#include "llm/llm.hpp"

#include <MNN/expr/Expr.hpp>
#include <MNN/expr/NeuralNetWorkOp.hpp>

// stb_image is a header-only JPEG/PNG/etc decoder shipped in MNN's
// 3rd_party/imageHelper/. We use it to turn file paths into raw pixel
// buffers, then wrap those in a VARP for MultimodalPrompt.images.
// STB_IMAGE_STATIC makes the functions file-local so there's no clash
// with any stb_image copy already compiled into libMNN.so.
#define STB_IMAGE_STATIC
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#define STBI_ONLY_BMP
#include "imageHelper/stb_image.h"

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

namespace {

// std::stringbuf that forwards each flushed chunk to a Dart callback.
class StreamCallbackBuf : public std::stringbuf {
public:
    StreamCallbackBuf(mnn_stream_cb cb, void* user_data, std::atomic<bool>* cancel)
        : cb_(cb), user_data_(user_data), cancel_(cancel) {}

    int sync() override {
        std::string chunk = str();
        if (!chunk.empty()) {
            if (cb_ && cb_(chunk.c_str(), user_data_) != 0) {
                // Caller asked to cancel: poison the stream so MNN stops
                // writing, and set the cancel flag for the outer loop.
                if (cancel_) cancel_->store(true);
                str("");
                return -1;  // non-zero marks the stream as bad
            }
        }
        str("");
        return 0;
    }

private:
    mnn_stream_cb cb_;
    void* user_data_;
    std::atomic<bool>* cancel_;
};

int status_to_code(MNN::Transformer::LlmStatus s) {
    using S = MNN::Transformer::LlmStatus;
    switch (s) {
        case S::NORMAL_FINISHED:    return 0;
        case S::MAX_TOKENS_FINISHED: return 1;
        case S::USER_CANCEL:         return 2;
        default:                     return 3;
    }
}

}  // namespace

struct mnn_llm {
    MNN::Transformer::Llm* engine = nullptr;
    std::atomic<bool> cancel_flag{false};
    std::mutex infer_mutex;  // serialise inference calls
};

extern "C" {

MNN_LLM_API
mnn_llm_t* mnn_llm_create(void) {
    return new mnn_llm();
}

MNN_LLM_API
int mnn_llm_load(mnn_llm_t* llm, const char* config_path) {
    if (!llm || !config_path) return MNN_ERR_INVALID;
    if (llm->engine) {
        MNN::Transformer::Llm::destroy(llm->engine);
        llm->engine = nullptr;
    }
    llm->engine = MNN::Transformer::Llm::createLLM(config_path);
    if (!llm->engine) return MNN_ERR_LOAD;
    if (!llm->engine->load()) {
        MNN::Transformer::Llm::destroy(llm->engine);
        llm->engine = nullptr;
        return MNN_ERR_LOAD;
    }
    return MNN_OK;
}

MNN_LLM_API
int mnn_llm_set_config(mnn_llm_t* llm, const char* json_config) {
    if (!llm || !llm->engine || !json_config) return MNN_ERR_INVALID;
    if (!llm->engine->set_config(json_config)) return MNN_ERR_CONFIG;
    return MNN_OK;
}

MNN_LLM_API
int mnn_llm_chat(mnn_llm_t* llm,
                 const char* prompt,
                 mnn_stream_cb stream_cb,
                 mnn_done_cb done_cb,
                 void* user_data) {
    if (!llm || !llm->engine || !prompt) return MNN_ERR_INVALID;
    std::lock_guard<std::mutex> lock(llm->infer_mutex);
    llm->cancel_flag.store(false);

    StreamCallbackBuf buf(stream_cb, user_data, &llm->cancel_flag);
    std::ostream os(&buf);

    try {
        llm->engine->response(prompt, &os, /*end_with=*/nullptr,
                              /*max_new_tokens=*/-1);
    } catch (...) {
        if (done_cb) done_cb(3, "inference error", user_data);
        return MNN_ERR_INFER;
    }

    int status = status_to_code(llm->engine->getContext()->status);
    const char* msg = (status == 0) ? "ok"
                     : (status == 1) ? "max_tokens"
                     : (status == 2) ? "cancelled"
                                     : "error";
    if (done_cb) done_cb(status, msg, user_data);
    return MNN_OK;
}

MNN_LLM_API
void mnn_llm_stop(mnn_llm_t* llm) {
    if (llm) llm->cancel_flag.store(true);
}

MNN_LLM_API
void mnn_llm_reset(mnn_llm_t* llm) {
    if (llm && llm->engine) {
        std::lock_guard<std::mutex> lock(llm->infer_mutex);
        llm->engine->reset();
    }
}

MNN_LLM_API
char* mnn_llm_get_metrics(mnn_llm_t* llm) {
    if (!llm || !llm->engine) return nullptr;
    auto* ctx = llm->engine->getContext();
    if (!ctx) return nullptr;
    std::ostringstream ss;
    ss << "{"
       << "\"prompt_len\":"  << ctx->prompt_len
       << ",\"gen_seq_len\":" << ctx->gen_seq_len
       << ",\"all_seq_len\":" << ctx->all_seq_len
       << ",\"prefill_us\":" << ctx->prefill_us
       << ",\"decode_us\":"  << ctx->decode_us
       << ",\"sample_us\":"  << ctx->sample_us
       << ",\"ttfa_us\":"    << ctx->ttfa_us
       << "}";
    std::string s = ss.str();
    char* out = static_cast<char*>(std::malloc(s.size() + 1));
    if (out) {
        std::memcpy(out, s.c_str(), s.size());
        out[s.size()] = '\0';
    }
    return out;
}

MNN_LLM_API
void mnn_llm_free_string(char* str) {
    if (str) std::free(str);
}

MNN_LLM_API
void mnn_llm_destroy(mnn_llm_t* llm) {
    if (!llm) return;
    if (llm->engine) MNN::Transformer::Llm::destroy(llm->engine);
    delete llm;
}

// ============================================================================
//  Omni (multimodal)
// ============================================================================
//
// Llm::createLLM() already returns an Omni subclass instance when the model
// config has `has_talker()` set, so mnn_omni_* reuses the same Llm engine.
// The difference is mnn_omni_chat builds a MultimodalPrompt (decoding images
// via stb_image into VARPs, and passing audio file paths through) and calls
// Llm::response(MultimodalPrompt), which the Omni subclass overrides to
// process vision / audio inputs.

namespace {

// True if [path] ends with a common image extension.
bool is_image_file(const std::string& path) {
    auto pos = path.find_last_of('.');
    if (pos == std::string::npos) return false;
    std::string ext = path.substr(pos);
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
    return ext == ".jpg" || ext == ".jpeg" || ext == ".png" || ext == ".bmp";
}

// Decode an image file into an MNN VARP (HWC, uint8, RGB). Returns a null
// VARP on failure; the caller should check before inserting into the prompt.
// extern "C++" ensures the C++ return type doesn't trigger -Wreturn-type-c-linkage.
extern "C++" MNN::Express::VARP load_image_varp(const std::string& path, int* out_w, int* out_h) {
    int w = 0, h = 0, c = 0;
    // stbi_load with req_comp=3 forces RGB regardless of source format.
    unsigned char* pixels = stbi_load(path.c_str(), &w, &h, &c, 3);
    if (!pixels) return nullptr;
    *out_w = w;
    *out_h = h;
    // Wrap the pixel buffer in a VARP. _Const copies the data, so we can
    // free the stb buffer immediately afterwards.
    auto v = MNN::Express::_Const(
        pixels, std::vector<int>{h, w, 3},
        MNN::Express::NHWC, halide_type_of<uint8_t>());
    stbi_image_free(pixels);
    return v;
}

}  // namespace

struct mnn_omni {
    // Llm* — at runtime this points to an Omni instance when the loaded
    // model is multimodal (Llm::createLLM is the factory).
    MNN::Transformer::Llm* engine = nullptr;
    std::atomic<bool> cancel_flag{false};
    std::mutex infer_mutex;
};

MNN_LLM_API
mnn_omni_t* mnn_omni_create(void) {
    return new mnn_omni();
}

MNN_LLM_API
int mnn_omni_load(mnn_omni_t* omni, const char* config_path) {
    if (!omni || !config_path) return MNN_ERR_INVALID;
    if (omni->engine) {
        MNN::Transformer::Llm::destroy(omni->engine);
        omni->engine = nullptr;
    }
    // createLLM internally checks has_talker() and returns an Omni subclass
    // instance for multimodal models, a plain Llm otherwise.
    omni->engine = MNN::Transformer::Llm::createLLM(config_path);
    if (!omni->engine) return MNN_ERR_LOAD;
    if (!omni->engine->load()) {
        MNN::Transformer::Llm::destroy(omni->engine);
        omni->engine = nullptr;
        return MNN_ERR_LOAD;
    }
    return MNN_OK;
}

MNN_LLM_API
int mnn_omni_set_config(mnn_omni_t* omni, const char* json_config) {
    if (!omni || !omni->engine || !json_config) return MNN_ERR_INVALID;
    if (!omni->engine->set_config(json_config)) return MNN_ERR_CONFIG;
    return MNN_OK;
}

MNN_LLM_API
int mnn_omni_chat(mnn_omni_t* omni,
                  const char* prompt,
                  const char** media_paths,
                  int media_count,
                  mnn_stream_cb stream_cb,
                  mnn_done_cb done_cb,
                  void* user_data) {
    if (!omni || !omni->engine || !prompt) return MNN_ERR_INVALID;
    std::lock_guard<std::mutex> lock(omni->infer_mutex);
    omni->cancel_flag.store(false);

    StreamCallbackBuf buf(stream_cb, user_data, &omni->cancel_flag);
    std::ostream os(&buf);

    // If no media, fall back to plain text response — the Omni engine
    // handles text-only turns just like a regular Llm.
    if (media_count <= 0 || !media_paths) {
        try {
            omni->engine->response(prompt, &os, /*end_with=*/nullptr,
                                   /*max_new_tokens=*/-1);
        } catch (...) {
            if (done_cb) done_cb(3, "inference error", user_data);
            return MNN_ERR_INFER;
        }
    } else {
        // Build a MultimodalPrompt: decode images to VARPs, pass audio
        // file paths through, and let the Omni subclass's
        // tokenizer_encode(MultimodalPrompt) override do the rest.
        MNN::Transformer::MultimodalPrompt mp;
        mp.prompt_template = prompt;
        int img_idx = 0, aud_idx = 0;
        for (int i = 0; i < media_count; ++i) {
            if (!media_paths[i]) continue;
            std::string path(media_paths[i]);
            if (is_image_file(path)) {
                int w = 0, h = 0;
                auto v = load_image_varp(path, &w, &h);
                if (v.get() != nullptr) {
                    MNN::Transformer::PromptImagePart part;
                    part.image_data = v;
                    part.width = w;
                    part.height = h;
                    mp.images["image_" + std::to_string(img_idx++)] = part;
                }
            } else {
                // Treat non-image files as audio. PromptAudioPart carries
                // a file_path which the Omni engine reads & decodes itself.
                MNN::Transformer::PromptAudioPart part;
                part.file_path = path;
                mp.audios["audio_" + std::to_string(aud_idx++)] = part;
            }
        }
        try {
            omni->engine->response(mp, &os, /*end_with=*/nullptr,
                                   /*max_new_tokens=*/-1);
        } catch (...) {
            if (done_cb) done_cb(3, "inference error", user_data);
            return MNN_ERR_INFER;
        }
    }

    int status = status_to_code(omni->engine->getContext()->status);
    const char* msg = (status == 0) ? "ok"
                     : (status == 1) ? "max_tokens"
                     : (status == 2) ? "cancelled"
                                     : "error";
    if (done_cb) done_cb(status, msg, user_data);
    return MNN_OK;
}

MNN_LLM_API
void mnn_omni_stop(mnn_omni_t* omni) {
    if (omni) omni->cancel_flag.store(true);
}

MNN_LLM_API
void mnn_omni_reset(mnn_omni_t* omni) {
    if (omni && omni->engine) {
        std::lock_guard<std::mutex> lock(omni->infer_mutex);
        omni->engine->reset();
    }
}

MNN_LLM_API
void mnn_omni_destroy(mnn_omni_t* omni) {
    if (!omni) return;
    if (omni->engine) MNN::Transformer::Llm::destroy(omni->engine);
    delete omni;
}

}  // extern "C"
