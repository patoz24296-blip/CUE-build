# Release status — 18 October 2026

## Available application

The delivered Sideloadly IPA is version 1.1.0, build 3, from source `186f8161f6b05f84cc636068ec3552e55ffb3440`. Its SHA-256 is `e318e639ea0140889772e54e78041abb8966bfa1bfae93a5e74297becde211bb`.

It includes Kokoro named English/Spanish voices and previews, Moonshine English recognition, multilingual Whisper, independent hearing review, visible script following/highlighting, timing and parser improvements. Initial Recommended setup downloads are necessary to use the new models. English components total about 655 MiB.

[The Apple workflow passed](https://github.com/patoz24296-blip/CUE/actions/runs/38012034522): release device IPA, native meaning/embeddings, installed iPhone simulator import/review/role/PDF/audio/OCR/export checks and macOS packaging. Windows and Linux build 3 passed from the same application source. Android build 3 passed after the Android-only optional-OCR R8 fix at `c2beb2f4627b3a2ab0fbb67ed2111bf38c10933b`.

## Verified correction awaiting compilation

Source `9e0a5a5f2182964bdb362a09090ae78584c21e02` increments the application to build 4. It closes a real timing bug: an unfinished exact prefix was blocked by the completion policy but could still be accepted by the flexible evaluation/independent-recognition fallback. All automatic paths now wait for the rest of that line. Explicit manual completion remains available.

Four engine regressions exercise an unfinished line after 20 seconds of silence in each accuracy mode, assert no attempt/advance/verification, then finish the line and confirm completion. The full suite passed: 109 tests, two separately exercised native opt-in tests skipped by default. Formatting, fatal-info analysis and three IPA packaging regressions passed. No native audio/model/parser/UI implementation changed in this correction; the installed build 3 evidence is distinguished from these build 4 engine tests.

[The build 4 Apple workflow](https://github.com/patoz24296-blip/CUE/actions/runs/39182913749) and [secondary workflow](https://github.com/patoz24296-blip/CUE/actions/runs/39182913881) were rejected before running. GitHub's check annotation states: “The job was not started because recent account payments have failed or your spending limit needs to be increased.” This is an account billing restriction. No billing settings or repository visibility were changed.

The current computer is Windows and has no Mac build host. A local Windows fallback also stopped because plugin symlink support/Developer Mode and the native desktop toolchain are unavailable. System security settings were not changed.

## Remaining release step

### Build 6: permanent free/offline requirement

Current source is 1.1.0+6. The owner clarified that every feature must remain free for everyone permanently, with no API services or spending. The optional companion-server HTTP inference client, detection UI and active preferences were removed. Old server preferences are ignored; scripts/history and local built-in models remain. See FREE_FOREVER.md. Do not seek a paid hosted-build workaround or request a spending-limit change; use a genuinely free build host. The available IPA is still build 3, and newer source changes have not been compiled into it.

Build 6 passed formatting/fatal-info analysis and 121 default tests, with two opt-in native tests skipped by that suite. The real local meaning/768-dimensional embedding/protected-information smoke test separately passed. The legacy-settings regression confirms old server preferences cannot select server inference and existing scripts/settings remain intact. Only the explicit model downloader creates an HTTP client in the app Dart source. Hosted workflows are now manual-only; no hosted build was dispatched for build 6.

### Build 5 source update

The current application source is 1.1.0+5. It adds session preparation (language, script-view choice, component readiness), visible named voice/pace assignments, a compact advanced-practice section, scene/actor-line position and retry without recording an attempt. A missing/failed second recognizer now requires explicit review before counting a mismatch. Hearing confirmations resist duplicate taps and pauses. Delayed microphone permission/stream opening cannot start capture after a stop; preparation/countdown finishing in the background waits for explicit resume. Recording indicators and core controls are present in both rehearsal views. Extended setup no longer downloads an unused high-quality recognizer.

Verification: 120 default tests passed, with two opt-in native tests skipped in that suite. Formatting and fatal-info analysis passed. The real native partner-quality test separately generated and re-transcribed three English and two Spanish Kokoro voices and exercised Moonshine/Whisper. Its host measurements were 216 ms for the Moonshine fixture and about 1.3–2.6 seconds of generation for 3–4 seconds of speech. These are Windows measurements, not physical iPhone performance or a human listening evaluation.

The actual UI was rendered using CUE's theme/fonts and inspected at 390×844. Regression tests exercise session setup, language switching, script following and retry at phone size, including 320×568 at 1.6× text. Microphone lifecycle races use an injected delayed recorder; they do not certify physical iPhone routing. Build 5 is source-only pending a successful new Apple build; the delivered IPA remains build 3. Since audio lifecycle code changed, run the full installed native checks for this update rather than relying only on build 3 evidence.

Build `main` on a local Mac using the existing iOS scripts, or use genuinely free build capacity. Hosted workflows are manual-only to prevent automatic resource use and must not incur charges. Run the complete native checks for the new audio lifecycle code. Verify hashes and package contents, and replace the build 3 files only after confirming the current build 6 in Info.plist. Android signing uses the persistent local identity; never upload `.tools` or signing material. Do not request a paid plan or spending change.

Sideloadly signs/installs an already compiled IPA; it cannot compile the Dart/Swift/C++ source or add this correction to build 3. Do not rename or edit version metadata to represent an old binary as a new build.

Physical iPhone 16e signing/install, echo, Bluetooth and real-device latency are still unverified here. Automatic language switching inside one bilingual line and unrestricted emotional voice acting are not implemented.
