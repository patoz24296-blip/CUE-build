#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
native="$PWD/packages/cue_native"
out="$PWD/build/cue-native-ios"
mkdir -p "$out" "$native/ios/Native"
sdks=(iphoneos)
if [[ "${CUE_IOS_DEVICE_ONLY:-0}" != 1 ]]; then sdks+=(iphonesimulator); fi
for sdk in "${sdks[@]}"; do
  architectures=arm64
  if [[ "$sdk" == iphonesimulator ]]; then architectures='arm64;x86_64'; fi
  cmake -S "$native/src" -B "$out/$sdk" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES="$architectures" -DCMAKE_OSX_DEPLOYMENT_TARGET=15.5 \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
  cmake --build "$out/$sdk" --config Release --target cue_native --parallel 3
done
python3 - "$native/ios/Native/cue_native.xcframework" <<'PY'
import pathlib, shutil, sys
target = pathlib.Path(sys.argv[1]).resolve()
assert target.name == 'cue_native.xcframework' and target.parent.name == 'Native'
if target.exists(): shutil.rmtree(target)
PY
frameworks=(-framework "$out/iphoneos/Release-iphoneos/cue_native.framework")
if [[ "${CUE_IOS_DEVICE_ONLY:-0}" != 1 ]]; then
  frameworks+=(-framework "$out/iphonesimulator/Release-iphonesimulator/cue_native.framework")
fi
xcodebuild -create-xcframework "${frameworks[@]}" -output "$native/ios/Native/cue_native.xcframework"
