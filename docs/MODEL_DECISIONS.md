# CUE 1.1: local models and scene-partner repair

Target: iPhone 16e, mainly English with Spanish rehearsals. Research checked on 9 October 2026. Selection weighs native compatibility, audio quality, latency, memory, downloads and permission to use the app professionally. There is no evidence that one free model is universally best at every task.

## Selected and integrated

| Task | Model and behavior | Verified download |
| --- | --- | --- |
| Partner speech | Kokoro 82M v1.0, full precision; named US/UK English and Spanish voices with previews; whole lines preserve neural phrasing | 384,088,732 bytes |
| English hearing | Moonshine v2 base English, quantized ORT; repeated partial decoding while speaking and a final decode after silence | 141,313,910 bytes |
| Independent English hearing | Whisper base.en INT8, used when the primary hearing fails script evaluation | Installed by Recommended setup |
| Spanish hearing | Whisper multilingual base INT8; language selected explicitly in Settings | 160,609,290 bytes |
| Independent Spanish hearing | Whisper multilingual tiny INT8; installed by the Spanish Recommended setup | Separate recognizer on the same audio |
| Speech activity | Silero VAD with bounded buffers | Existing verified component |
| Meaning and embeddings | Optional Qwen2.5 0.5B Instruct Q4 and Nomic embed text v1.5 Q4 | Existing native integration retained |
| Script import | Native Latin OCR plus repaired ownership/scene parsing; indented PDFs no longer lose their first dialogue | On-device extraction; Script check remains editable |

Exact immutable revisions, file sizes, licenses and integrity hashes are in `assets/models.json`. Kokoro conversion: `f7b96bb6bef5c5da4d3aa4f4e0498fbbf62dc78b`; Moonshine conversion: `8f4d6c58c03d40bcea40043bb7120a878f2bbef6`; multilingual Whisper base: `bb53ee204431c90d314c1cc08d28d23e5b7927cc`.

[Kokoro's model card](https://huggingface.co/hexgrad/Kokoro-82M) documents its 82M architecture and Apache-2.0 weights. [The official voice list](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md) distinguishes accents and voice training data. CUE exposes a curated selection, rather than an anonymous speaker number. [Sherpa's converted model documentation](https://k2-fsa.github.io/sherpa/onnx/tts/all/Chinese-English/kokoro-multi-lang-v1_0.html) establishes the actual speaker IDs. Full precision was chosen because [an upstream ARM issue](https://github.com/k2-fsa/sherpa-onnx/issues/3754) reports intermittent clipped output from INT8 Kokoro while FP32 was unaffected. This is a compatibility precaution, not an iPhone performance measurement.

[Moonshine v2's paper](https://arxiv.org/abs/2602.12241) addresses latency on resource-constrained devices. CUE integrates the base English ORT model supported by [Sherpa's v2 model interface](https://k2-fsa.github.io/sherpa/onnx/moonshine/models-v2.html), with repeated bounded utterance decoding; it does not claim to integrate the separate streaming-medium architecture. The [pinned model license](https://huggingface.co/csukuangfj2/sherpa-onnx-moonshine-base-en-quantized-2026-02-27/blob/8f4d6c58c03d40bcea40043bb7120a878f2bbef6/LICENSE) licenses English weights under MIT and other languages under a non-commercial community license. Spanish therefore uses [Whisper's MIT-licensed weights](https://github.com/openai/whisper).

The secondary recognizer receives the microphone audio, never the expected script. If the two hearings differ, CUE freezes both candidates, offers confirmation or a fresh hearing, and records no mistake until that choice. Script matching never silently rewrites a changed number or negation. The optional secondary model can fail without terminating the primary rehearsal.

## Alternatives investigated

[Chatterbox Turbo ONNX](https://huggingface.co/ResembleAI/chatterbox-turbo-ONNX) offers a larger expressive speech model, but its model card does not establish reliable iPhone 16e performance through CUE's native runtime. It is not advertised as an integrated replacement. Separate Moonshine streaming models require a different native recognizer interface; a paper benchmark does not validate this app's microphone path. [Qwen2.5 1.5B GGUF](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF) is an alternative for optional semantic comparison, but a larger language model cannot repair acoustic recognition, timing or voice selection. The existing conservative evaluator remains protected by deterministic information checks. No paid or trial cloud endpoint is used.

## Evidence and practical limits

The host native test actually loads Moonshine, independent Whisper and Kokoro, transcribes a known recording, synthesizes three English and two Spanish voices, checks finite audio and signal levels and transcribes the generated speech in each language. On this Windows host the Moonshine fixture took 207–210 ms; initial synthesis took approximately 1.3–2.3 seconds for 3–4 seconds of audio. The expanded run holding both English and Spanish recognition models concurrently took 1.2–10.8 seconds per synthesized sample. CUE opens only the selected language's recognizers. These values demonstrate that concurrency matters; they are host smoke measurements, not iPhone latency promises or human listening scores.

The visible script view scrolls to the active line, highlights it and shows recognized words. Phone layout and recognition-disagreement behavior have regression tests. Full Performance now preserves whole-line phrasing, uses modest variation and reuses exactly the same performance plan for preloading and playback. Timing responds faster to complete endings and retains an unfinished prefix through dramatic pauses.

Select English or Spanish explicitly; automatic language switching inside a mixed-language line is not implemented. Other Whisper recognition languages are available, but the curated partner voice UI is English/Spanish. Free-text direction influences supported speed, volume and pauses; it does not grant arbitrary emotional acting or voice cloning. Physical microphone echo, Bluetooth, Sideloadly installation and latency still require the actual iPhone.
