import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:cue/services/local_audio.dart';

class RecorderGate implements AudioRecorder {
  final permission = Completer<bool>();
  final opening = Completer<void>();
  bool delayOpening = false, active = false;
  int starts = 0;
  @override
  Future<bool> hasPermission({bool request = true}) => permission.future;
  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    starts++;
    if (delayOpening) await opening.future;
    active = true;
    return const Stream<Uint8List>.empty();
  }

  @override
  Future<String?> stop() async {
    active = false;
    return null;
  }

  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class NoInference implements InferenceWorker {
  @override
  Future<dynamic> call(
    String method, [
    Map<String, Object> args = const {},
  ]) async => false;
  @override
  Future<void> dispose() async {}
}

void main() {
  LocalListening listener(RecorderGate recorder) {
    final worker = NoInference();
    return LocalListening(
      LocalRecognizer(worker),
      LocalVad(worker),
      worker,
      recorder: recorder,
    );
  }

  test(
    'Pausing during microphone permission cannot start recording later',
    () async {
      final recorder = RecorderGate();
      final audio = listener(recorder);
      final starting = audio.start();
      final stopping = audio.stop();
      recorder.permission.complete(true);
      await Future.wait([starting, stopping]);
      expect(recorder.starts, 0);
      expect(recorder.active, isFalse);
      await audio.start();
      expect(recorder.active, isTrue);
      await audio.dispose();
      expect(recorder.active, isFalse);
    },
  );
  test(
    'A microphone stream opening after pause is stopped before subscribing',
    () async {
      final recorder = RecorderGate()..delayOpening = true;
      recorder.permission.complete(true);
      final audio = listener(recorder);
      final starting = audio.start();
      await Future<void>.delayed(Duration.zero);
      expect(recorder.starts, 1);
      final stopping = audio.stop();
      recorder.opening.complete();
      await Future.wait([starting, stopping]);
      expect(recorder.active, isFalse);
      await audio.dispose();
    },
  );
}
