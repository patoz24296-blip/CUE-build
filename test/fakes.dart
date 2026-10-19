import 'dart:async';
import 'package:cue/domain/providers.dart';

class FakeListening implements ListeningProvider {
  final controller = StreamController<SpeechEvent>.broadcast();
  bool active = false;
  @override
  Stream<SpeechEvent> get events => controller.stream;
  @override
  Future<void> start() async {
    active = true;
  }

  @override
  Future<void> stop() async {
    active = false;
  }

  @override
  Future<void> reset() async {}
  @override
  Future<void> dispose() async {
    active = false;
    await controller.close();
  }

  void say(String text, {bool speaking = false, int silence = 4000}) =>
      controller.add(
        SpeechEvent(
          text: text,
          speaking: speaking,
          silence: Duration(milliseconds: silence),
          startedAt: DateTime.now(),
        ),
      );
}

class FakeTts implements TextToSpeechProvider {
  final spoken = <String>[];
  final speeds = <double>[];
  bool fail = false;
  Completer<void>? blocked;
  @override
  Future<void> speak(
    String text, {
    int voice = 0,
    double speed = 1,
    double volume = 1,
  }) async {
    if (fail) throw StateError('Voice engine unavailable');
    spoken.add(text);
    speeds.add(speed);
    await blocked?.future;
  }

  @override
  Future<void> stop() async {
    if (blocked != null && !blocked!.isCompleted) blocked!.complete();
  }

  @override
  Future<void> preload(String text, {int voice = 0, double speed = 1}) async {}
  @override
  Future<void> dispose() async {
    await stop();
  }
}
