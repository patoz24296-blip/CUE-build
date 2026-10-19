import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:cue/domain/evaluator.dart';
import 'package:cue/domain/models.dart';
import 'package:cue/domain/providers.dart';
import 'package:cue/domain/performance.dart';
import 'package:cue/domain/rehearsal_engine.dart';
import 'fakes.dart';

class DelayedMeaning implements LanguageModelProvider {
  final completion = Completer<SemanticJudgment?>();
  @override
  Future<SemanticJudgment?> judge({
    required String expected,
    required String spoken,
    required List<String> anchors,
    required AccuracyMode mode,
  }) => completion.future;
  @override
  Future<void> dispose() async {}
}

void main() {
  final line = ScriptEntry(
    id: 'a',
    type: EntryType.dialogue,
    character: 'MARA',
    text: 'I believe this undertaking is an extraordinary challenge.',
  );
  final first = Scene(id: 'first', heading: 'First scene', entries: [line]);
  final second = Scene(
    id: 'second',
    heading: 'Second scene',
    entries: [
      ScriptEntry(
        id: 'b',
        type: EntryType.dialogue,
        character: 'MARA',
        text: 'Wait for me.',
      ),
    ],
  );
  final production = Production(
    id: 'production',
    title: 'Play',
    createdAt: DateTime.now(),
    scenes: [first, second],
  );
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));
  test('A selected range uses its own scene direction', () async {
    final partner = ScriptEntry(
      id: 'partner',
      type: EntryType.dialogue,
      character: 'THEO',
      text: 'Wait for me.',
    );
    final later = Scene(
      id: 'later',
      heading: 'Later',
      entries: [partner, line],
    );
    final scene = combineScenes([first, later]);
    final tts = FakeTts();
    final engine = RehearsalEngine(
      production: production,
      scene: scene,
      start: 3,
      character: 'MARA',
      settings: const AppSettings(variableCues: false),
      sceneDirections: const {'first': 'fast', 'later': 'slow'},
      listener: FakeListening(),
      tts: tts,
      evaluator: LineEvaluator(),
    );
    await engine.begin();
    expect(tts.speeds.single, lessThan(1));
    engine.dispose();
  });
  test(
    'Unfinished rehearsals retain every requested hint without evaluating the line',
    () async {
      final engine = RehearsalEngine(
        production: production,
        scene: first,
        character: 'MARA',
        settings: const AppSettings(variableCues: false),
        listener: FakeListening(),
        tts: FakeTts(),
        evaluator: LineEvaluator(),
      );
      await engine.begin();
      await engine.requestHint();
      await engine.pause();
      final report = engine.report(completed: false);
      expect(report.hintCount, 1);
      expect(
        report.attempts.single.evaluation.classification,
        LineClassification.skippedLine,
      );
      expect(engine.attempts, isEmpty);
      engine.dispose();
    },
  );
  test('Repeated line drills count each hint request once', () async {
    final engine = RehearsalEngine(
      production: production,
      scene: first,
      character: 'MARA',
      practice: PracticeMode.lineDrill,
      drillIds: {line.id},
      settings: const AppSettings(variableCues: false),
      listener: FakeListening(),
      tts: FakeTts(),
      evaluator: LineEvaluator(),
    );
    await engine.begin();
    await engine.requestHint();
    await engine.submit('Wrong words');
    await engine.submit('Wrong words');
    await engine.submit(line.text);
    final report = engine.report();
    expect(report.hintCount, 3);
    expect(report.attempts.expand((a) => a.cueRequests).length, 3);
    engine.dispose();
  });
  test(
    'Pausing preserves hint levels and request timestamps for the current line',
    () async {
      final listener = FakeListening();
      final engine = RehearsalEngine(
        production: production,
        scene: first,
        character: 'MARA',
        settings: const AppSettings(variableCues: false),
        listener: listener,
        tts: FakeTts(),
        evaluator: LineEvaluator(),
      );
      await engine.begin();
      await engine.requestHint();
      await engine.pause();
      await engine.resume();
      await engine.requestHint();
      listener.say(line.text);
      await settle();
      expect(engine.attempts.single.cueRequests.map((c) => c.level), [1, 2]);
      engine.dispose();
    },
  );
  test(
    'Multi-scene run crosses boundaries without losing attempts or scene identities',
    () async {
      final listener = FakeListening();
      final engine = RehearsalEngine(
        production: production,
        scene: combineScenes([first, second]),
        sceneIds: ['first', 'second'],
        character: 'MARA',
        settings: const AppSettings(variableCues: false),
        listener: listener,
        tts: FakeTts(),
        evaluator: LineEvaluator(),
      );
      await engine.begin();
      expect(engine.sceneHeading, first.heading);
      listener.say(line.text);
      await settle();
      expect(engine.sceneHeading, second.heading);
      listener.say(second.dialogue.single.text);
      await settle();
      expect(engine.state, RehearsalState.finished);
      expect(engine.attempts, hasLength(2));
      expect(engine.report().sceneIds, ['first', 'second']);
      engine.dispose();
    },
  );
  test(
    'Configured distinct hint command works without dialogue substring triggers',
    () async {
      final listener = FakeListening();
      final engine = RehearsalEngine(
        production: production,
        scene: first,
        character: 'MARA',
        settings: const AppSettings(
          variableCues: false,
          hintCommand: 'Prompt me please',
        ),
        listener: listener,
        tts: FakeTts(),
        evaluator: LineEvaluator(),
      );
      await engine.begin();
      listener.say('They told me to prompt me please later.');
      await settle();
      expect(engine.hint, isEmpty);
      listener.say('Prompt me please');
      await settle();
      expect(engine.hint, isNotEmpty);
      engine.dispose();
    },
  );
  test(
    'Complete semantic paraphrases can advance without touching the screen',
    () async {
      final listener = FakeListening(), meaning = DelayedMeaning();
      final engine = RehearsalEngine(
        production: production,
        scene: first,
        character: 'MARA',
        settings: const AppSettings(
          variableCues: false,
          accuracy: AccuracyMode.improv,
        ),
        listener: listener,
        tts: FakeTts(),
        evaluator: LineEvaluator(languageModel: meaning),
      );
      await engine.begin();
      listener.say('This job seems incredibly difficult.');
      await settle();
      meaning.completion.complete(
        const SemanticJudgment(
          preserved: true,
          confidence: .9,
          reason: 'Meaning preserved',
        ),
      );
      await settle();
      expect(engine.state, RehearsalState.finished);
      expect(engine.attempts.single.evaluation.usedSemanticModel, isTrue);
      engine.dispose();
    },
  );
  test(
    'An in-flight meaning decision cannot cut off newly resumed speech',
    () async {
      final listener = FakeListening(), meaning = DelayedMeaning();
      final engine = RehearsalEngine(
        production: production,
        scene: first,
        character: 'MARA',
        settings: const AppSettings(
          variableCues: false,
          accuracy: AccuracyMode.improv,
        ),
        listener: listener,
        tts: FakeTts(),
        evaluator: LineEvaluator(languageModel: meaning),
      );
      await engine.begin();
      listener.say('This job seems incredibly difficult.');
      await settle();
      listener.say('This job seems incredibly difficult.', speaking: true);
      await settle();
      meaning.completion.complete(
        const SemanticJudgment(
          preserved: true,
          confidence: .9,
          reason: 'Meaning preserved',
        ),
      );
      await settle();
      expect(engine.state, RehearsalState.listening);
      expect(engine.attempts, isEmpty);
      engine.dispose();
    },
  );
  test('An empty custom drill cannot enter an infinite loop', () async {
    final engine = RehearsalEngine(
      production: production,
      scene: first,
      character: 'MARA',
      loop: true,
      practice: PracticeMode.lineDrill,
      settings: const AppSettings(),
      listener: FakeListening(),
      tts: FakeTts(),
      evaluator: LineEvaluator(),
    );
    await engine.begin();
    expect(engine.state, RehearsalState.error);
    engine.dispose();
  });
}
