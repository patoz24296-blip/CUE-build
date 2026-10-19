#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cmake -S packages/cue_native/src -B build/cue-native-macos -G Xcode \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=10.15
cmake --build build/cue-native-macos --config Release --target cue_native --parallel 3
mkdir -p packages/cue_native/macos/Native
ditto build/cue-native-macos/Release/cue_native.framework packages/cue_native/macos/Native/cue_native.framework
