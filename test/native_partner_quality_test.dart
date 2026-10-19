import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:cue/services/local_audio.dart';

void main() {
  final root = Platform.environment['CUE_SMOKE_MODELS'];
  final library = Platform.environment['CUE_SHERPA_LIBRARY'];
  test(
    'Real Kokoro English/Spanish voices and Moonshine v2 recognition',
    () async {
      if (Platform.isWindows) {
        DynamicLibrary.open(p.join(library!, 'onnxruntime.dll'));
      }
      sherpa.initBindings(library);
      final asr = await InferenceWorker.open({
        'type': 'asr',
        'family': 'moonshine',
        'prefix': '',
        'root': p.join(root!, 'moonshine'),
        'library': library!,
      });
      final check = await InferenceWorker.open({
        'type': 'asr',
        'prefix': 'base.en',
        'root': p.join(root, 'whisper-base'),
        'library': library,
      });
      final spanish = await InferenceWorker.open({
        'type': 'asr',
        'prefix': 'base',
        'language': 'es',
        'root': p.join(root, 'whisper-base-multilingual'),
        'library': library,
      });
      try {
        final input = sherpa.readWave(p.join(root, 'input.wav'));
        final timer = Stopwatch()..start();
        final text = await asr.call('transcribe', {'samples': input.samples});
        expect((text as String).toLowerCase(), contains('yellow lamps'));
        // ignore: avoid_print
        print(
          'Moonshine sample transcription ${timer.elapsedMilliseconds} ms: $text',
        );
        for (final language in ['en', 'es']) {
          final tts = await InferenceWorker.open({
            'type': 'tts',
            'family': 'kokoro',
            'root': p.join(root, 'kokoro'),
            'language': language,
            'library': library,
          });
          try {
            for (final voice
                in language == 'en' ? [1003, 1017, 1021] : [1028, 1029]) {
              final file = p.join(root, 'kokoro-$voice.wav');
              timer.reset();
              await tts.call('speak', {
                'text': language == 'en'
                    ? 'Wait. Before you go, there is something I need to tell you.'
                    : 'No te vayas todavía. Necesito decirte algo.',
                'voice': voice,
                'speed': 1.0,
                'path': file,
              });
              final audio = sherpa.readWave(file);
              expect(audio.samples.length, greaterThan(audio.sampleRate));
              expect(audio.samples.every((v) => v.isFinite), isTrue);
              final rms = sqrt(
                audio.samples.fold<double>(0, (s, v) => s + v * v) /
                    audio.samples.length,
              );
              expect(rms, inExclusiveRange(.005, .5));
              // ignore: avoid_print
              print(
                'Kokoro $voice $language: ${timer.elapsedMilliseconds} ms generation; ${(audio.samples.length / audio.sampleRate).toStringAsFixed(2)} seconds audio; RMS $rms',
              );
              {
                final samples = Float32List(
                  (audio.samples.length * 16000 / audio.sampleRate).floor(),
                );
                for (var i = 0; i < samples.length; i++) {
                  samples[i] =
                      audio.samples[(i * audio.sampleRate / 16000).floor()];
                }
                final heard = await (language == 'en' ? check : spanish).call(
                  'transcribe',
                  {'samples': samples},
                );
                expect(
                  (heard as String).toLowerCase(),
                  contains(language == 'en' ? 'tell you' : 'decirte'),
                );
              }
            }
          } finally {
            await tts.dispose();
          }
        }
      } finally {
        await asr.dispose();
        await check.dispose();
        await spanish.dispose();
      }
    },
    skip:
        root == null ||
        library == null ||
        Platform.environment['CUE_PARTNER_QUALITY'] != '1',
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
