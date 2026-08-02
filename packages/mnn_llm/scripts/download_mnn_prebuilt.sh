#!/usr/bin/env bash
# Download prebuilt MNN libraries (LLM-enabled) for Android arm64-v8a.
#
# Since MNN 3.6.0 the official GitHub Releases ship prebuilt Android .so files
# built with -DMNN_SEP_BUILD=ON (libMNN.so, libllm.so, libMNN_Express.so,
# libMNNAudio.so, libMNNOpenCV.so, libMNN_CL.so, libMNN_Vulkan.so, …).
# This script downloads those binaries plus the matching header tree so the
# FFI plugin can be compiled without NDK / cmake / Docker.
#
# Output layout:
#   third_party/mnn/android/arm64-v8a/
#       include/                                MNN + 3rd_party + llm headers
#       include/transformers/llm/engine/include/llm/llm.hpp
#       libMNN.so  libllm.so  libMNN_Express.so  …
#
# Prerequisites: curl (or wget) + unzip + tar. No NDK required.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MNN_ROOT="${PLUGIN_ROOT}/third_party/mnn"
ANDROID_ROOT="${MNN_ROOT}/android/arm64-v8a"
MNN_TAG="3.6.1"
DL_DIR="${MNN_ROOT}/_download"

mkdir -p "${ANDROID_ROOT}/include" "${DL_DIR}"

# ---- 1. Prebuilt .so files ----
PREBUILT_ZIP="mnn_${MNN_TAG}_android_armv7_armv8_cpu_opencl_vulkan.zip"
PREBUILT_URL="https://github.com/alibaba/MNN/releases/download/${MNN_TAG}/${PREBUILT_ZIP}"

if [ ! -f "${ANDROID_ROOT}/libMNN.so" ]; then
  echo "==> Downloading prebuilt Android libraries (${MNN_TAG})"
  if command -v curl >/dev/null 2>&1; then
    curl -fL -o "${DL_DIR}/${PREBUILT_ZIP}" "${PREBUILT_URL}"
  else
    wget -q -O "${DL_DIR}/${PREBUILT_ZIP}" "${PREBUILT_URL}"
  fi
  unzip -o "${DL_DIR}/${PREBUILT_ZIP}" -d "${DL_DIR}/prebuilt"
  # Copy arm64-v8a .so files (skip armeabi-v7a to save space).
  cp "${DL_DIR}/prebuilt"/*/arm64-v8a/*.so "${ANDROID_ROOT}/"
else
  echo "    (libMNN.so already present, skipping download)"
fi

# ---- 2. Headers from source archive ----
if [ ! -f "${ANDROID_ROOT}/include/transformers/llm/engine/include/llm/llm.hpp" ]; then
  echo "==> Downloading MNN source archive for headers (${MNN_TAG})"
  SRC_TARBALL="MNN-${MNN_TAG}.tar.gz"
  SRC_URL="https://github.com/alibaba/MNN/archive/refs/tags/${MNN_TAG}.tar.gz"
  if command -v curl >/dev/null 2>&1; then
    curl -fsL -o "${DL_DIR}/${SRC_TARBALL}" "${SRC_URL}"
  else
    wget -q -O "${DL_DIR}/${SRC_TARBALL}" "${SRC_URL}"
  fi
  tar -xzf "${DL_DIR}/${SRC_TARBALL}" -C "${DL_DIR}"

  SRC_DIR="${DL_DIR}/MNN-${MNN_TAG}"
  # MNN core headers (MNN/expr/Expr.hpp etc.)
  cp -r "${SRC_DIR}/include/." "${ANDROID_ROOT}/include/"
  # 3rd_party headers (imageHelper/stb_image.h)
  mkdir -p "${ANDROID_ROOT}/include/3rd_party"
  cp -r "${SRC_DIR}/3rd_party/." "${ANDROID_ROOT}/include/3rd_party/"
  # LLM engine headers (llm/llm.hpp)
  mkdir -p "${ANDROID_ROOT}/include/transformers/llm/engine/include/llm"
  cp -r "${SRC_DIR}/transformers/llm/engine/include/llm/." \
        "${ANDROID_ROOT}/include/transformers/llm/engine/include/llm/"
else
  echo "    (llm.hpp already present, skipping header download)"
fi

# ---- 3. Cleanup ----
rm -rf "${DL_DIR}"

echo "==> Done. Libraries and headers installed at ${ANDROID_ROOT}"
echo "    .so files: $(ls "${ANDROID_ROOT}"/*.so | xargs -n1 basename | tr '\n' ' ')"
