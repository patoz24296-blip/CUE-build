Pod::Spec.new do |s|
  s.name = 'cue_native'
  s.version = '1.0.0'
  s.summary = 'CUE local meaning inference.'
  s.description = 'CPU llama.cpp inference without a server.'
  s.homepage = 'https://github.com/ggml-org/llama.cpp'
  s.license = { :type => 'MIT', :file => '../LICENSE' }
  s.author = { 'CUE' => 'CUE' }
  s.source = { :path => '.' }
  s.dependency 'Flutter'
  s.platform = :ios, '15.5'
  s.vendored_frameworks = 'Native/cue_native.xcframework'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
