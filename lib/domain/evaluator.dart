import 'dart:math';
import 'models.dart';
import 'providers.dart';

class TextNormalizer {
  static const contractions = {
    "don't": 'do not',
    "doesn't": 'does not',
    "didn't": 'did not',
    "can't": 'cannot',
    "won't": 'will not',
    "isn't": 'is not',
    "aren't": 'are not',
    "wasn't": 'was not',
    "weren't": 'were not',
    "haven't": 'have not',
    "hasn't": 'has not',
    "hadn't": 'had not',
    "shouldn't": 'should not',
    "wouldn't": 'would not',
    "couldn't": 'could not',
    "i'm": 'i am',
    "i'll": 'i will',
    "i've": 'i have',
    "i'd": 'i would',
    "you're": 'you are',
    "you'll": 'you will',
    "you've": 'you have',
    "we're": 'we are',
    "we'll": 'we will',
    "we've": 'we have',
    "they're": 'they are',
    "they'll": 'they will',
    "it's": 'it is',
    "that's": 'that is',
    "what's": 'what is',
    "there's": 'there is',
    "let's": 'let us',
  };
  static const numbers = {
    'zero': '0',
    'one': '1',
    'two': '2',
    'three': '3',
    'four': '4',
    'five': '5',
    'six': '6',
    'seven': '7',
    'eight': '8',
    'nine': '9',
    'ten': '10',
    'eleven': '11',
    'twelve': '12',
    'thirteen': '13',
    'fourteen': '14',
    'fifteen': '15',
    'sixteen': '16',
    'seventeen': '17',
    'eighteen': '18',
    'nineteen': '19',
    'twenty': '20',
    'thirty': '30',
    'forty': '40',
    'fifty': '50',
    'sixty': '60',
    'seventy': '70',
    'eighty': '80',
    'ninety': '90',
    'hundred': '100',
    'thousand': '1000',
  };
  List<String> tokens(
    String text, {
    bool contractions = true,
    bool fillers = false,
  }) {
    var s = text.toLowerCase().replaceAll(RegExp('[’‘]'), "'");
    if (contractions) {
      for (final pair in TextNormalizer.contractions.entries) {
        s = s.replaceAll(
          RegExp('\\b${RegExp.escape(pair.key)}\\b'),
          pair.value,
        );
      }
      s = s.replaceAll(RegExp(r'\bcan not\b'), 'cannot');
    }
    final tokens = RegExp(
      r"[\p{L}\p{N}]+(?:'[\p{L}]+)?",
      unicode: true,
    ).allMatches(s).map((m) => m.group(0)!).toList();
    return tokens
        .where((t) => !fillers || !{'um', 'uh', 'erm', 'hmm'}.contains(t))
        .map((t) => numbers[t] ?? t)
        .toList();
  }
}

class TokenDiff {
  const TokenDiff(this.missing, this.inserted, this.matches);
  final List<String> missing, inserted;
  final int matches;
}

class LineEvaluator {
  LineEvaluator({this.languageModel, this.embeddings});
  final LanguageModelProvider? languageModel;
  final EmbeddingProvider? embeddings;
  final normalizer = TextNormalizer();
  static const _negations = {
    'not',
    'never',
    'no',
    'cannot',
    'nothing',
    'nobody',
    'neither',
    'without',
  };
  static const _opposites = [
    ['always', 'never'],
    ['love', 'hate'],
    ['loved', 'hated'],
    ['stay', 'leave'],
    ['alive', 'dead'],
    ['before', 'after'],
    ['tomorrow', 'yesterday'],
    ['yes', 'no'],
    ['guilty', 'innocent'],
    ['accept', 'refuse'],
  ];

  TokenDiff diff(List<String> expected, List<String> actual) {
    final grid = List.generate(
      expected.length + 1,
      (_) => List.filled(actual.length + 1, 0),
    );
    for (var i = expected.length - 1; i >= 0; i--) {
      for (var j = actual.length - 1; j >= 0; j--) {
        grid[i][j] = expected[i] == actual[j]
            ? 1 + grid[i + 1][j + 1]
            : max(grid[i + 1][j], grid[i][j + 1]);
      }
    }
    final missing = <String>[], inserted = <String>[];
    var i = 0, j = 0, matches = 0;
    while (i < expected.length || j < actual.length) {
      if (i < expected.length &&
          j < actual.length &&
          expected[i] == actual[j]) {
        matches++;
        i++;
        j++;
      } else if (i < expected.length &&
          (j == actual.length || grid[i + 1][j] >= grid[i][j + 1])) {
        missing.add(expected[i++]);
      } else {
        inserted.add(actual[j++]);
      }
    }
    return TokenDiff(missing, inserted, matches);
  }

  double editSimilarity(List<String> a, List<String> b) {
    if (a.isEmpty && b.isEmpty) {
      return 1;
    }
    var prev = List.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final row = List.filled(b.length + 1, 0);
      row[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        row[j + 1] = min(
          min(row[j] + 1, prev[j + 1] + 1),
          prev[j] + (a[i] == b[j] ? 0 : 1),
        );
      }
      prev = row;
    }
    return 1 - prev.last / max(a.length, b.length);
  }

  double bagSimilarity(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) {
      return a.isEmpty && b.isEmpty ? 1 : 0;
    }
    final counts = <String, int>{};
    for (final t in b) {
      counts.update(t, (v) => v + 1, ifAbsent: () => 1);
    }
    var matches = 0;
    for (final t in a) {
      if ((counts[t] ?? 0) > 0) {
        matches++;
        counts[t] = counts[t]! - 1;
      }
    }
    return 2 * matches / (a.length + b.length);
  }

  List<String> anchors(ScriptEntry line, List<String> names) {
    final tokens = normalizer.tokens(line.text);
    final phrases = <String>{...line.protectedPhrases};
    for (final t in tokens) {
      if (RegExp(r'^\d+$').hasMatch(t)) {
        phrases.add(t);
      }
    }
    for (final name in names) {
      final n = normalizer.tokens(name);
      if (_contains(tokens, n)) {
        phrases.add(name);
      }
    }
    // Proper nouns inside a sentence. First-word capitalization is not an entity.
    final proper = RegExp(r'(?<=[\p{L}\p{N},;:]\s)[A-Z][a-z]+', unicode: true);
    for (final match in proper.allMatches(line.text)) {
      phrases.add(match.group(0)!);
    }
    return phrases.toList();
  }

  bool _contains(List<String> tokens, List<String> phrase) {
    if (phrase.isEmpty) {
      return false;
    }
    for (var i = 0; i <= tokens.length - phrase.length; i++) {
      if (List.generate(
        phrase.length,
        (j) => tokens[i + j] == phrase[j],
      ).every((v) => v)) {
        return true;
      }
    }
    return false;
  }

  Future<LineEvaluation> evaluate({
    required ScriptEntry line,
    required String spoken,
    required AccuracyMode mode,
    List<String> names = const [],
    bool contractionsEquivalent = true,
    double? asrConfidence,
  }) async {
    final exactExpected = normalizer.tokens(
      line.text,
      contractions: contractionsEquivalent,
    );
    final exactActual = normalizer.tokens(
      spoken,
      contractions: contractionsEquivalent,
    );
    final expected = normalizer.tokens(
      line.text,
      fillers: mode != AccuracyMode.wordPerfect,
    );
    final actual = normalizer.tokens(
      spoken,
      fillers: mode != AccuracyMode.wordPerfect,
    );
    final changes = diff(exactExpected, exactActual);
    final textual = editSimilarity(exactExpected, exactActual);
    final bag = bagSimilarity(expected, actual);
    final protected = anchors(line, names);
    final violations = protected
        .where((p) => !_contains(actual, normalizer.tokens(p)))
        .toList();
    final expectedNeg = expected.where(_negations.contains).toList();
    final actualNeg = actual.where(_negations.contains).toList();
    var reversal = bagSimilarity(expectedNeg, actualNeg) < 1;
    String? predicate(List<String> words, int index) => words
        .skip(index + 1)
        .where(
          (w) => !{
            'really',
            'just',
            'quite',
            'ever',
            'do',
            'did',
            'does',
            'be',
            'been',
            'have',
            'has',
            'had',
          }.contains(w),
        )
        .firstOrNull;
    for (var i = 0; i < expected.length; i++) {
      if (!_negations.contains(expected[i])) continue;
      final ePredicate = predicate(expected, i);
      final aIndex = actual.indexOf(expected[i]);
      final aPredicate = aIndex < 0 ? null : predicate(actual, aIndex);
      // Detect moved polarity within the same vocabulary, without treating
      // every synonymous negated predicate as a reversal.
      if (ePredicate != null &&
          aPredicate != null &&
          ePredicate != aPredicate &&
          expected.contains(aPredicate) &&
          actual.contains(ePredicate)) {
        reversal = true;
      }
    }
    final eSubject = expected
        .where((w) => {'i', 'we', 'you', 'he', 'she', 'they'}.contains(w))
        .firstOrNull;
    final aSubject = actual
        .where((w) => {'i', 'we', 'you', 'he', 'she', 'they'}.contains(w))
        .firstOrNull;
    if (eSubject != null &&
        aSubject != null &&
        eSubject != aSubject &&
        expected.contains(aSubject) &&
        actual.contains(eSubject)) {
      reversal = true;
    }
    for (final pair in _opposites) {
      final e0 = _contains(expected, normalizer.tokens(pair[0]));
      final e1 = _contains(expected, normalizer.tokens(pair[1]));
      final a0 = _contains(actual, normalizer.tokens(pair[0]));
      final a1 = _contains(actual, normalizer.tokens(pair[1]));
      if (e0 != a0 && e1 != a1 && (e0 || e1)) {
        reversal = true;
      }
    }
    // Changed/invented numbers are unsafe, even if the expected number survives.
    final eNums = expected.where((t) => RegExp(r'^\d+$').hasMatch(t)).toList();
    final aNums = actual.where((t) => RegExp(r'^\d+$').hasMatch(t)).toList();
    if (bagSimilarity(eNums, aNums) < 1) {
      violations.add('Numeric information');
    }
    LineEvaluation result(
      bool accepted,
      LineClassification classification,
      String reason, {
      double? semantic,
      double confidence = .9,
      bool model = false,
    }) => LineEvaluation(
      accepted: accepted,
      textualAccuracy: textual,
      semanticAccuracy: semantic,
      classification: classification,
      confidence: min(confidence, asrConfidence ?? 1),
      missingWords: changes.missing,
      insertedWords: changes.inserted,
      changedWords: List.generate(
        min(changes.missing.length, changes.inserted.length),
        (i) => '${changes.missing[i]} → ${changes.inserted[i]}',
      ),
      protectedWordViolations: violations.toSet().toList(),
      meaningChanged: reversal,
      reason: reason,
      usedSemanticModel: model,
    );
    if (actual.isEmpty) {
      return result(
        false,
        LineClassification.skippedLine,
        'No line was heard.',
        confidence: 1,
      );
    }
    if (reversal) {
      return result(
        false,
        LineClassification.significantDeviation,
        'Negation or opposing information changed.',
      );
    }
    if (violations.isNotEmpty) {
      return result(
        false,
        LineClassification.significantDeviation,
        'Protected information was missing or changed.',
      );
    }
    if (line.flaggedVariants.contains(actual.join(' '))) {
      return result(
        false,
        LineClassification.significantDeviation,
        'Wording you chose to keep flagging.',
      );
    }
    if (textual == 1) {
      return result(true, LineClassification.wordPerfect, 'Word for word.');
    }
    if (mode == AccuracyMode.wordPerfect) {
      return result(
        false,
        LineClassification.significantDeviation,
        'The wording differed from the script.',
      );
    }
    for (final variant in line.variants) {
      if (normalizer.tokens(variant).join(' ') == actual.join(' ')) {
        return result(
          true,
          LineClassification.acceptableVariation,
          'An accepted rehearsal variation.',
        );
      }
    }
    // Compare a conservative grammar-normalized form, not a lower acceptance
    // threshold. Auxiliary omissions and inflection changes preserve content.
    List<String> grammar(List<String> words) => words
        .where(
          (w) => !{'be', 'been', 'being', 'um', 'uh', 'erm', 'hmm'}.contains(w),
        )
        .map(
          (w) =>
              const {
                'doing': 'do',
                'going': 'go',
                'coming': 'come',
                'really': 'really',
              }[w] ??
              w,
        )
        .toList();
    final grammarBag = bagSimilarity(grammar(expected), grammar(actual));
    final flexible =
        textual >= .84 ||
        ((bag >= .88 || grammarBag >= .94) &&
            changes.missing.length <= max(4, (expected.length * .3).round()));
    if (flexible) {
      return result(
        true,
        LineClassification.acceptableVariation,
        'A small wording variation.',
      );
    }
    if (mode == AccuracyMode.flexible) {
      return result(
        false,
        bag < .25
            ? LineClassification.wrongLine
            : LineClassification.significantDeviation,
        'The wording changed substantially.',
      );
    }
    // Larger paraphrases need a semantic decision, not a lowered lexical threshold.
    if (embeddings != null) {
      try {
        final a = await embeddings!.embed(line.text),
            b = await embeddings!.embed(spoken);
        if (a.length == b.length && a.isNotEmpty) {
          var dot = 0.0, aa = 0.0, bb = 0.0;
          for (var i = 0; i < a.length; i++) {
            dot += a[i] * b[i];
            aa += a[i] * a[i];
            bb += b[i] * b[i];
          }
          final cosine = aa > 0 && bb > 0 ? dot / sqrt(aa * bb) : 0.0;
          if (cosine < .25) {
            return result(
              false,
              LineClassification.wrongLine,
              'This response appears unrelated to the expected line.',
              confidence: .7,
            );
          }
        }
      } catch (_) {
        /* A missing optional model cannot disable rehearsal. */
      }
    }
    SemanticJudgment? judgment;
    try {
      judgment = await languageModel?.judge(
        expected: line.text,
        spoken: spoken,
        anchors: protected,
        mode: mode,
      );
    } catch (_) {
      judgment = null;
    }
    if (judgment != null && judgment.confidence >= .65) {
      return result(
        judgment.preserved,
        judgment.preserved
            ? LineClassification.meaningPreserved
            : LineClassification.significantDeviation,
        judgment.reason,
        semantic: judgment.preserved
            ? judgment.confidence
            : 1 - judgment.confidence,
        confidence: judgment.confidence,
        model: true,
      );
    }
    return result(
      false,
      bag < .25
          ? LineClassification.wrongLine
          : LineClassification.significantDeviation,
      'This paraphrase needs review. Install the optional meaning model for broader ${mode.label.toLowerCase()} matching.',
      confidence: .55,
    );
  }

  bool hasEnoughContent(ScriptEntry line, String spoken) {
    final e = normalizer.tokens(line.text),
        a = normalizer.tokens(spoken, fillers: true);
    if (a.isEmpty) {
      return false;
    }
    if (e.length <= 3) {
      return a.length >= e.length && bagSimilarity(e, a) >= .45;
    }
    final d = diff(e, a);
    final cueEnd = e.skip(max(0, e.length - 3)).toList();
    return (d.matches / e.length >= .8 && _contains(a, cueEnd)) ||
        (a.length >= e.length * .8 && bagSimilarity(e, a) >= .4) ||
        (line.isInterrupted &&
            a.length >= max(1, e.length - 1) &&
            bagSimilarity(e, a) >= .65);
  }
}
