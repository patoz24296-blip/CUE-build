# CUE — current local handoff

CUE is an implemented Flutter application. The original scaffold handoff has been superseded; its history remains in Git. The private source repository is https://github.com/patoz24296-blip/CUE.

## Product and release

CUE is permanently free for every user, with all features included. Scripts, recognition, voices, meaning evaluation, recordings and history stay local. There are no accounts, advertisements, paid voices, subscriptions, usage credits or external AI calls. Models require an explicit initial download, then rehearsal works offline. Read docs/FREE_FOREVER.md before making product or release-infrastructure decisions; the owner prohibits paid services and spending changes.

The primary target is iPhone, iOS 15.5 or newer. `.github/workflows/ios-ipa.yml` builds actual ARM64 release code and packages an unsigned `CUE.ipa` for Sideloadly to sign. It also runs installed iPhone simulator checks and creates a macOS app. `.github/workflows/platform-builds.yml` creates Windows, Linux and unsigned Android packages. Android release signing uses a persistent key on the owner's computer; private signing material is not uploaded to GitHub.

## Implemented scope

- Script library, original sample, Fountain/TXT/FDX/DOCX/PDF/photo imports, local OCR and Script check editing/search/ownership/scene repair.
- Hidden actor dialogue or explicit Follow script with automatic scrolling/current-line highlighting; local Moonshine v2 English, multilingual Whisper, Silero and named Kokoro English/Spanish voices with previews; independent audio rechecking before counting uncertain mistakes; hands-free content-aware completion, protected-information evaluation, hints and pause recovery.
- Scene Partner, Cue Drill with reduced cues, weakest/imperfect/custom Line Drill and Rehearsal; selected ranges, loops and multiple scenes.
- Four accuracy modes, optional real local Nomic embeddings and built-in Qwen reasoning; no external or companion-server inference.
- Character/scene performance directions, voice/pace assignments, clause emphasis, supported volume/pauses and controlled timing variation.
- Immediate repeat with reused models; exact hint timestamps/counts, unfinished-run history, historical dialogue snapshots, repeated-alternative decisions and progress trends.
- Explicit opt-in mixed WAV recordings, playback, streaming native export, deletion/retention and CSV/JSON results export.
- Verified/resumable component management, three quality presets, multilingual/high-quality recognition, microphone selection, desktop storage relocation, themes, text scaling, semantics, keyboard controls and optional sounds.

See README.md and docs/FEATURE_COVERAGE.md for behavior and practical limits. SQLite schema is version 4, with tested upgrades from versions 1, 2 and 3.

Version 1.1.0+5 includes the voice/recognition/timing/parser upgrade and the build 4 unfinished-prefix fix, plus explicit session preparation, named cast summaries, script-view choice before starting, recovery without penalties, safe asynchronous hearing review and microphone/background cancellation. See docs/MODEL_DECISIONS.md for models and docs/PRODUCTION_ACCEPTANCE.md for professional-use checks. Existing scripts/history are preserved; old voice assignments migrate. Upgrades must download Kokoro and the new recognizers through Recommended setup. Do not label the earlier IPA as this update.

Current source is 1.1.0+6: the old optional server client, its UI and active settings have been removed. Existing saved server preferences are ignored while scripts/history are preserved. Rehearsal uses only built-in local inference. Do not request API credentials, payment details, a paid build plan or spending-limit changes; a free build host is required for the pending new IPA.

Build 6 verification: formatting/fatal-info analysis and 121 default tests passed (two native opt-in tests skipped there). The actual local Qwen judgment, 768-dimensional Nomic embeddings and protected-information smoke test also passed. Manual review finds only the explicit component downloader creates an HTTP client in app Dart source. Hosted workflow push/PR triggers were removed; no hosted build was dispatched for this change.

The owner subsequently authorized a public current-source copy at https://github.com/patoz24296-blip/CUE-build to use standard free public macOS runners. The original repository remains private; original Git history, personal documents and signing material were excluded. Build 7 also fixes session preparation for existing Portuguese/Japanese/Chinese/Korean/Russian settings so the language dropdown matches the supported Settings choices. Non-English/Spanish listening explicitly explains the English partner-voice fallback. Rebuild and verify the current build 7 IPA; do not deliver an earlier compiled version as current.

Delivery status on 18 October 2026: the available IPA and desktop/Android packages are build 3. The build 4 correction passed 109 Flutter tests, analysis and three IPA packaging tests, but GitHub rejected both new workflows before any runner started because account payments failed or the spending limit must be increased. Do not claim build 4 was compiled or included in `CUE.ipa`. See docs/RELEASE_STATUS.md for source/build evidence and the exact remaining step.

Build 5 source passed 120 default tests (two native opt-in tests skipped there), fatal-info analysis and actual native English/Spanish voice generation/recognition. The UI was rendered and inspected at phone dimensions; tests also exercise 320×568 with 1.6× text. The new microphone lifecycle checks use a delayed recorder test double; physical iPhone capture still requires hardware evidence. Build 5 has not yet been compiled into an IPA.

## Development and verification

Pinned toolchain: Flutter 3.35.4 / Dart 3.9.2. Use the committed dependency lockfile. Native llama.cpp source is pinned to b5046 and verified before compilation.

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test integration_test tool/native_inference_smoke.dart packages/cue_native/lib
flutter analyze --fatal-infos
flutter test
```

The default suite covers evaluation, parsers/imports, migrations, downloads/relocation, hints/ranges/drills, recording mixing/cleanup/concurrent finish, exports/progress and phone layouts/flows. Real native audio inference is verified separately with test/native_audio_smoke_test.dart; native meaning/embeddings with tool/native_inference_smoke.dart. Installed simulator tests are in integration_test/iphone_test.dart. The OCR SDK needs an Intel simulator, so CI uses macos-15-intel. The delivered BUILD_VALIDATION.md records the exact release commit, build evidence and checksums.

## Hardware validation

A connected physical iPhone is still needed to verify Sideloadly signing/install, microphone/speaker echo, Bluetooth routes, calls/locks and real-device latency. Follow docs/IPHONE_SMOKE_TEST.md. Do not treat simulator/native-model evidence as proof of these physical hardware results.
