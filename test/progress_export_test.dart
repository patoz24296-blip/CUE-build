import 'package:flutter_test/flutter_test.dart';
import 'package:cue/domain/models.dart';
import 'package:cue/domain/progress.dart';
import 'package:cue/services/export_service.dart';

void main() {
  final a = ScriptEntry(
    id: 'a',
    type: EntryType.dialogue,
    character: 'MARA',
    text: '=HYPERLINK("remote")',
  );
  final b = ScriptEntry(
    id: 'b',
    type: EntryType.dialogue,
    character: 'MARA',
    text: 'Wait, please.',
  );
  final production = Production(
    id: 'production',
    title: 'Scene',
    scenes: [
      Scene(id: 's', heading: 'Scene', entries: [a, b]),
    ],
    createdAt: DateTime(2026),
    selectedCharacter: 'MARA',
  );
  LineAttempt attempt(
    ScriptEntry line, {
    bool accepted = true,
    int hints = 0,
    int day = 1,
  }) => LineAttempt(
    id: newId(),
    line: line,
    transcript: line.text,
    evaluation: LineEvaluation(
      accepted: accepted,
      textualAccuracy: accepted ? 1 : .5,
      semanticAccuracy: null,
      classification: accepted
          ? LineClassification.wordPerfect
          : LineClassification.significantDeviation,
      confidence: .9,
    ),
    responseDelay: const Duration(seconds: 2),
    duration: const Duration(seconds: 3),
    hints: hints,
    cueRequests: hints > 0 ? [CueRequest(1, DateTime(2026, 1, day))] : [],
    at: DateTime(2026, 1, day),
  );
  RehearsalReport report(List<LineAttempt> attempts) => RehearsalReport(
    id: newId(),
    productionId: production.id,
    sceneId: 's',
    sceneIds: ['s'],
    character: 'MARA',
    mode: AccuracyMode.flexible,
    practice: PracticeMode.scenePartner,
    startedAt: DateTime(2026),
    finishedAt: DateTime(2026),
    attempts: attempts,
  );
  test(
    'Rewritten dialogue requires a fresh attempt before counting as off book',
    () {
      final edited = production.copyWith(
        scenes: [
          Scene(
            id: 's',
            heading: 'Scene',
            entries: [
              a.copyWith(text: 'A new line.'),
              b,
            ],
          ),
        ],
      );
      expect(
        PracticeProgress(edited, [
          report([attempt(a)]),
        ]).offBook,
        0,
      );
    },
  );
  test(
    'Off-book coverage uses latest attempts and includes unpractised lines',
    () {
      expect(
        PracticeProgress(production, [
          report([attempt(a)]),
        ]).coverage,
        .5,
      );
      final progress = PracticeProgress(production, [
        report([attempt(a, accepted: false, day: 2)]),
        report([attempt(a)]),
      ]);
      expect(progress.coverage, 0);
      expect(progress.weakest, hasLength(1));
      expect(
        PracticeProgress(production, [
          report([attempt(a, hints: 1)]),
        ]).coverage,
        0,
      );
    },
  );
  test(
    'CSV preserves commas and quotes while preventing spreadsheet formulas',
    () {
      final text = ExportService.csv(report([attempt(a), attempt(b)]));
      expect(text, contains('"\'=HYPERLINK(""remote"")"'));
      expect(text, contains('"Wait, please."'));
    },
  );
  test('Exported reports preserve cue timestamps and original dialogue', () {
    final data = ExportService.reportMap(report([attempt(b, hints: 1)]));
    final line = (data['attempts'] as List).single as Map;
    expect(line['expected'], b.text);
    expect((line['cueRequests'] as List).single['level'], 1);
    expect(data['sceneIds'], ['s']);
  });
}
