# CUE feature coverage

The source handoff is historical. This document describes the implemented application.

| Area | Implemented behavior | Verification |
| --- | --- | --- |
| Private installed app | Flutter iPhone, Android and desktop runners; SQLite; no account, ads, cloud AI or telemetry | Native builds plus schema migration tests |
| Script import and repair | Fountain, TXT, structured FDX, DOCX, text PDF, local image/scanned PDF OCR; rename/merge/split characters and scenes, edit lines and anchors, dialogue search | Parser/import tests; native PDF/OCR in installed iPhone simulator |
| Hands-free rehearsal | Real Whisper recognition, Silero voice detection and local neural voices; content plus silence completion; local semantic completion; configurable hints; interruption guards | Engine tests and real model inference smoke checks |
| Practice controls | Scene Partner, Cue Drill with reduced cues, weak/imperfect/custom Line Drill, Rehearsal; selected range, looping and all-scenes traversal | Engine, performance and phone flow tests |
| Accuracy | Four modes, word/order/omission checks, protected names/numbers/negation/phrases, real optional Nomic embeddings and built-in Qwen judgment, entirely on device | Adversarial evaluator tests and native inference checks |
| Partner performance | Named Kokoro English/Spanish voices with audition, visible cast assignments and pace; supported character/scene pace, volume and pauses; whole-line phrasing, controlled variation and preloading | Performance tests and actual English/Spanish voice generation/re-transcription |
| Repeated practice | Dominant Run It Again with short countdown and reused models; results, historical original text, weak-line drills, repeated-alternative decisions | Widget, database and variation tests |
| Progress | Current-role latest off-book coverage, textual accuracy trends, hint and response latency history, weak lines; fresh practice required after edits | Progress and database tests |
| Recording and export | Explicit opt-in mixed PCM WAV, clear recording state, played-cue truncation, playback, immediate deletion/retention, streaming native audio export, CSV/JSON results | Mix/resampling/concurrent-close/path/retention tests; native export channel registration |
| Model manager | Verified/resumable installs, disk use/delete, lightweight/recommended/extended presets, English and multilingual recognition, safe desktop storage relocation | Download corruption/resume/path and relocation tests |
| Access and settings | Light/dark/system, text scaling, semantics, desktop keys, large rehearsal actions, display policies, pause allowance, microphone selection, optional sounds | Small-phone enlarged-text and complete phone-sized flow tests |
| Session preparation and recovery | Language and Off book/Follow script before starting; readiness of primary and independent hearing; collapsed advanced practice controls; current scene/actor-line position; retry without counting an attempt | Phone setup/retry tests; delayed hearing confirmation, duplicate-tap, pause and microphone-opening regressions |

## Remaining hardware validation

A physical iPhone is required to verify Sideloadly installation, microphone/speaker echo, Bluetooth routing, locks/calls and device-specific latency. Use IPHONE_SMOKE_TEST.md. The IPA validation checks an actual ARM64 iPhone device archive; simulator evidence does not substitute for these hardware checks.

Model performance is device dependent. Full Performance uses the neural TTS engine's supported controls; it does not claim arbitrary emotional acting. Desktop OCR uses a separately installed Tesseract engine. Models require an initial download, then normal rehearsal is offline.
