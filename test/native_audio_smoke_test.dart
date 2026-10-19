import 'dart:io';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:cue/services/local_audio.dart';

void main() {
  final root = Platform.environment['CUE_SMOKE_MODELS'];
  final library = Platform.environment['CUE_SHERPA_LIBRARY'];
  test(
    'Real Whisper, Silero and neural voice inference in persistent workers',
    () async {
      if (Platform.isWindows) {
        DynamicLibrary.open(p.join(library!, 'onnxruntime.dll'));
      }
      sherpa.initBindings(library);
      final input = sherpa.readWave(p.join(root!, 'input.wav'));
      final asr = await InferenceWorker.open({
        'type': 'asr',
        'root': p.join(root, 'whisper-tiny'),
        'prefix': 'tiny.en',
        'library': library!,
      });
      final vad = await InferenceWorker.open({
        'type': 'vad',
        'root': p.join(root, 'vad'),
        'sensitivity': .5,
        'library': library,
      });
      final tts = await InferenceWorker.open({
        'type': 'tts',
        'root': p.join(root, 'voices'),
        'library': library,
      });
      try {
        final transcript = await asr.call('transcribe', {
          'samples': input.samples,
        });
        expect((transcript as String).toLowerCase(), contains('yellow lamps'));
        var detected = false;
        for (var i = 0; i + 512 < input.samples.length; i += 512) {
          detected =
              await vad.call('vad', {
                    'samples': Float32List.sublistView(
                      input.samples,
                      i,
                      i + 512,
                    ),
                  })
                  as bool ||
              detected;
        }
        expect(detected, isTrue);
        final target = p.join(root, 'generated.wav');
        await tts.call('speak', {
          'text': 'Meet me at seven tomorrow.',
          'voice': 0,
          'speed': 1.0,
          'path': target,
        });
        final generated = sherpa.readWave(target);
        expect(generated.samples.length, greaterThan(22050));
        // Recognize the actual generated scene-partner voice; catches mismatched
        // voice data/configuration beyond mere native handle creation.
        final second = await asr.call('transcribe', {
          'samples': _resample(generated.samples, generated.sampleRate),
        });
        expect((second as String).toLowerCase(), contains('tomorrow'));
      } finally {
        await asr.dispose();
        await vad.dispose();
        await tts.dispose();
      }
    },
    skip: root == null || library == null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Float32List _resample(Float32List samples, int rate) {
  final out = Float32List((samples.length * 16000 / rate).floor());
  for (var i = 0; i < out.length; i++) {
    out[i] = samples[(i * rate / 16000).floor()];
  }
  return out;
}
