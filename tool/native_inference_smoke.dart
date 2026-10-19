import 'dart:math';
import 'dart:io';
import 'package:cue/services/semantic.dart';
import 'package:cue/domain/models.dart';
import 'package:cue/domain/evaluator.dart';

Future<void> main(List<String> args) async {
  final library = args[0], root = args[1];
  final meaning = await BuiltinMeaning.open(
    '$root/meaning/qwen2.5-0.5b-instruct-q4_k_m.gguf',
    libraryPath: library,
  );
  final embeddings = await BuiltinEmbeddings.open(
    '$root/embeddings/nomic-embed-text-v1.5.Q4_K_M.gguf',
    libraryPath: library,
  );
  try {
    final judgment = await meaning.judge(
      expected: 'Meet me at seven tomorrow.',
      spoken: 'Meet me at seven tomorrow.',
      anchors: ['7'],
      mode: AccuracyMode.loose,
    );
    if (judgment == null || !judgment.preserved) {
      throw StateError(
        'Real meaning model failed identical-line smoke test: ${judgment?.reason}',
      );
    }
    final same = await embeddings.embed('Meet me at seven tomorrow.');
    final paraphrase = await embeddings.embed(
      'We should meet tomorrow at seven.',
    );
    final unrelated = await embeddings.embed(
      'A bicycle wheel needs repairing.',
    );
    double cosine(List<double> b) {
      var dot = 0.0, aa = 0.0, bb = 0.0;
      for (var i = 0; i < same.length; i++) {
        dot += same[i] * b[i];
        aa += same[i] * same[i];
        bb += b[i] * b[i];
      }
      return dot / sqrt(aa * bb);
    }

    if (same.length != 768 ||
        same.any((x) => !x.isFinite) ||
        cosine(paraphrase) <= cosine(unrelated)) {
      throw StateError('Real embedding comparison smoke test failed');
    }
    final protected =
        await LineEvaluator(
          languageModel: meaning,
          embeddings: embeddings,
        ).evaluate(
          line: const ScriptEntry(
            id: 'test',
            type: EntryType.dialogue,
            character: 'A',
            text: 'Meet me at seven tomorrow.',
          ),
          spoken: 'Meet me at eleven tomorrow.',
          mode: AccuracyMode.improv,
        );
    if (protected.accepted) {
      throw StateError('Protected number bypassed by native inference');
    }
    stdout.writeln(
      'Real Qwen judgment, 768-dimensional Nomic embeddings and protected-information checks passed.',
    );
  } finally {
    await meaning.dispose();
    await embeddings.dispose();
  }
}
