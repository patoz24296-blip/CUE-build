import 'package:flutter_test/flutter_test.dart';
import 'package:cue/domain/evaluator.dart';
import 'package:cue/domain/models.dart';
import 'package:cue/domain/providers.dart';

ScriptEntry line(
  String text, {
  List<String> anchors = const [],
  List<String> variants = const [],
}) => ScriptEntry(
  id: 'line',
  type: EntryType.dialogue,
  character: 'MARA',
  text: text,
  protectedPhrases: anchors,
  variants: variants,
);

class AlwaysAccept implements LanguageModelProvider {
  int calls = 0;
  @override
  Future<SemanticJudgment?> judge({
    required String expected,
    required String spoken,
    required List<String> anchors,
    required AccuracyMode mode,
  }) async {
    calls++;
    return const SemanticJudgment(
      preserved: true,
      confidence: .95,
      reason: 'Meaning preserved.',
    );
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  final evaluator = LineEvaluator();
  for (final mode in AccuracyMode.values) {
    test('${mode.label} accepts identical negative lines', () async {
      for (final text in [
        'I will not go.',
        'I never loved her.',
        'I love you, but I hate the rain.',
      ]) {
        expect(
          (await evaluator.evaluate(
            line: line(text),
            spoken: text,
            mode: mode,
          )).accepted,
          isTrue,
        );
      }
    });
    for (final pair in [
      ['I never loved her.', 'I always loved her.'],
      ['Meet me at seven.', 'Meet me at eleven.'],
      ["Tell Gwendolen I'll come tomorrow.", "Tell Cecily I'll come tomorrow."],
      ['I do not know what you mean.', 'I know what you mean.'],
      ['Meet me at seven.', 'Meet me at seven or eleven.'],
      ['Bring the blue key.', 'Bring the red key.'],
    ]) {
      test('${mode.label} protects ${pair[0]}', () async {
        final result = await evaluator.evaluate(
          line: line(
            pair[0],
            anchors: pair[0].contains('blue') ? ['blue'] : [],
          ),
          spoken: pair[1],
          mode: mode,
          names: ['GWENDOLEN', 'CECILY'],
        );
        expect(result.accepted, isFalse);
      });
    }
  }
  test('Contraction equivalence is configurable in Word Perfect', () async {
    expect(
      (await evaluator.evaluate(
        line: line("I don't know."),
        spoken: 'I do not know',
        mode: AccuracyMode.wordPerfect,
      )).accepted,
      isTrue,
    );
    expect(
      (await evaluator.evaluate(
        line: line("I don't know."),
        spoken: 'I do not know',
        mode: AccuracyMode.wordPerfect,
        contractionsEquivalent: false,
      )).accepted,
      isFalse,
    );
  });
  test('Flexible and Loose allow harmless reordered grammar', () async {
    for (final mode in [AccuracyMode.flexible, AccuracyMode.loose]) {
      expect(
        (await evaluator.evaluate(
          line: line("I really don't think we should be doing this right now."),
          spoken: "I don't really think we should do this right now.",
          mode: mode,
        )).accepted,
        isTrue,
      );
    }
  });
  test(
    'Punctuation and case do not count; filler only allowed outside strict mode',
    () async {
      expect(
        (await evaluator.evaluate(
          line: line('Wait. Wait. Give me the key.'),
          spoken: 'WAIT WAIT give me the key',
          mode: AccuracyMode.wordPerfect,
        )).accepted,
        isTrue,
      );
      expect(
        (await evaluator.evaluate(
          line: line('Give me the key.'),
          spoken: 'Um give me the key',
          mode: AccuracyMode.flexible,
        )).accepted,
        isTrue,
      );
      expect(
        (await evaluator.evaluate(
          line: line('Give me the key.'),
          spoken: 'Um give me the key',
          mode: AccuracyMode.wordPerfect,
        )).accepted,
        isFalse,
      );
    },
  );
  test('Repeated words count in strict mode', () async {
    expect(
      (await evaluator.evaluate(
        line: line('Wait. Wait.'),
        spoken: 'Wait',
        mode: AccuracyMode.wordPerfect,
      )).accepted,
      isFalse,
    );
  });
  test('Word Perfect does not bypass policy for an accepted variant', () async {
    final entry = line('Give me the key.', variants: ['Hand me the key.']);
    expect(
      (await evaluator.evaluate(
        line: entry,
        spoken: 'Hand me the key',
        mode: AccuracyMode.wordPerfect,
      )).accepted,
      isFalse,
    );
    expect(
      (await evaluator.evaluate(
        line: entry,
        spoken: 'Hand me the key',
        mode: AccuracyMode.loose,
      )).accepted,
      isTrue,
    );
  });
  test('Protected information wins over a semantic model', () async {
    final model = AlwaysAccept();
    final semantic = LineEvaluator(languageModel: model);
    final result = await semantic.evaluate(
      line: line('Meet Gwendolen at seven.'),
      spoken: 'Meet Cecily at eleven.',
      mode: AccuracyMode.improv,
      names: ['Gwendolen', 'Cecily'],
    );
    expect(result.accepted, isFalse);
    expect(model.calls, 0);
  });
  test(
    'Broad paraphrases use local meaning inference or explicitly need review',
    () async {
      final entry = line('The room is freezing.');
      final fallback = await evaluator.evaluate(
        line: entry,
        spoken: 'It is bitterly cold in here.',
        mode: AccuracyMode.loose,
      );
      expect(fallback.accepted, isFalse);
      expect(fallback.semanticAccuracy, isNull);
      expect(fallback.reason, contains('review'));
      final result = await LineEvaluator(languageModel: AlwaysAccept())
          .evaluate(
            line: entry,
            spoken: 'It is bitterly cold in here.',
            mode: AccuracyMode.improv,
          );
      expect(result.accepted, isTrue);
      expect(result.usedSemanticModel, isTrue);
    },
  );
  test('Partial utterance cannot end an actor line', () {
    final entry = line(
      "I really don't think we should be doing this right now.",
    );
    expect(evaluator.hasEnoughContent(entry, "I really don't think"), isFalse);
    expect(evaluator.hasEnoughContent(entry, entry.text), isTrue);
    expect(evaluator.hasEnoughContent(line('But I—'), 'But I'), isTrue);
  });
  test(
    'Reordered subjects and shifted negation cannot preserve a line',
    () async {
      for (final pair in [
        ['I told you that you loved me.', 'You told me that I loved you.'],
        ['I did not tell her I loved you.', 'I did tell her I not loved you.'],
      ]) {
        final result = await evaluator.evaluate(
          line: line(pair[0]),
          spoken: pair[1],
          mode: AccuracyMode.loose,
        );
        expect(result.accepted, isFalse);
        expect(result.meaningChanged, isTrue);
      }
    },
  );
}
