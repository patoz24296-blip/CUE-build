# CUE

A private, free, installed scene partner for actors. Import a script, choose your role, hide your dialogue and rehearse opposite local neural voices. No account, subscription, ads, telemetry or cloud AI service.

**Free for everyone, permanently.** Every feature is included. No trials, usage credits, paid voice packs, external AI APIs or required servers. See [the permanent product requirement](docs/FREE_FOREVER.md).

**iPhone is the primary release target.** The macOS GitHub Actions workflow creates a release-mode, unsigned, ARM64 device IPA that Sideloadly signs for your own iPhone. A real-device microphone, audio-route and airplane-mode smoke test is required before treating this as a production release.

## Get the iPhone IPA

1. Use the verified IPA artifact from a successful build, or build locally on a Mac using the commands below. The manual **Actions → iPhone IPA for Sideloadly** workflow is available only when genuinely free capacity is available; do not enable paid services or spending. Pushes and pull requests no longer trigger hosted builds automatically.
2. Download the **CUE-iPhone-Sideloadly** artifact. Extract its ZIP to find `CUE.ipa` and its SHA-256 checksum.
3. Connect and unlock your iPhone, trust the computer, and open [Sideloadly](https://sideloadly.io/) on Windows or macOS.
4. Select your device, drag `CUE.ipa` into Sideloadly, enter your own Apple ID, and start installation. CUE itself does not need an account; the Apple ID is only for signing the app.
5. Follow iOS's trust/developer-mode prompts if shown. Open CUE and grant microphone access when starting your first rehearsal.

CUE needs **iOS 15.5 or later**. A free Apple ID can sign the app; Sideloadly documents a seven-day validity period for free accounts and supports automatic refresh. Do not lower CUE's minimum OS version in Sideloadly: its native dependencies require 15.5. No JIT, jailbreak, application group, push entitlement, paid voice or developer subscription is required by CUE.

The IPA contains actual Flutter AOT code and native inference libraries. It is not a simulator application and is not App Store signed. Signing and physical-device validation cannot be performed on a Windows-only build host.

## First rehearsal

1. Try **The Last Light**, CUE's original sample, or add a Fountain, TXT, FDX, DOCX, PDF or photo.
2. In **Script check**, review detected scenes and characters. Tap lines to edit text, change ownership or protect phrases. Rename a character to another existing name to merge duplicates; assign selected lines to a different character to split ownership. Line menus can remove page furniture or start a new scene. Scene menus rename or merge boundaries.
3. Choose your role and a scene. **Session setup** shows language, Off book/Follow script and whether both listening checks are installed. The cast lists each named voice and pace before you start; tap to audition or change it. Open **Practice options** for practice mode, accuracy, ranges and looping. Optional range selection uses line numbers and speakers, so it does not reveal your upcoming dialogue.
4. Install **Recommended setup** in Offline components: Moonshine responsive English recognition, Kokoro natural voices, Silero listening detection and an independent Whisper recognizer. The new voices need a fresh download when upgrading from 1.0. Spanish in Settings selects multilingual Whisper and Spanish voices. Downloads are resumable and verified against pinned upstream identities.
5. Press **Rehearse**. CUE speaks partners, listens to you, evaluates after silence **and** sufficient script content, and continues. Say **“CUE please”** for a progressive hint; hold **I NEED A LINE** to hear the full line.
6. Choose **Follow script** before starting or tap the book button during rehearsal for the complete scene, automatic scrolling and current-line highlighting. On iPhone the script sits above compact controls; wider screens show it beside the controls. If independent hearings disagree, or only one hearing is available for a mismatch, confirm the hearing or try again before a mistake is recorded. **Try line again** clears the current hearing without counting an attempt. Scene/line position and recording status remain visible in both views.
7. Review results, repeat with **RUN IT AGAIN**, or drill weak lines. Disable variable timing if you want consistent cues. Microphone audio is not saved unless you explicitly enable **Record rehearsals**. Optional recordings mix your microphone with played partner cues, stay on your device, and export as WAV.

The app pauses when backgrounded or interrupted, and when an audio route becomes noisy. Resume explicitly after returning. Own lines are hidden by default; visible/initials/blurred options are explicit preferences. Large buttons, scalable text, semantic state announcements, keyboard controls and light/dark/system appearance are included. On desktop, Space pauses/resumes, H requests a hint, and Enter finishes a recognized line.

## Accuracy and timing

- **Word Perfect** compares normalized words, with configurable contraction equivalence. Accepted rehearsal variations never bypass strict mode.
- **Flexible** allows conservative inflection, auxiliary and ordering variations, while protecting information.
- **Loose / Improv** use the same protected information checks, then optionally use a local meaning model for broader paraphrases. Without a model, uncertain paraphrases explicitly need review; lexical overlap is not presented as semantic accuracy.

Negation, shifted polarity, role reversals, opposing information, protected phrases, names and numbers are checked before a model decision. Results describe textual accuracy and response timing, never acting quality. An actor can explicitly accept a variation for future non-strict runs without changing script text. After three occurrences, CUE offers to accept the wording, keep flagging it, edit the original, or decide later. Nothing is silently rewritten.

Fast/Natural/Patient response timing changes the silence required **after** sufficient line content is heard. Silence alone cannot advance an incomplete line. Loose/Improv can automatically complete a stable paraphrase when the local meaning model accepts it. **Finish line** is available for uncertain wording; **Skip this line** explicitly records a missed attempt. Overlap is optional, off by default, and requires recognized actor-line evidence that exceeds partner-echo similarity. Headphones improve separation. Physical iPhone latency and echo behavior still need field testing.

## Architecture

```text
lib/domain/       normalized script models, parser/editor, multilayer evaluator,
                  completion policy and rehearsal state machine
lib/data/         SQLite migrations, scripts/settings/history/voices/variations,
                  checksum-verified, staged/resumable local model installations
lib/services/     imports and OCR, persistent ASR/VAD/TTS inference workers,
                  built-in llama.cpp meaning/embeddings and recordings/exports
lib/ui/           library, script review, role/scene setup, rehearsal,
                  results, progress trends, recordings, settings and offline component manager
packages/cue_native/  pinned CPU llama.cpp C ABI and platform build integration
tool/             iOS/macOS native builds, IPA packaging and archive validation
```

Provider interfaces isolate speech recognition, VAD, TTS, semantic inference and parsing from the UI. Moonshine v2, Whisper INT8, Silero VAD and Kokoro 82M FP32 run through sherpa-onnx in separate persistent isolates. Models load once and are reused by immediate repeat/drill runs. Scene-partner WAV files are temporary and cached only for that rehearsal. The next complete partner cue is preloaded while the actor is responding. The optional Qwen2.5 0.5B Q4 model runs through the included llama.cpp bridge, without a server. Optional Nomic embeddings supply real local semantic evidence before meaning-model judgment; an embedding similarity alone never accepts a line. See [model selection and evidence](docs/MODEL_DECISIONS.md).

SQLite schema version 4 uses normalized tables, transactions, foreign keys and WAL. Scene boundary changes keep entry IDs and existing line attempts. Cue requests store actual levels and request timestamps, including across pauses. Historical attempts preserve the dialogue as it was performed even after script edits. Multi-scene sessions retain each scene identity. History can be deleted separately from scripts. Script deletion removes dependent history.

## Privacy

Scripts and recognition buffers never leave the device through CUE. The only normal external requests are explicit model downloads from Hugging Face and the sherpa-onnx release repository. Rehearsal, TTS, recognition, deterministic evaluation and history work without a network after installation. Fonts and sample content are bundled.

Rehearsal has no HTTP inference client, server selection or API-key setting. The only app-managed HTTP client downloads model files when explicitly requested. Device backups are controlled by your operating system; “local” does not mean OS backup encryption or exclusion is configured by CUE.

## Develop and build

Pinned toolchain: **Flutter 3.35.4 / Dart 3.9.2**. Install the normal platform prerequisites from [Flutter documentation](https://docs.flutter.dev/install). Keep `pubspec.lock` committed. Native meaning builds download the pinned, SHA-256-verified llama.cpp `b5046` source.

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test integration_test tool/native_inference_smoke.dart packages/cue_native/lib
flutter analyze --fatal-infos
flutter test
```

**iPhone, on macOS with Xcode, CocoaPods and CMake:**

```sh
bash tool/build_native_ios.sh
flutter build ios --release --no-codesign
bash tool/package_ipa.sh
# build/sideload/CUE.ipa
```

The native build produces an XCFramework with ARM64 device and universal simulator slices. The OCR SDK requires an Intel iPhone simulator; CI uses GitHub’s standard macos-15-intel runner for installed simulator tests. CocoaPods requires deployment target 15.5 for bundled Latin OCR. IPA validation checks Payload layout, device platform, bundle identity, Flutter and local meaning frameworks, archive integrity and absence of stale signatures/provisioning. Simulator builds are never accepted as sideload artifacts.

**macOS:** run `bash tool/build_native_macos.sh`, then `flutter run -d macos` or `flutter build macos`. **Windows:** install Visual Studio's Desktop Development with C++ workload, enable Developer Mode for Flutter plugin symlinks, then `flutter run -d windows` or `flutter build windows`. **Linux:** install Flutter's native Linux dependencies and CMake 3.22+, then `flutter run -d linux`. **Android:** install the Android SDK/NDK and CMake, then `flutter run` or `flutter build apk --release`. Native desktop/Android meaning libraries build through CMake. These secondary platform builds require their own native smoke tests; they are not represented as verified merely because generated runners exist.

## Verification

The default suite covers contractions, fillers, strict variations, negations, numbers, names, role/polarity reversals, parser formats and recovery, scene history preservation, download checksum rejection and resume, content-aware pauses, hints, echo-vs-actor overlap, audio failure/pause recovery, and the phone-sized import/review/role/rehearsal/results/repeat flow.

An opt-in native test also loads real Whisper, Silero and the 904-speaker neural voice model, recognizes upstream sample audio, generates partner speech and recognizes it again. Download its fixtures with `python tool/download_smoke_models.py`. Set `CUE_SMOKE_MODELS` to the resulting folder and `CUE_SHERPA_LIBRARY` to the platform native library **directory**, then run `flutter test test/native_audio_smoke_test.dart`. On Windows the test preloads the bundled ONNX Runtime to avoid the older system DLL. This verifies the actual providers on the host, not an iPhone microphone.

Before release, follow [the iPhone smoke checklist](docs/IPHONE_SMOKE_TEST.md). Unit/widget tests and host inference are useful evidence but cannot replace testing a sideloaded physical phone.

## Complete rehearsal controls

- Run one scene, a selected range, or all scenes in script order. Line Drill supports weakest, imperfect, and custom selected actor lines without exposing their dialogue during selection.
- Assign named English or Spanish voices with **Listen to this voice**, pace, and a free-text performance direction. Older anonymous assignments migrate to named voices. Add a separate scene direction. Full Performance preserves whole-line neural phrasing and adjusts supported pace, volume and pauses; consistent timing remains available.
- Adjust Fast/Natural/Patient timing, dramatic-pause allowance, VAD sensitivity, interruption behavior, stage-direction display/reading, line visibility, configurable spoken hint command, spoken hints, sounds, and microphone input.
- Track latest off-book coverage, response/hint/accuracy trends and weak lines. Rewriting a line requires a fresh attempt before it counts as off book. Export results as CSV or JSON with cue timestamps.
- Recording is opt-in. Play, export or delete recordings, delete them with associated history/scripts, and choose automatic retention (or keep until manually deleted). Exports use the native Files/document picker on iPhone and Android and file selection on desktop.
- Select quick English, detailed English, high-quality English or multilingual recognition. Lightweight and Recommended setup install the selected listening model; Recommended adds a separate recognizer. Extended setup also adds optional local meaning/phrase comparison without downloading an unused recognition model or claiming a quality change it has not enabled. Desktop model storage can be moved to another folder with verified copies.

Windows packages include the compiler runtime for computers without development tools. macOS exports use read/write access to user-selected files; selected model folders use persistent security-scoped bookmarks. If an external component folder becomes unavailable, CUE opens its internal storage and offers recovery while preserving the old files.

## Practical limits

- Curated neural voices support English and Spanish; select the language explicitly in Settings. Other Whisper recognition languages remain selectable, with English partner voices. Automatic switching within mixed-language dialogue is not implemented. Latin-script OCR is built into iPhone/Android. Desktop image/scanned-PDF OCR uses an installed free Tesseract engine. Imperfect source layouts still need Script check. Fountain dual-dialogue markers normalize ownership but do not create simultaneous voice tracks.
- Performance directions map to supported pace, volume, clause emphasis and pauses. The neural voice engine does not promise arbitrary emotional acting or voice cloning. A small local meaning model can be uncertain; malformed responses require review, and deterministic information protection runs first.
- Recognition processes long utterances in successive bounded chunks rather than imposing a rehearsal or script limit. Initial component setup requires internet and storage. Offline operation begins after models are installed.
- CUE pauses in the background and on interruptions. Physical iPhone speaker/Bluetooth/overlap behavior and Sideloadly installation need a connected phone; simulator/native-engine checks cannot establish those hardware results. No App Store distribution or hardware performance claim is made without evidence.

See [third-party notices](docs/THIRD_PARTY.md) for the local engines, model sources and font licenses.
