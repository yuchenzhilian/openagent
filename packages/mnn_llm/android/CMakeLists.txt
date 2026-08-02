# CMakeLists.txt for packages/mnn_llm Android native library.
# Builds libmnn_llm.so from the C API wrapper and links against the
# prebuilt libMNN.so (LLM-enabled) downloaded by scripts/download_mnn_prebuilt.sh.
cmake_minimum_required(VERSION 3.10)
project(mnn_llm LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---- MNN prebuilt location ----
# Expected layout under third_party/mnn/android/arm64-v8a/:
#   include/        MNN headers (MNN/, transformers/llm/engine/include/llm/)
#   libMNN.so       prebuilt shared library
set(MNN_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/mnn)
set(MNN_ANDROID_ROOT ${MNN_ROOT}/android/${ANDROID_ABI})

# ---- C API wrapper sources ----
add_library(mnn_llm SHARED
    ../src/mnn_llm_capi.cpp
)

target_include_directories(mnn_llm PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../src
    ${MNN_ANDROID_ROOT}/include
    ${MNN_ANDROID_ROOT}/include/transformers/llm/engine/include
    # 3rd_party/imageHelper/stb_image.h is used for multimodal image decoding.
    ${MNN_ANDROID_ROOT}/include/3rd_party
    # 3rd_party/flatbuffers/include/flatbuffers/*.h pulled in by MNN schema headers.
    ${MNN_ANDROID_ROOT}/include/3rd_party/flatbuffers/include
    # 3rd_party/half/half.hpp used internally by MNN FP16 conversion helpers.
    ${MNN_ANDROID_ROOT}/include/3rd_party/half
)

# ---- Link prebuilt MNN shared libraries ----
# The official MNN Android prebuilt (3.6.1) is built with -DMNN_SEP_BUILD=ON,
# so LLM, Express, and backend libs are separate .so files. Our C API wrapper
# directly references symbols from libMNN.so (core), libMNN_Express.so (VARP /
# _Const for multimodal image tensors) and libllm.so (Llm engine).
set(MNN_LIBS MNN MNN_Express llm)
foreach(lib ${MNN_LIBS})
    add_library(${lib} SHARED IMPORTED)
    set_target_properties(${lib} PROPERTIES
        IMPORTED_LOCATION ${MNN_ANDROID_ROOT}/lib${lib}.so
    )
    target_link_libraries(mnn_llm PRIVATE ${lib})
endforeach()

# Allow C symbols to be loaded by Dart FFI via DynamicLibrary.open.
target_link_options(mnn_llm PRIVATE
    "-Wl,--exclude-libs,ALL"
)
