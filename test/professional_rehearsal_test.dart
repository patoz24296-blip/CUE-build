import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:cue/domain/evaluator.dart';
import 'package:cue/domain/models.dart';
import 'package:cue/domain/providers.dart';
import 'package:cue/domain/rehearsal_engine.dart';
import 'fakes.dart';

class ReviewListening extends FakeListening implements RecognitionVerification {
  String? second;
  bool failVerification = false, delayReset = false;
  final resetGate = Completer<void>();
  @override
  Future<Transcript?> verifyUtterance() async {
    if (failVerification) throw StateError('Optional recognizer unavailable');
    return second == null ? null : Transcript(second!);
  }

  @override
  Future<void> reset() async {
    if (delayReset) await resetGate.future;
  }
}

class ReviewEvaluator extends LineEvaluator {
  bool delay = false;
  final gate = Completer<void>();
  @override
  Future<LineEvaluation> evaluate({
    required ScriptEntry line,
    required String spoken,
    required AccuracyMode mode,
    List<String> names = const [],
    bool contractionsEquivalent = true,
    double? asrConfidence,
  }) async {
    if (delay) await gate.future;
    return super.evaluate(
      line: line,
      spoken: spoken,
      mode: mode,
      names: names,
      contractionsEquivalent: contractionsEquivalent,
      asrConfidence: asrConfidence,
    );
  }
}

void main() {
  const line = ScriptEntry(
    id: 'a',
    type: EntryType.dialogue,
    character: 'MARA',
    text: 'Meet me at seven tomorrow.',
  );
  const next = ScriptEntry(
    id: 'b',
    type: EntryType.dialogue,
    character: 'MARA',
    text: 'Wait for me.',
  );
  const scene = Scene(id: 's', heading: 'Scene', entries: [line, next]);
  RehearsalEngine engine(
    ReviewListening listening, {
    LineEvaluator? evaluator,
    int start = 0,
  }) => RehearsalEngine(
    production: Production(
      id: 'p',
      title: 'Play',
      scenes: [scene],
      createdAt: DateTime.now(),
    ),
    scene: scene,
    character: 'MARA',
    start: start,
    settings: const AppSettings(variableCues: false),
    listener: listening,
    tts: FakeTts(),
    evaluator: evaluator ?? LineEvaluator(),
  );

  for (final failure in [false, true]) {
    test(
      'Unavailable second hearing requires review (failure=$failure)',
      () async {
        final listening = ReviewListening()..failVerification = failure;
        final run = engine(listening);
        await run.begin();
        await run.submit('Meet me at eleven tomorrow.');
        expect(run.attempts, isEmpty);
        expect(run.recognitionNotice, contains('Only one hearing'));
        expect(run.recognitionAlternative, isEmpty);
        expect(listening.active, isFalse);
        await run.submit(run.transcript);
        expect(run.attempts, isEmpty); // Finish cannot bypass a pending review.
        await run.useFirstHearing();
        expect(run.attempts.single.evaluation.accepted, isFalse);
        expect(run.current?.id, 'b');
        run.dispose();
      },
    );
  }

  for (final pause in [false, true]) {
    test(
      'Hearing review resists duplicate taps and pause (pause=$pause)',
      () async {
        final listening = ReviewListening()..second = line.text;
        final evaluator = ReviewEvaluator();
        final run = engine(listening, evaluator: evaluator);
        await run.begin();
        await run.submit('Meet me at eleven tomorrow.');
        evaluator.delay = true;
        final firstTap = run.useSecondHearing();
        final duplicateTap = run.useFirstHearing();
        expect(run.reviewingHearing, isTrue);
        if (pause) await run.pause();
        evaluator.gate.complete();
        await Future.wait([firstTap, duplicateTap]);
        expect(run.reviewingHearing, isFalse);
        if (pause) {
          expect(run.attempts, isEmpty);
          expect(run.state, RehearsalState.paused);
          expect(listening.active, isFalse);
        } else {
          expect(run.attempts, hasLength(1));
          expect(run.attempts.single.transcript, line.text);
          expect(run.current?.id, 'b');
        }
        run.dispose();
      },
    );
  }

  test('Retry cancelled by pause cannot restart the microphone', () async {
    final listening = ReviewListening();
    final run = engine(listening);
    await run.begin();
    listening.delayReset = true;
    final retry = run.retryHearing();
    await Future<void>.delayed(Duration.zero);
    await run.pause();
    listening.resetGate.complete();
    await retry;
    expect(run.state, RehearsalState.paused);
    expect(listening.active, isFalse);
    expect(run.attempts, isEmpty);
    run.dispose();
  });

  test(
    'Preparation completed in background waits for explicit resume',
    () async {
      final listening = ReviewListening();
      final run = engine(listening, start: 1);
      await run.begin(paused: true);
      expect(run.state, RehearsalState.paused);
      expect(listening.active, isFalse);
      await run.resume();
      expect(run.current?.id, 'b');
      expect(run.actorLineNumber, 1);
      expect(run.actorLineCount, 1);
      expect(listening.active, isTrue);
      run.dispose();
    },
  );

  test('Retry clears the hearing without creating an attempt', () async {
    final listening = ReviewListening();
    final run = engine(listening);
    await run.begin();
    await run.submit('Meet me at eleven tomorrow.');
    await run.retryHearing();
    expect(run.attempts, isEmpty);
    expect(run.transcript, isEmpty);
    expect(run.recognitionNotice, isEmpty);
    expect(listening.active, isTrue);
    await run.submit(line.text);
    expect(run.attempts.single.evaluation.accepted, isTrue);
    run.dispose();
  });
}
