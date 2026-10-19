import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cue/domain/models.dart';
import 'package:cue/domain/providers.dart';
import 'package:cue/domain/evaluator.dart';
import 'package:cue/domain/script_parser.dart';
import 'package:cue/domain/rehearsal_engine.dart';
import 'package:cue/domain/voice_catalog.dart';
import 'package:cue/ui/script_follow_view.dart';
import 'fakes.dart';

class DoubleListening extends FakeListening implements RecognitionVerification {
  String second = 'Meet me at seven tomorrow.';
  int checks = 0;
  @override
  Future<Transcript?> verifyUtterance() async {
    checks++;
    return Transcript(second);
  }
}

void main() {
  test('Repeated script words are highlighted only as many times as heard', () {
    expect(heardWordPositions('Wait wait wait.', 'wait'), {0});
    expect(heardWordPositions("I don't think I can.", 'I do not think'), {
      0,
      1,
      2,
    });
  });
  test('Indented PDF text is retained before any metadata', () {
    final p = ScriptParser().parse(
      '    MARA\n    Wait for me.\n\n    LEO\n    I will.',
      filename: 'scene.pdf',
    );
    expect(p.characters.toSet(), {'MARA', 'LEO'});
    expect(p.lineCount, 2);
  });
  test('Mixed-case play labels and adjacent repeated cue names parse', () {
    final p = ScriptParser().parse(
      'Scene One\nJohn: Stay here.\nMary: Why?\nJohn: Because I need you.\nMary: All right.',
      filename: 'play.txt',
    );
    expect(p.characters.toSet(), {'John', 'Mary'});
    expect(p.scenes.single.dialogue.map((e) => e.text), [
      'Stay here.',
      'Why?',
      'Because I need you.',
      'All right.',
    ]);
    final adjacent = ScriptParser().parse(
      'John\nStay here.\nMary\nWhy?\nJohn\nI need you.\nMary\nAll right.',
      filename: 'play.txt',
    );
    expect(adjacent.lineCount, 4);
  });
  test(
    'Natural turn timing is quick after a complete ending, and waits mid-line',
    () {
      const line = ScriptEntry(
        id: 'a',
        type: EntryType.dialogue,
        character: 'MARA',
        text: 'Meet me at seven tomorrow.',
      );
      const policy = CompletionPolicy();
      final evaluator = LineEvaluator();
      expect(
        policy.complete(
          line,
          const SpeechEvent(
            text: 'Meet me at seven tomorrow.',
            speaking: false,
            silence: Duration(milliseconds: 600),
          ),
          ResponseTiming.natural,
          evaluator,
        ),
        isTrue,
      );
      expect(
        policy.complete(
          line,
          const SpeechEvent(
            text: 'Meet me at seven',
            speaking: false,
            silence: Duration(seconds: 20),
          ),
          ResponseTiming.natural,
          evaluator,
        ),
        isFalse,
      );
    },
  );
  test(
    'Language selects a real named voice and migrates legacy voice numbers',
    () {
      expect(resolveVoice(900, 'MARA', 0).speaker, greaterThanOrEqualTo(1000));
      expect(resolveVoice(1003, 'MARA', 0).id, 3);
      expect(suggestedVoice('THEO', 1).description, contains('male'));
      expect(suggestedVoice('THEO', 1).description, isNot(contains('female')));
      expect(resolveVoice(1003, 'MARA', 0, language: 'es').language, 'es');
      expect(
        const AppSettings(language: 'es').effectiveSpeechModel,
        'whisper-base-multilingual',
      );
      expect(
        const AppSettings(language: 'es').verificationSpeechModel,
        'whisper-multilingual',
      );
      expect(
        const AppSettings(
          language: 'es',
          speechModel: 'whisper-multilingual',
        ).verificationSpeechModel,
        'whisper-base-multilingual',
      );
      expect(
        const AppSettings(language: 'fr').verificationSpeechModel,
        'whisper-multilingual',
      );
    },
  );
  for (final mode in AccuracyMode.values) {
    test(
      'A mid-line pause cannot advance through $mode verification',
      () async {
        const line = ScriptEntry(
          id: 'a',
          type: EntryType.dialogue,
          character: 'MARA',
          text: 'Meet me at seven tomorrow.',
        );
        const scene = Scene(id: 's', heading: 'Scene', entries: [line]);
        final listener = DoubleListening();
        final engine = RehearsalEngine(
          production: Production(
            id: 'p',
            title: 'Play',
            scenes: [scene],
            createdAt: DateTime.now(),
          ),
          scene: scene,
          character: 'MARA',
          settings: AppSettings(accuracy: mode, variableCues: false),
          listener: listener,
          tts: FakeTts(),
          evaluator: LineEvaluator(),
        );
        await engine.begin();
        listener.say('Meet me at seven', silence: 20000);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(engine.state, RehearsalState.listening);
        expect(engine.transcript, 'Meet me at seven');
        expect(engine.attempts, isEmpty);
        expect(listener.checks, 0);
        listener.say(line.text);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(engine.attempts.single.evaluation.accepted, isTrue);
        expect(engine.state, RehearsalState.finished);
        engine.dispose();
      },
    );
  }
  test(
    'Disagreeing recognizers do not automatically penalize or rewrite the actor',
    () async {
      const line = ScriptEntry(
        id: 'a',
        type: EntryType.dialogue,
        character: 'MARA',
        text: 'Meet me at seven tomorrow.',
      );
      const scene = Scene(id: 's', heading: 'Scene', entries: [line]);
      final listener = DoubleListening();
      final engine = RehearsalEngine(
        production: Production(
          id: 'p',
          title: 'Play',
          scenes: [scene],
          createdAt: DateTime.now(),
        ),
        scene: scene,
        character: 'MARA',
        settings: const AppSettings(variableCues: false),
        listener: listener,
        tts: FakeTts(),
        evaluator: LineEvaluator(),
      );
      await engine.begin();
      listener.say('Meet me at eleven tomorrow.');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(engine.attempts, isEmpty);
      expect(engine.recognitionNotice, isNotEmpty);
      expect(engine.recognitionAlternative, line.text);
      expect(listener.active, isFalse);
      listener.say('A later accidental microphone phrase.');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(engine.transcript, 'Meet me at eleven tomorrow.');
      await engine.useSecondHearing();
      expect(engine.attempts.single.transcript, line.text);
      expect(engine.attempts.single.evaluation.accepted, isTrue);
      engine.dispose();
    },
  );
  testWidgets(
    'Visible script follows and highlights the current line on a phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scene = Scene(
        id: 's',
        heading: 'Scene',
        entries: List.generate(
          25,
          (i) => ScriptEntry(
            id: '$i',
            type: EntryType.dialogue,
            character: i.isEven ? 'MARA' : 'LEO',
            text: 'This is dialogue number $i.',
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptFollowView(
              scene: scene,
              activeId: '0',
              character: 'MARA',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptFollowView(
              scene: scene,
              activeId: '24',
              character: 'MARA',
              transcript: 'This is dialogue',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.textContaining('This is dialogue number 24.')).top,
        inInclusiveRange(0, 720),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
