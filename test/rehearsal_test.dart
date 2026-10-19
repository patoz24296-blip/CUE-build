import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:cue/domain/evaluator.dart';
import 'package:cue/domain/models.dart';
import 'package:cue/domain/rehearsal_engine.dart';
import 'package:cue/domain/providers.dart';
import 'fakes.dart';

void main() {
  final cue = ScriptEntry(
    id: 'cue',
    type: EntryType.dialogue,
    character: 'JACK',
    text: 'Where are you going?',
  );
  final reply = ScriptEntry(
    id: 'reply',
    type: EntryType.dialogue,
    character: 'MARA',
    text: 'Meet me at seven tomorrow.',
  );
  final scene = Scene(id: 'scene', heading: 'Scene 1', entries: [cue, reply]);
  final production = Production(
    id: 'production',
    title: 'Test',
    scenes: [scene],
    createdAt: DateTime.now(),
  );
  test('Dramatic pause never advances an unfinished line', () {
    const policy = CompletionPolicy();
    final evaluator = LineEvaluator();
    expect(
      policy.complete(
        reply,
        const SpeechEvent(
          text: 'Meet me',
          speaking: false,
          silence: Duration(seconds: 20),
        ),
        ResponseTiming.fast,
        evaluator,
      ),
      isFalse,
    );
    expect(
      policy.complete(
        reply,
        SpeechEvent(
          text: reply.text,
          speaking: true,
          silence: const Duration(seconds: 20),
        ),
        ResponseTiming.fast,
        evaluator,
      ),
      isFalse,
    );
    expect(
      policy.complete(
        reply,
        SpeechEvent(
          text: reply.text,
          speaking: false,
          silence: const Duration(milliseconds: 800),
        ),
        ResponseTiming.patient,
        evaluator,
      ),
      isFalse,
    );
  });
  test(
    'Partner -> listen -> evaluate -> results progresses hands free',
    () async {
      final listener = FakeListening(), tts = FakeTts();
      final engine = RehearsalEngine(
        production: production,
        scene: scene,
        character: 'MARA',
        settings: const AppSettings(variableCues: false),
        listener: listener,
        tts: tts,
        evaluator: LineEvaluator(),
      );
      await engine.begin();
      expect(tts.spoken, [cue.text]);
      expect(listener.active, isTrue);
      listener.say('Meet me');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(engine.state, RehearsalState.listening);
      listener.say(reply.text);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(engine.state, RehearsalState.finished);
      expect(engine.attempts.single.evaluation.accepted, isTrue);
      engine.dispose();
    },
  );
  test(
    'Progressive hints store actual level and timestamp, not reconstructed counts',
    () async {
      final engine = RehearsalEngine(
        production: production,
        scene: scene,
        character: 'MARA',
        settings: const AppSettings(variableCues: false),
        listener: FakeListening(),
        tts: FakeTts(),
        evaluator: LineEvaluator(),
      );
      await engine.begin();
      await engine.requestHint();
      expect(engine.hint, 'Meet me at');
      await engine.requestHint(full: true);
      expect(engine.hint, reply.text);
      await engine.submit(reply.text);
      expect(engine.attempts.single.cueRequests.map((e) => e.level), [1, 3]);
      expect(
        engine.attempts.single.cueRequests.every(
          (e) => e.at.isBefore(DateTime.now()),
        ),
        isTrue,
      );
      engine.dispose();
    },
  );
  test('Pause during playback cannot start microphone afterward', () async {
    final listener = FakeListening(),
        tts = FakeTts()..blocked = Completer<void>();
    final engine = RehearsalEngine(
      production: production,
      scene: scene,
      character: 'MARA',
      settings: const AppSettings(variableCues: false),
      listener: listener,
      tts: tts,
      evaluator: LineEvaluator(),
    );
    final begin = engine.begin();
    await Future<void>.delayed(Duration.zero);
    await engine.pause();
    await begin;
    expect(engine.state, RehearsalState.paused);
    expect(listener.active, isFalse);
    engine.dispose();
  });
  test('Voice failure is recoverable', () async {
    final tts = FakeTts()..fail = true;
    final engine = RehearsalEngine(
      production: production,
      scene: scene,
      character: 'MARA',
      settings: const AppSettings(variableCues: false),
      listener: FakeListening(),
      tts: tts,
      evaluator: LineEvaluator(),
    );
    await engine.begin();
    expect(engine.state, RehearsalState.error);
    tts.fail = false;
    await engine.resume();
    expect(engine.state, RehearsalState.listening);
    engine.dispose();
  });
  test('Cue reduction and progressive hint boundaries', () {
    expect(
      reduceCue('Listen. Go now, before dawn.', CueReduction.sentence),
      'Go now, before dawn.',
    );
    expect(
      reduceCue('Listen. Go now, before dawn.', CueReduction.phrase),
      'before dawn.',
    );
    expect(progressiveHint('Wait.', 1), 'Wait.');
  });
  test(
    'Overlap only stops playback for actor evidence, never partner echo',
    () async {
      final listener = FakeListening(),
          tts = FakeTts()..blocked = Completer<void>();
      final engine = RehearsalEngine(
        production: production,
        scene: scene,
        character: 'MARA',
        settings: const AppSettings(variableCues: false, interruptions: true),
        listener: listener,
        tts: tts,
        evaluator: LineEvaluator(),
      );
      final beginning = engine.begin();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      listener.say(cue.text);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(tts.blocked!.isCompleted, isFalse);
      listener.say(reply.text);
      await beginning;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(tts.blocked!.isCompleted, isTrue);
      expect(engine.state, RehearsalState.finished);
      expect(engine.attempts.single.transcript, reply.text);
      engine.dispose();
    },
  );
}
