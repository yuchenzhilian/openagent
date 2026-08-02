#!/usr/bin/env bash
# Build MNN.framework for iOS (LLM + Omni + Metal acceleration).
# macOS only — run on a Mac or via GitHub Actions macos-latest.
#
# Output: third_party/mnn/ios/MNN.framework
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MNN_ROOT="${PLUGIN_ROOT}/third_party/mnn"
MNN_TAG="3.3.0"
MNN_SRC="${MNN_ROOT}/src"
IOS_OUT="${MNN_ROOT}/ios"

mkdir -p "${IOS_OUT}"

if [ ! -d "${MNN_SRC}/.git" ]; then
  echo "==> Cloning MNN ${MNN_TAG} into ${MNN_SRC}"
  git clone --depth 1 --branch "${MNN_TAG}" https://github.com/alibaba/MNN.git "${MNN_SRC}"
else
  echo "==> (MNN source already present)"
fi

cd "${MNN_SRC}"

echo "==> Building MNN.framework via official iOS build script"
# MNN ships package_scripts/ios/buildiOS.sh which produces a universal
# framework under MNN-iOS-CPU-GPU/Static/.
sh package_scripts/ios/buildiOS.sh \
  "-DMNN_ARM82=true -DMNN_LOW_MEMORY=true -DMNN_SUPPORT_TRANSFORMER_FUSE=true \
   -DMNN_BUILD_LLM=true -DMNN_METAL=ON \
   -DMNN_BUILD_OPENCV=ON -DMNN_IMGCODECS=ON -DMNN_OPENCL=OFF \
   -DMNN_BUILD_LLM_OMNI=ON -DLLM_SUPPORT_VISION=true -DLLM_SUPPORT_AUDIO=true \
   -DMNN_BUILD_AUDIO=true -DMNN_SEP_BUILD=OFF"

FRAMEWORK_SRC="MNN-iOS-CPU-GPU/Static/MNN.framework"
if [ ! -d "${FRAMEWORK_SRC}" ]; then
  echo "ERROR: ${FRAMEWORK_SRC} not found after build"
  exit 1
fi

echo "==> Installing framework to ${IOS_OUT}"
rm -rf "${IOS_OUT}/MNN.framework"
cp -R "${FRAMEWORK_SRC}" "${IOS_OUT}/"

# Copy headers so the plugin's HEADER_SEARCH_PATHS resolve.
mkdir -p "${IOS_OUT}/include"
cp -R include/. "${IOS_OUT}/include/"
mkdir -p "${IOS_OUT}/include/transformers/llm/engine/include/llm"
cp -R transformers/llm/engine/include/llm/. \
      "${IOS_OUT}/include/transformers/llm/engine/include/llm/"
# stb_image headers (used by mnn_llm_capi.cpp for multimodal image decoding).
mkdir -p "${IOS_OUT}/include/3rd_party"
cp -R 3rd_party/. "${IOS_OUT}/include/3rd_party/" 2>/dev/null || true

echo "==> Done. MNN.framework at ${IOS_OUT}/MNN.framework"
