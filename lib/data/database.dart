import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import '../domain/models.dart';
import '../domain/evaluator.dart';
import '../domain/voice_catalog.dart';

class CueDatabase {
  CueDatabase(this.db);
  final Database db;
  static const schemaVersion = 4;
  static Future<CueDatabase> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    if (factory == null && (Platform.isLinux || Platform.isWindows)) {
      ffi.sqfliteFfiInit();
      factory = ffi.databaseFactoryFfi;
    }
    factory ??= databaseFactory;
    if (path == null) {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      path = p.join(dir.path, 'cue.sqlite');
    }
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys=ON');
          await db.rawQuery('PRAGMA journal_mode=WAL');
        },
        onCreate: (db, version) async {
          await _v1(db);
          await _v2(db);
          await _v3(db);
          await _v4(db);
        },
        onUpgrade: (db, old, newVersion) async {
          if (old < 2) {
            await _v2(db);
          }
          if (old < 3) {
            await _v3(db);
          }
          if (old < 4) await _v4(db);
        },
      ),
    );
    return CueDatabase(db);
  }

  static Future<void> _v1(Database db) async {
    const statements = [
      'CREATE TABLE production(id TEXT PRIMARY KEY,title TEXT NOT NULL,author TEXT NOT NULL,selected_character TEXT,created_at TEXT NOT NULL)',
      'CREATE TABLE script_source(id TEXT PRIMARY KEY,production_id TEXT NOT NULL REFERENCES production(id) ON DELETE CASCADE,name TEXT NOT NULL,format TEXT NOT NULL)',
      'CREATE TABLE character(id TEXT PRIMARY KEY,production_id TEXT NOT NULL REFERENCES production(id) ON DELETE CASCADE,name TEXT NOT NULL,UNIQUE(production_id,name))',
      'CREATE TABLE scene(id TEXT PRIMARY KEY,production_id TEXT NOT NULL REFERENCES production(id) ON DELETE CASCADE,heading TEXT NOT NULL,position INTEGER NOT NULL)',
      'CREATE TABLE script_entry(id TEXT PRIMARY KEY,scene_id TEXT NOT NULL REFERENCES scene(id) ON DELETE CASCADE,type INTEGER NOT NULL,position INTEGER NOT NULL,text TEXT NOT NULL)',
      'CREATE TABLE dialogue_line(entry_id TEXT PRIMARY KEY REFERENCES script_entry(id) ON DELETE CASCADE,character_id TEXT NOT NULL REFERENCES character(id),parenthetical TEXT NOT NULL)',
      'CREATE TABLE accepted_variation(id TEXT PRIMARY KEY,line_id TEXT NOT NULL REFERENCES script_entry(id) ON DELETE CASCADE,text TEXT NOT NULL,accepted_at TEXT NOT NULL,UNIQUE(line_id,text))',
      'CREATE TABLE protected_phrase(id TEXT PRIMARY KEY,line_id TEXT NOT NULL REFERENCES script_entry(id) ON DELETE CASCADE,text TEXT NOT NULL,UNIQUE(line_id,text))',
      'CREATE TABLE voice_assignment(character_id TEXT PRIMARY KEY REFERENCES character(id) ON DELETE CASCADE,speaker INTEGER NOT NULL,rate REAL NOT NULL,direction TEXT NOT NULL)',
      'CREATE TABLE rehearsal_session(id TEXT PRIMARY KEY,production_id TEXT NOT NULL REFERENCES production(id) ON DELETE CASCADE,scene_id TEXT NOT NULL REFERENCES scene(id) ON DELETE CASCADE,character TEXT NOT NULL,mode INTEGER NOT NULL,practice INTEGER NOT NULL,started_at TEXT NOT NULL,finished_at TEXT NOT NULL,completed INTEGER NOT NULL)',
      'CREATE TABLE line_attempt(id TEXT PRIMARY KEY,session_id TEXT NOT NULL REFERENCES rehearsal_session(id) ON DELETE CASCADE,line_id TEXT NOT NULL REFERENCES script_entry(id) ON DELETE CASCADE,transcript TEXT NOT NULL,accepted INTEGER NOT NULL,textual_accuracy REAL NOT NULL,semantic_accuracy REAL,confidence REAL NOT NULL,classification INTEGER NOT NULL,meaning_changed INTEGER NOT NULL,missing TEXT NOT NULL,inserted TEXT NOT NULL,violations TEXT NOT NULL,reason TEXT NOT NULL,response_ms INTEGER NOT NULL,duration_ms INTEGER NOT NULL,hints INTEGER NOT NULL,at TEXT NOT NULL,interrupted INTEGER NOT NULL)',
      'CREATE TABLE cue_request(id TEXT PRIMARY KEY,attempt_id TEXT NOT NULL REFERENCES line_attempt(id) ON DELETE CASCADE,level INTEGER NOT NULL)',
      'CREATE TABLE model_installation(id TEXT PRIMARY KEY,path TEXT NOT NULL,bytes INTEGER NOT NULL,installed_at TEXT NOT NULL)',
      'CREATE TABLE app_setting(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
      'CREATE INDEX entry_scene_position ON script_entry(scene_id,position)',
      'CREATE INDEX attempt_line ON line_attempt(line_id)',
      'CREATE INDEX session_production_date ON rehearsal_session(production_id,started_at DESC)',
    ];
    for (final sql in statements) {
      await db.execute(sql);
    }
  }

  static Future<void> _v2(Database db) async {
    await db.execute(
      'ALTER TABLE line_attempt ADD COLUMN used_semantic_model INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'CREATE TABLE recording(id TEXT PRIMARY KEY,session_id TEXT REFERENCES rehearsal_session(id) ON DELETE CASCADE,path TEXT NOT NULL,created_at TEXT NOT NULL)',
    );
  }

  static Future<void> _v3(Database db) async {
    await db.execute('ALTER TABLE cue_request ADD COLUMN requested_at TEXT');
  }

  static Future<void> _v4(Database db) async {
    await db.execute('ALTER TABLE line_attempt ADD COLUMN expected_text TEXT');
    await db.execute(
      'ALTER TABLE line_attempt ADD COLUMN expected_character TEXT',
    );
    await db.execute(
      'ALTER TABLE line_attempt ADD COLUMN expected_parenthetical TEXT',
    );
    await db.execute('ALTER TABLE line_attempt ADD COLUMN changed_words TEXT');
    await db.execute(
      'CREATE TABLE scene_direction(scene_id TEXT PRIMARY KEY REFERENCES scene(id) ON DELETE CASCADE,direction TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE variant_decision(line_id TEXT NOT NULL REFERENCES script_entry(id) ON DELETE CASCADE,normalized TEXT NOT NULL,PRIMARY KEY(line_id,normalized))',
    );
    await db.execute(
      'CREATE TABLE rehearsal_scene(session_id TEXT NOT NULL REFERENCES rehearsal_session(id) ON DELETE CASCADE,scene_id TEXT NOT NULL REFERENCES scene(id) ON DELETE CASCADE,position INTEGER NOT NULL,PRIMARY KEY(session_id,scene_id))',
    );
    await db.execute(
      'INSERT INTO rehearsal_scene SELECT id,scene_id,0 FROM rehearsal_session',
    );
  }

  Future<void> saveProduction(Production prod) async {
    await db.transaction((tx) async {
      final exists = await tx.query(
        'production',
        columns: ['id'],
        where: 'id=?',
        whereArgs: [prod.id],
      );
      final value = {
        'id': prod.id,
        'title': prod.title,
        'author': prod.author,
        'selected_character': prod.selectedCharacter,
        'created_at': prod.createdAt.toIso8601String(),
      };
      if (exists.isEmpty) {
        await tx.insert('production', value);
        await tx.insert('script_source', {
          'id': newId(),
          'production_id': prod.id,
          'name': prod.sourceName,
          'format': prod.sourceFormat,
        });
      } else {
        await tx.update(
          'production',
          value,
          where: 'id=?',
          whereArgs: [prod.id],
        );
      }
      final characterIds = <String, String>{};
      for (final name in prod.characters) {
        final rows = await tx.query(
          'character',
          where: 'production_id=? AND name=?',
          whereArgs: [prod.id, name],
        );
        final id = rows.isEmpty ? newId() : rows.first['id'] as String;
        characterIds[name] = id;
        if (rows.isEmpty) {
          await tx.insert('character', {
            'id': id,
            'production_id': prod.id,
            'name': name,
          });
        }
      }
      final validScenes = prod.scenes.map((s) => s.id).toSet();
      final oldScenes = await tx.query(
        'scene',
        where: 'production_id=?',
        whereArgs: [prod.id],
      );
      final oldEntries = await tx.rawQuery(
        'SELECT e.id FROM script_entry e JOIN scene s ON s.id=e.scene_id WHERE s.production_id=?',
        [prod.id],
      );
      final validEntries = {
        for (final s in prod.scenes)
          for (final e in s.entries) e.id,
      };
      for (var i = 0; i < prod.scenes.length; i++) {
        final scene = prod.scenes[i];
        final exists = await tx.query(
          'scene',
          columns: ['id'],
          where: 'id=?',
          whereArgs: [scene.id],
        );
        final sceneMap = {
          'id': scene.id,
          'production_id': prod.id,
          'heading': scene.heading,
          'position': i,
        };
        if (exists.isEmpty) {
          await tx.insert('scene', sceneMap);
        } else {
          await tx.update(
            'scene',
            sceneMap,
            where: 'id=?',
            whereArgs: [scene.id],
          );
        }
        for (var j = 0; j < scene.entries.length; j++) {
          final e = scene.entries[j];
          final existing = await tx.query(
            'script_entry',
            columns: ['id', 'text'],
            where: 'id=?',
            whereArgs: [e.id],
          );
          final entryMap = {
            'id': e.id,
            'scene_id': scene.id,
            'type': e.type.index,
            'position': j,
            'text': e.text,
          };
          if (existing.isEmpty) {
            await tx.insert('script_entry', entryMap);
          } else {
            if (existing.first['text'] != e.text) {
              await tx.delete(
                'accepted_variation',
                where: 'line_id=?',
                whereArgs: [e.id],
              );
              await tx.delete(
                'variant_decision',
                where: 'line_id=?',
                whereArgs: [e.id],
              );
            }
            await tx.update(
              'script_entry',
              entryMap,
              where: 'id=?',
              whereArgs: [e.id],
            );
          }
          if (e.isDialogue) {
            await tx.insert('dialogue_line', {
              'entry_id': e.id,
              'character_id': characterIds[e.character!],
              'parenthetical': e.parenthetical,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          } else {
            await tx.delete(
              'dialogue_line',
              where: 'entry_id=?',
              whereArgs: [e.id],
            );
          }
          await tx.delete(
            'protected_phrase',
            where: 'line_id=?',
            whereArgs: [e.id],
          );
          for (final phrase in e.protectedPhrases.toSet()) {
            await tx.insert('protected_phrase', {
              'id': newId(),
              'line_id': e.id,
              'text': phrase,
            });
          }
        }
      }
      for (final e in oldEntries) {
        if (!validEntries.contains(e['id'])) {
          await tx.delete('script_entry', where: 'id=?', whereArgs: [e['id']]);
        }
      }
      for (final s in oldScenes) {
        if (!validScenes.contains(s['id'])) {
          // Keep runs when a scene is merged; moved line IDs remain authoritative.
          if (prod.scenes.isNotEmpty) {
            final links = await tx.query(
              'rehearsal_scene',
              where: 'scene_id=?',
              whereArgs: [s['id']],
            );
            for (final link in links) {
              await tx.insert('rehearsal_scene', {
                'session_id': link['session_id'],
                'scene_id': prod.scenes.first.id,
                'position': link['position'],
              }, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
            await tx.update(
              'rehearsal_session',
              {'scene_id': prod.scenes.first.id},
              where: 'scene_id=?',
              whereArgs: [s['id']],
            );
          }
          await tx.delete('scene', where: 'id=?', whereArgs: [s['id']]);
        }
      }
      // Remove retired character names after dialogue ownership has moved.
      final chars = await tx.query(
        'character',
        where: 'production_id=?',
        whereArgs: [prod.id],
      );
      for (final c in chars) {
        if (!characterIds.containsKey(c['name'])) {
          await tx.delete('character', where: 'id=?', whereArgs: [c['id']]);
        }
      }
    });
  }

  Future<List<Production>> productions() async {
    final rows = await db.query('production', orderBy: 'created_at DESC');
    return Future.wait(rows.map(_hydrate));
  }

  Future<Production> _hydrate(Map<String, Object?> row) async {
    final sceneRows = await db.query(
      'scene',
      where: 'production_id=?',
      whereArgs: [row['id']],
      orderBy: 'position',
    );
    final scenes = <Scene>[];
    for (final s in sceneRows) {
      final entries = await db.rawQuery(
        'SELECT e.*,c.name AS character,d.parenthetical FROM script_entry e LEFT JOIN dialogue_line d ON d.entry_id=e.id LEFT JOIN character c ON c.id=d.character_id WHERE e.scene_id=? ORDER BY e.position',
        [s['id']],
      );
      final hydrated = <ScriptEntry>[];
      for (final e in entries) {
        final anchors = await db.query(
          'protected_phrase',
          where: 'line_id=?',
          whereArgs: [e['id']],
        );
        final variants = await db.query(
          'accepted_variation',
          where: 'line_id=?',
          whereArgs: [e['id']],
        );
        final flagged = await db.query(
          'variant_decision',
          where: 'line_id=?',
          whereArgs: [e['id']],
        );
        hydrated.add(
          ScriptEntry(
            id: e['id'] as String,
            type: EntryType.values[e['type'] as int],
            text: e['text'] as String,
            character: e['character'] as String?,
            parenthetical: e['parenthetical'] as String? ?? '',
            protectedPhrases: anchors.map((a) => a['text'] as String).toList(),
            variants: variants.map((a) => a['text'] as String).toList(),
            flaggedVariants: flagged
                .map((a) => a['normalized'] as String)
                .toList(),
          ),
        );
      }
      scenes.add(
        Scene(
          id: s['id'] as String,
          heading: s['heading'] as String,
          entries: hydrated,
        ),
      );
    }
    final source = await db.query(
      'script_source',
      where: 'production_id=?',
      whereArgs: [row['id']],
      limit: 1,
    );
    return Production(
      id: row['id'] as String,
      title: row['title'] as String,
      author: row['author'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      selectedCharacter: row['selected_character'] as String?,
      scenes: scenes,
      sourceName: source.firstOrNull?['name'] as String? ?? '',
      sourceFormat: source.firstOrNull?['format'] as String? ?? '',
    );
  }

  Future<void> acceptVariation(String lineId, String text) =>
      db.transaction((tx) async {
        await tx.delete(
          'variant_decision',
          where: 'line_id=? AND normalized=?',
          whereArgs: [lineId, TextNormalizer().tokens(text).join(' ')],
        );
        await tx.insert('accepted_variation', {
          'id': newId(),
          'line_id': lineId,
          'text': text,
          'accepted_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      });
  Future<void> removeVariation(String lineId, String text) => db.delete(
    'accepted_variation',
    where: 'line_id=? AND text=?',
    whereArgs: [lineId, text],
  );
  Future<void> saveReport(RehearsalReport r) async {
    await db.transaction((tx) async {
      await tx.insert('rehearsal_session', {
        'id': r.id,
        'production_id': r.productionId,
        'scene_id': r.sceneId,
        'character': r.character,
        'mode': r.mode.index,
        'practice': r.practice.index,
        'started_at': r.startedAt.toIso8601String(),
        'finished_at': r.finishedAt.toIso8601String(),
        'completed': r.completed ? 1 : 0,
      });
      final scenes = r.sceneIds.isEmpty ? [r.sceneId] : r.sceneIds;
      for (var i = 0; i < scenes.length; i++) {
        await tx.insert('rehearsal_scene', {
          'session_id': r.id,
          'scene_id': scenes[i],
          'position': i,
        });
      }
      for (final a in r.attempts) {
        final e = a.evaluation;
        await tx.insert('line_attempt', {
          'id': a.id,
          'session_id': r.id,
          'line_id': a.line.id,
          'transcript': a.transcript,
          'accepted': e.accepted ? 1 : 0,
          'textual_accuracy': e.textualAccuracy,
          'semantic_accuracy': e.semanticAccuracy,
          'confidence': e.confidence,
          'classification': e.classification.index,
          'meaning_changed': e.meaningChanged ? 1 : 0,
          'missing': jsonEncode(e.missingWords),
          'inserted': jsonEncode(e.insertedWords),
          'violations': jsonEncode(e.protectedWordViolations),
          'reason': e.reason,
          'response_ms': a.responseDelay.inMilliseconds,
          'duration_ms': a.duration.inMilliseconds,
          'hints': a.hints,
          'at': a.at.toIso8601String(),
          'interrupted': a.interrupted ? 1 : 0,
          'used_semantic_model': e.usedSemanticModel ? 1 : 0,
          'expected_text': a.line.text,
          'expected_character': a.line.character,
          'expected_parenthetical': a.line.parenthetical,
          'changed_words': jsonEncode(e.changedWords),
        });
        for (final cue in a.cueRequests) {
          await tx.insert('cue_request', {
            'id': newId(),
            'attempt_id': a.id,
            'level': cue.level,
            'requested_at': cue.at.toIso8601String(),
          });
        }
      }
    });
  }

  Future<List<RehearsalReport>> history(Production prod) async {
    final lines = {
      for (final s in prod.scenes)
        for (final e in s.entries) e.id: e,
    };
    final rows = await db.query(
      'rehearsal_session',
      where: 'production_id=?',
      whereArgs: [prod.id],
      orderBy: 'started_at DESC',
    );
    final result = <RehearsalReport>[];
    List<String> strings(Object? v) =>
        (jsonDecode(v as String) as List).cast<String>();
    for (final row in rows) {
      final runScenes = await db.query(
        'rehearsal_scene',
        where: 'session_id=?',
        whereArgs: [row['id']],
        orderBy: 'position',
      );
      final cues = await db.rawQuery(
        'SELECT c.* FROM cue_request c JOIN line_attempt a ON a.id=c.attempt_id WHERE a.session_id=? ORDER BY c.requested_at',
        [row['id']],
      );
      final attempts = await db.query(
        'line_attempt',
        where: 'session_id=?',
        whereArgs: [row['id']],
        orderBy: 'at',
      );
      result.add(
        RehearsalReport(
          id: row['id'] as String,
          productionId: prod.id,
          sceneId: row['scene_id'] as String,
          character: row['character'] as String,
          mode: AccuracyMode.values[row['mode'] as int],
          practice: PracticeMode.values[row['practice'] as int],
          startedAt: DateTime.parse(row['started_at'] as String),
          finishedAt: DateTime.parse(row['finished_at'] as String),
          completed: row['completed'] == 1,
          sceneIds: runScenes.map((s) => s['scene_id'] as String).toList(),
          attempts: attempts
              .where((a) => lines.containsKey(a['line_id']))
              .map(
                (a) => LineAttempt(
                  id: a['id'] as String,
                  line: lines[a['line_id']]!.copyWith(
                    text: a['expected_text'] as String?,
                    character: a['expected_character'] as String?,
                    parenthetical: a['expected_parenthetical'] as String?,
                  ),
                  transcript: a['transcript'] as String,
                  evaluation: LineEvaluation(
                    accepted: a['accepted'] == 1,
                    textualAccuracy: (a['textual_accuracy'] as num).toDouble(),
                    semanticAccuracy: (a['semantic_accuracy'] as num?)
                        ?.toDouble(),
                    confidence: (a['confidence'] as num).toDouble(),
                    classification:
                        LineClassification.values[a['classification'] as int],
                    meaningChanged: a['meaning_changed'] == 1,
                    missingWords: strings(a['missing']),
                    insertedWords: strings(a['inserted']),
                    changedWords: a['changed_words'] == null
                        ? const []
                        : strings(a['changed_words']),
                    protectedWordViolations: strings(a['violations']),
                    reason: a['reason'] as String,
                    usedSemanticModel: a['used_semantic_model'] == 1,
                  ),
                  responseDelay: Duration(
                    milliseconds: a['response_ms'] as int,
                  ),
                  duration: Duration(milliseconds: a['duration_ms'] as int),
                  hints: a['hints'] as int,
                  at: DateTime.parse(a['at'] as String),
                  interrupted: a['interrupted'] == 1,
                  cueRequests: cues
                      .where((c) => c['attempt_id'] == a['id'])
                      .map(
                        (c) => CueRequest(
                          c['level'] as int,
                          DateTime.tryParse(
                                c['requested_at'] as String? ?? '',
                              ) ??
                              DateTime.parse(a['at'] as String),
                        ),
                      )
                      .toList(),
                ),
              )
              .toList(),
        ),
      );
    }
    return result;
  }

  Future<Set<String>> weakLineIds(
    Production prod, {
    bool allImperfect = false,
  }) async {
    final runs = await history(prod);
    final scores = <String, List<double>>{};
    for (final run in runs.take(12)) {
      for (final a in run.attempts) {
        scores
            .putIfAbsent(a.line.id, () => [])
            .add(
              a.evaluation.accepted &&
                      a.hints == 0 &&
                      a.responseDelay.inSeconds <= 6 &&
                      a.evaluation.confidence >= .65
                  ? a.evaluation.textualAccuracy
                  : 0,
            );
      }
    }
    return scores.entries
        .where(
          (e) =>
              e.value.reduce((a, b) => a + b) / e.value.length <
              (allImperfect ? 1 : .85),
        )
        .map((e) => e.key)
        .toSet();
  }

  Future<List<Map<String, Object?>>> repeatedVariants(
    String productionId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT a.line_id,a.transcript,e.text FROM line_attempt a JOIN rehearsal_session s ON s.id=a.session_id JOIN script_entry e ON e.id=a.line_id WHERE s.production_id=? AND a.meaning_changed=0 AND a.violations=\'[]\' AND a.transcript<>\'\' ORDER BY a.at DESC',
      [productionId],
    );
    final decisions = await db.query('variant_decision');
    final accepted = await db.query('accepted_variation');
    final normalizer = TextNormalizer();
    String normalize(String s) => normalizer.tokens(s).join(' ');
    final counts = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final line = row['line_id'];
      final normalized = normalize(row['transcript'] as String);
      if (normalized == normalize(row['text'] as String) ||
          decisions.any(
            (d) => d['line_id'] == line && d['normalized'] == normalized,
          ) ||
          accepted.any(
            (d) =>
                d['line_id'] == line &&
                normalize(d['text'] as String) == normalized,
          )) {
        continue;
      }
      final key = '$line|$normalized';
      final candidate = counts.putIfAbsent(
        key,
        () => {
          'line_id': line,
          'transcript': row['transcript'],
          'original': row['text'],
          'normalized': normalized,
          'repetitions': 0,
        },
      );
      candidate['repetitions'] = (candidate['repetitions'] as int) + 1;
    }
    return counts.values.where((r) => (r['repetitions'] as int) >= 3).toList();
  }

  Future<void> dismissVariation(String lineId, String normalized) async {
    await db.insert('variant_decision', {
      'line_id': lineId,
      'normalized': normalized,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>> sceneDirections(Production production) async {
    final rows = await db.rawQuery(
      'SELECT d.* FROM scene_direction d JOIN scene s ON s.id=d.scene_id WHERE s.production_id=?',
      [production.id],
    );
    return {
      for (final r in rows) r['scene_id'] as String: r['direction'] as String,
    };
  }

  Future<void> saveSceneDirection(String id, String direction) async {
    await db.insert('scene_direction', {
      'scene_id': id,
      'direction': direction,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> offBookLines(Production production) async {
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS n FROM (SELECT a.accepted,a.hints,a.expected_text,e.text,ROW_NUMBER() OVER (PARTITION BY a.line_id ORDER BY a.at DESC) AS recent FROM line_attempt a JOIN rehearsal_session s ON s.id=a.session_id JOIN script_entry e ON e.id=a.line_id JOIN dialogue_line dl ON dl.entry_id=e.id JOIN character c ON c.id=dl.character_id WHERE s.production_id=? AND s.character=? AND c.name=s.character) WHERE recent=1 AND accepted=1 AND hints=0 AND (expected_text='' OR expected_text=text)",
      [production.id, production.selectedCharacter ?? ''],
    );
    return rows.single['n'] as int;
  }

  Future<VoiceAssignment> voice(String productionId, String character) async {
    final rows = await db.rawQuery(
      'SELECT v.* FROM voice_assignment v JOIN character c ON c.id=v.character_id WHERE c.production_id=? AND c.name=?',
      [productionId, character],
    );
    if (rows.isEmpty) {
      final chars = await db.query(
        'character',
        where: 'production_id=?',
        whereArgs: [productionId],
        orderBy: 'name',
      );
      return VoiceAssignment(
        speaker: suggestedVoice(
          character,
          chars.indexWhere((c) => c['name'] == character),
        ).speaker,
      );
    }
    final r = rows.first;
    return VoiceAssignment(
      speaker: (r['speaker'] as int) >= 1000
          ? r['speaker'] as int
          : suggestedVoice(character, 0).speaker,
      rate: (r['rate'] as num).toDouble(),
      direction: r['direction'] as String,
    );
  }

  Future<void> saveVoice(
    String productionId,
    String character,
    VoiceAssignment voice,
  ) async {
    final chars = await db.query(
      'character',
      where: 'production_id=? AND name=?',
      whereArgs: [productionId, character],
    );
    await db.insert('voice_assignment', {
      'character_id': chars.first['id'],
      'speaker': voice.speaker,
      'rate': voice.rate,
      'direction': voice.direction,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<AppSettings> settings() async {
    final rows = await db.query('app_setting');
    return AppSettings.fromMap({
      for (final r in rows)
        r['key'] as String: jsonDecode(r['value'] as String),
    });
  }

  Future<void> saveSettings(AppSettings settings) async {
    await db.transaction((tx) async {
      for (final e in settings.toMap().entries) {
        await tx.insert('app_setting', {
          'key': e.key,
          'value': jsonEncode(e.value),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> deleteHistory({String? productionId}) => db.delete(
    'rehearsal_session',
    where: productionId == null ? null : 'production_id=?',
    whereArgs: productionId == null ? null : [productionId],
  );
  Future<void> deleteProduction(String id) =>
      db.delete('production', where: 'id=?', whereArgs: [id]);
  Future<void> close() => db.close();
}
