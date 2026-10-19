import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cue/services/session_recording.dart';

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cue-recording-');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });
  Uint8List pcm(List<int> samples) {
    final bytes = ByteData(samples.length * 2);
    for (var i = 0; i < samples.length; i++) {
      bytes.setInt16(i * 2, samples[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  test('Microphone samples persist only during explicit recording', () async {
    final recording = await SessionRecording.open(
      File('${temporary.path}/run.wav'),
    );
    recording.addMicrophone(pcm([1000, 2000]));
    expect(await recording.finish(), isNull);
    expect(await recording.file.exists(), isFalse);
  });
  test('Timeline mixing saturates safely and writes a valid WAV', () async {
    final recording = await SessionRecording.open(
      File('${temporary.path}/run.wav'),
    );
    await recording.addPcm(pcm([30000, -30000]), atMs: 0);
    await recording.addPcm(pcm([10000, -10000]), atMs: 0);
    await recording.addPcm(pcm([123]), atMs: 100);
    final file = (await recording.finish())!;
    final bytes = ByteData.sublistView(await file.readAsBytes());
    expect(bytes.getUint32(40, Endian.little), 3202);
    expect(bytes.getInt16(44, Endian.little), 32767);
    expect(bytes.getInt16(46, Endian.little), -32768);
    expect(bytes.getInt16(44 + 1600, Endian.little), 0);
    expect(bytes.getInt16(44 + 3200, Endian.little), 123);
    await recording.addPcm(pcm([555]), atMs: 0);
    expect(await file.length(), 3246);
  });
  test(
    'Partner audio is resampled and limited to the portion actually played',
    () async {
      final partner = File('${temporary.path}/partner.wav');
      await partner.writeAsBytes([
        ...waveHeader(32000, rate: 32000),
        ...pcm(List.filled(16000, 1000)),
      ]);
      final recording = await SessionRecording.open(
        File('${temporary.path}/run.wav'),
      );
      await recording.addWave(partner, atMs: 0, playedMs: 100, volume: .5);
      final bytes = ByteData.sublistView(
        await (await recording.finish())!.readAsBytes(),
      );
      expect(bytes.getUint32(40, Endian.little), 3200);
      expect(bytes.getInt16(44, Endian.little), 500);
    },
  );
  test('Discard immediately deletes an unfinished recording', () async {
    final recording = await SessionRecording.open(
      File('${temporary.path}/run.wav'),
    );
    await recording.addPcm(pcm([100]), atMs: 0);
    await recording.discard();
    expect(await recording.file.exists(), isFalse);
  });
  test(
    'Finishing while leaving the screen closes a recording only once',
    () async {
      final recording = await SessionRecording.open(
        File('${temporary.path}/run.wav'),
      );
      unawaited(recording.addPcm(pcm([100, 200]), atMs: 0));
      final results = await Future.wait([
        recording.finish(),
        recording.finish(),
      ]);
      expect(results.first?.path, results.last?.path);
      recording.dispose();
      await Future.wait([recording.discard(), recording.discard()]);
      expect(await recording.file.exists(), isFalse);
    },
  );
}
