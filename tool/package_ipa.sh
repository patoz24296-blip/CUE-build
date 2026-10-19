#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/build/ios/iphoneos/Runner.app"
test -f "$app/Info.plist"
test -x "$app/Runner"
test -d "$app/Frameworks/Flutter.framework"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist"
lipo "$app/Runner" -verify_arch arm64
for symbol in cue_load cue_complete cue_embed cue_free; do
  nm -gU "$app/Frameworks/cue_native.framework/cue_native" | grep "_$symbol$" > /dev/null
done
mkdir -p build/sideload/Payload
ditto "$app" build/sideload/Payload/CUE.app
python3 - <<'PY'
import pathlib, shutil
root = pathlib.Path('build/sideload/Payload/CUE.app').resolve()
for signature in root.rglob('_CodeSignature'):
    assert root in signature.parents
    shutil.rmtree(signature)
for profile in root.rglob('embedded.mobileprovision'):
    profile.unlink()
PY
(cd build/sideload && /usr/bin/zip -qry CUE.ipa Payload)
python3 tool/verify_ipa.py build/sideload/CUE.ipa
shasum -a 256 build/sideload/CUE.ipa > build/sideload/CUE.ipa.sha256
