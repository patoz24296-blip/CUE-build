import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cue/data/database.dart';
import 'package:cue/domain/models.dart';
import 'package:cue/domain/evaluator.dart';
import 'package:cue/domain/script_parser.dart';

void main() {
  late CueDatabase database;
  setUp(() async {
    sqfliteFfiInit();
    database = await CueDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
  });
  tearDown(() async {
    await database.close();
  });
  test(
    'Legacy server preferences are ignored without losing scripts or rehearsal settings',
    () async {
      final production = ScriptParser()
          .parse(
            File('assets/sample.fountain').readAsStringSync(),
            filename: 'sample.fountain',
          )
          .copyWith(selectedCharacter: 'MARA');
      await database.saveProduction(production);
      await database.db.insert('app_setting', {
        'key': 'semanticEngine',
        'value': '"ollama"',
      });
      await database.db.insert('app_setting', {
        'key': 'ollamaModel',
        'value': '"previous-local-model"',
      });
      await database.db.insert('app_setting', {
        'key': 'language',
        'value': '"es"',
      });
      final settings = await database.settings();
      expect(settings.language, 'es');
      expect(settings.toMap().containsKey('semanticEngine'), isFalse);
      expect(settings.toMap().containsKey('ollamaModel'), isFalse);
      await database.saveSettings(settings.change('language', 'en'));
      expect((await database.settings()).language, 'en');
      expect(
        (await database.productions()).single.lineCount,
        production.lineCount,
      );
    },
  );
  Production sample() => ScriptParser()
      .parse(
        File('assets/sample.fountain').readAsStringSync(),
        filename: 'sample.fountain',
      )
      .copyWith(selectedCharacter: 'MARA');
  Future<RehearsalReport> report(Production prod) async {
    final entry = prod.scenes.first.dialogue[4];
    final now = DateTime.now();
    return RehearsalReport(
      id: newId(),
      productionId: prod.id,
      sceneId: prod.scenes.first.id,
      character: 'MARA',
      mode: AccuracyMode.flexible,
      practice: PracticeMode.scenePartner,
      startedAt: now,
      finishedAt: now,
      attempts: [
        LineAttempt(
          id: newId(),
          line: entry,
          transcript: entry.text,
          evaluation: await LineEvaluator().evaluate(
            line: entry,
            spoken: entry.text,
            mode: AccuracyMode.flexible,
          ),
          responseDelay: const Duration(seconds: 1),
          duration: const Duration(seconds: 3),
          hints: 2,
          at: now,
          cueRequests: [
            CueRequest(1, now),
            CueRequest(3, now.add(const Duration(seconds: 1))),
          ],
        ),
      ],
    );
  }

  test(
    'Normalized script, settings, voices and accepted variations round trip',
    () async {
      final production = sample();
      await database.saveProduction(production);
      await database.saveSettings(
        const AppSettings(theme: 'dark', timing: ResponseTiming.patient),
      );
      await database.saveVoice(
        production.id,
        'THEO',
        const VoiceAssignment(speaker: 1007, rate: .9),
      );
      await database.acceptVariation(
        production.scenes.first.dialogue.first.id,
        'Tell Ellis I will arrive tomorrow.',
      );
      final loaded = (await database.productions()).single;
      expect(loaded.title, production.title);
      expect(
        loaded.scenes.first.entries.map((e) => e.id),
        production.scenes.first.entries.map((e) => e.id),
      );
      expect(loaded.scenes.first.dialogue.first.variants, isNotEmpty);
      expect((await database.settings()).theme, 'dark');
      expect((await database.voice(production.id, 'THEO')).speaker, 1007);
    },
  );
  test(
    'Scene split and merge preserve existing line attempts and hints',
    () async {
      final production = sample();
      await database.saveProduction(production);
      final run = await report(production);
      await database.saveReport(run);
      final editor = ScriptEditor();
      final split = editor.splitScene(
        production,
        production.scenes.first.id,
        production.scenes.first.dialogue[3].id,
        'New boundary',
      );
      await database.saveProduction(split);
      expect(
        (await database.history(split)).single.attempts.single.line.id,
        run.attempts.single.line.id,
      );
      final merged = editor.mergeScene(split, split.scenes[1].id);
      await database.saveProduction(merged);
      expect((await database.history(merged)).single.attempts.single.hints, 2);
      final cues = await database.db.query('cue_request');
      expect(cues.map((c) => c['level']), [1, 3]);
      expect(cues.every((c) => c['requested_at'] != null), isTrue);
    },
  );
  test('Merging a scene that owns a session keeps its history', () async {
    final production = sample();
    await database.saveProduction(production);
    final now = DateTime.now();
    await database.saveReport(
      RehearsalReport(
        id: newId(),
        productionId: production.id,
        sceneId: production.scenes[1].id,
        character: 'MARA',
        mode: AccuracyMode.flexible,
        practice: PracticeMode.scenePartner,
        startedAt: now,
        finishedAt: now,
        attempts: [],
      ),
    );
    final merged = ScriptEditor().mergeScene(
      production,
      production.scenes[1].id,
    );
    await database.saveProduction(merged);
    expect(await database.history(merged), hasLength(1));
  });
  test(
    'History deletion keeps scripts; script deletion cascades history',
    () async {
      final production = sample();
      await database.saveProduction(production);
      await database.saveReport(await report(production));
      await database.deleteHistory();
      expect(await database.history(production), isEmpty);
      expect(await database.productions(), hasLength(1));
      await database.saveReport(await report(production));
      await database.deleteProduction(production.id);
      expect(await database.db.query('line_attempt'), isEmpty);
      expect(await database.productions(), isEmpty);
    },
  );
  for (final version in [1, 2, 3]) {
    test(
      'Real v$version database upgrades without losing scripts or history',
      () async {
        final folder = await Directory.systemTemp.createTemp('cue-migration-');
        final path = '${folder.path}/legacy.sqlite';
        final schema = File('test/fixtures/schema_v2.sql')
            .readAsStringSync()
            .split(';')
            .where((s) => s.trim().isNotEmpty)
            .toList();
        final legacy = await databaseFactoryFfiNoIsolate.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: version,
            onCreate: (db, _) async {
              for (final statement
                  in version == 1 ? schema.take(schema.length - 2) : schema) {
                await db.execute(statement);
              }
              if (version == 3) {
                await db.execute(
                  'ALTER TABLE cue_request ADD COLUMN requested_at TEXT',
                );
              }
            },
          ),
        );
        await legacy.insert('production', {
          'id': 'old-production',
          'title': 'Old play',
          'author': '',
          'selected_character': 'MARA',
          'created_at': '2024-01-01',
        });
        await legacy.insert('scene', {
          'id': 'old-scene',
          'production_id': 'old-production',
          'heading': 'Old scene',
          'position': 0,
        });
        await legacy.insert('character', {
          'id': 'old-character',
          'production_id': 'old-production',
          'name': 'MARA',
        });
        await legacy.insert('script_entry', {
          'id': 'old-line',
          'scene_id': 'old-scene',
          'type': 0,
          'position': 0,
          'text': 'Wait for me.',
        });
        await legacy.insert('dialogue_line', {
          'entry_id': 'old-line',
          'character_id': 'old-character',
          'parenthetical': '',
        });
        await legacy.insert('rehearsal_session', {
          'id': 'old-run',
          'production_id': 'old-production',
          'scene_id': 'old-scene',
          'character': 'MARA',
          'mode': 1,
          'practice': 0,
          'started_at': '2024-01-01',
          'finished_at': '2024-01-01',
          'completed': 1,
        });
        await legacy.close();
        final upgraded = await CueDatabase.open(
          path: path,
          factory: databaseFactoryFfiNoIsolate,
        );
        try {
          expect(await upgraded.db.getVersion(), CueDatabase.schemaVersion);
          final production = (await upgraded.productions()).single;
          expect(production.scenes.single.dialogue.single.text, 'Wait for me.');
          final history = (await upgraded.history(production)).single;
          expect(history.id, 'old-run');
          expect(history.sceneIds, ['old-scene']);
          await upgraded.saveSceneDirection('old-scene', 'Slow and quiet');
          expect(
            (await upgraded.sceneDirections(production))['old-scene'],
            'Slow and quiet',
          );
          final info = await upgraded.db.rawQuery(
            'PRAGMA table_info(cue_request)',
          );
          expect(info.any((c) => c['name'] == 'requested_at'), isTrue);
        } finally {
          await upgraded.close();
          await folder.delete(recursive: true);
        }
      },
    );
  }
  test(
    'Editing a script keeps the text performed in historical reports',
    () async {
      final production = sample();
      await database.saveProduction(production);
      final run = await report(production);
      await database.saveReport(run);
      await database.saveProduction(
        ScriptEditor().updateEntry(
          production,
          run.attempts.single.line.id,
          run.attempts.single.line.copyWith(text: 'A rewritten line.'),
        ),
      );
      final edited = (await database.productions()).single;
      expect(await database.offBookLines(edited), 0);
      final saved = (await database.history(edited)).single.attempts.single;
      expect(saved.line.text, run.attempts.single.line.text);
      expect(saved.cueRequests.map((c) => c.level), [1, 3]);
      expect(
        saved.cueRequests.first.at,
        run.attempts.single.cueRequests.first.at,
      );
    },
  );
  test(
    'Three safe personal variations prompt once, and keep-flagging persists',
    () async {
      final production = sample();
      await database.saveProduction(production);
      final base = await report(production);
      for (var i = 0; i < 3; i++) {
        final attempt = base.attempts.single;
        await database.saveReport(
          RehearsalReport(
            id: newId(),
            productionId: production.id,
            sceneId: base.sceneId,
            character: 'MARA',
            mode: base.mode,
            practice: base.practice,
            startedAt: base.startedAt,
            finishedAt: base.finishedAt,
            attempts: [
              LineAttempt(
                id: newId(),
                line: attempt.line,
                transcript: 'A consistent variation.',
                evaluation: const LineEvaluation(
                  accepted: false,
                  textualAccuracy: .6,
                  semanticAccuracy: null,
                  classification: LineClassification.significantDeviation,
                  confidence: .8,
                ),
                responseDelay: Duration.zero,
                duration: const Duration(seconds: 2),
                hints: 0,
                at: DateTime.now(),
              ),
            ],
          ),
        );
      }
      final candidates = await database.repeatedVariants(production.id);
      expect(candidates, hasLength(1));
      expect(candidates.single['repetitions'], 3);
      await database.dismissVariation(
        candidates.single['line_id'] as String,
        candidates.single['normalized'] as String,
      );
      expect(await database.repeatedVariants(production.id), isEmpty);
      final updated = (await database.productions()).single;
      expect(
        updated.scenes
            .expand((s) => s.dialogue)
            .firstWhere((e) => e.id == candidates.single['line_id'])
            .flaggedVariants,
        contains('a consistent variation'),
      );
      await database.acceptVariation(
        candidates.single['line_id'] as String,
        'A consistent variation.',
      );
      final accepted = (await database.productions()).single.scenes
          .expand((s) => s.dialogue)
          .firstWhere((e) => e.id == candidates.single['line_id']);
      expect(accepted.flaggedVariants, isEmpty);
      expect(accepted.variants, contains('A consistent variation.'));
    },
  );
}
