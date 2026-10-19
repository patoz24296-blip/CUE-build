# Third-party engines and assets

Dependencies retain their own licenses. The model manager downloads immutable revision URLs and validates upstream LFS SHA-256 or Git blob SHA-1 identities. See `assets/models.json` for every file, byte count and digest.

| Component | Source / license |
| --- | --- |
| Flutter / Dart | [Flutter](https://github.com/flutter/flutter), BSD-style license |
| sherpa-onnx 1.13.8 | [k2-fsa](https://github.com/k2-fsa/sherpa-onnx), Apache-2.0 |
| ONNX Runtime | [Microsoft](https://github.com/microsoft/onnxruntime), MIT |
| Windows compiler runtime | Microsoft Visual C++ redistributable runtime, bundled from the build toolchain under Microsoft's redistribution terms |
| Whisper tiny.en / base.en / small.en / multilingual tiny | [Whisper](https://github.com/openai/whisper), MIT; ONNX conversion from [sherpa model catalog](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/index.html) |
| Whisper multilingual base | [Whisper](https://github.com/openai/whisper), MIT; pinned sherpa conversion |
| Moonshine v2 base English ORT | [Converted model and license](https://huggingface.co/csukuangfj2/sherpa-onnx-moonshine-base-en-quantized-2026-02-27), English weights MIT; non-English Moonshine weights are not included |
| Kokoro 82M v1.0 FP32 | [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M), Apache-2.0 weights; [conversion](https://huggingface.co/csukuangfj/kokoro-multi-lang-v1_0); downloaded eSpeak NG data retains upstream GPL terms |
| Silero VAD | [Silero](https://github.com/snakers4/silero-vad), MIT; sherpa-onnx release model |
| Piper LibriTTS-R medium | [Converted model and card](https://huggingface.co/csukuangfj/vits-piper-en_US-libritts_r-medium), model-card attribution/license; eSpeak NG data uses its upstream GPL terms and is downloaded with the model |
| llama.cpp b5046 | [ggml-org](https://github.com/ggml-org/llama.cpp), MIT |
| Qwen2.5 0.5B Instruct GGUF | [Qwen](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF), Apache-2.0; license downloaded with the model |
| Nomic embed text v1.5 GGUF | [Nomic](https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF), Apache-2.0; pinned Q4_K_M model |
| Desktop OCR | [Tesseract](https://github.com/tesseract-ocr/tesseract), Apache-2.0; optional separately installed engine |
| Latin OCR | [Google ML Kit on-device Text Recognition](https://developers.google.com/ml-kit/vision/text-recognition), Google SDK terms |
| Manrope / Literata | SIL Open Font License 1.1; full licenses in `assets/fonts/` |
| The Last Light | Original sample scene written for CUE; included for rehearsal and testing |

Piper/eSpeak integration and each downloaded model's terms should be reviewed before public redistribution. This repository builds a private sideload artifact; an App Store distribution has not been reviewed. CUE does not strip model attribution or sell paid model access.
