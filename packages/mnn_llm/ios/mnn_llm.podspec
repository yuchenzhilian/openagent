Pod::Spec.new do |s|
  s.name             = 'mnn_llm'
  s.version          = '0.1.0'
  s.summary          = 'On-device LLM inference for Flutter via MNN-LLM.'
  s.description      = <<-DESC
  Flutter FFI plugin that bridges Alibaba's MNN-LLM C++ engine for
  fully offline, on-device large language model inference with streaming
  output.
                       DESC
  s.homepage         = 'https://github.com/your-name/openagent'
  s.license          = { :type => 'Apache', :file => '../../../LICENSE' }
  s.author           = { 'OpenAgent' => 'openagent@example.com' }
  s.source           = { :path => '.' }

  # All paths below are relative to this podspec's directory (ios/), so
  # the C/C++ sources and vendored framework one level up need '../'.
  s.source_files        = '../src/**/*.{h,cpp}'
  s.public_header_files = '../src/mnn_llm_capi.h'

  s.ios.deployment_target = '16.1'
  s.osx.deployment_target = '11.0'

  # MNN.framework is built by scripts/build_ios.sh and placed under
  # ../third_party/mnn/ios/. Build it before `pod install`.
  s.vendored_frameworks = '../third_party/mnn/ios/MNN.framework'

  # Metal acceleration on iOS.
  s.weak_frameworks = 'Metal', 'MetalKit', 'CoreML'

  s.libraries          = 'c++'
  # PODS_TARGET_SRCROOT points at this podspec's directory (ios/), so reach
  # the plugin root via ../ to find src/ and third_party/.
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../src" "${PODS_TARGET_SRCROOT}/../third_party/mnn/ios/include" "${PODS_TARGET_SRCROOT}/../third_party/mnn/ios/include/3rd_party"',
    'OTHER_LDFLAGS' => '-ObjC'
  }
end
