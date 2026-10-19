#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
device=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; devices=[d for group in json.load(sys.stdin)["devices"].values() for d in group if d["name"].startswith("iPhone")]; print(devices[0]["udid"])')
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
flutter build ios --debug --simulator --no-pub --target integration_test/iphone_test.dart
xcrun simctl install "$device" build/ios/iphonesimulator/Runner.app
container=$(xcrun simctl get_app_container "$device" studio.cue.cue data)
mkdir -p "$container/Library/Application Support/cue-test-fixtures"
ditto build/smoke-models "$container/Library/Application Support/cue-test-fixtures"
flutter test integration_test/iphone_test.dart --no-pub -d "$device" --timeout 12m
