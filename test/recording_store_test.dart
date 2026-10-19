import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cue/data/database.dart';
import 'package:cue/data/recording_store.dart';
import 'package:cue/domain/models.dart';
import 'package:cue/domain/script_parser.dart';

void main() {
  late Directory directory;
  late CueDatabase database;
  late RecordingStore store;
  late RehearsalReport run;
  setUp(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('cue-recording-store-');
    database = await CueDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    store = RecordingStore(database, directory);
    final production = ScriptParser().parse(
      'INT. ROOM - DAY\n\nMARA\nWait for me.\n',
      filename: 'sample.fountain',
    );
    await database.saveProduction(production);
    run = RehearsalReport(
      id: 'session',
      productionId: production.id,
      sceneId: production.scenes.single.id,
      character: 'MARA',
      mode: AccuracyMode.flexible,
      practice: PracticeMode.scenePartner,
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      attempts: [],
    );
    await database.saveReport(run);
  });
  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });
  test(
    'Recordings are associated with the run and delete immediately',
    () async {
      final file = store.newFile();
      await file.writeAsBytes([1, 2]);
      await store.save(file, run.id);
      final row = (await store.list()).single;
      expect(row['session_id'], run.id);
      expect(row['title'], 'sample');
      await store.delete(row);
      expect(await store.list(), isEmpty);
      expect(await file.exists(), isFalse);
    },
  );
  test(
    'Automatic retention removes expired audio and orphan files only',
    () async {
      final old = store.newFile(),
          fresh = store.newFile(),
          orphan = store.newFile();
      for (final file in [old, fresh, orphan]) {
        await file.writeAsBytes([1]);
      }
      await store.save(old, run.id);
      await store.save(fresh, run.id);
      await database.db.update(
        'recording',
        {'created_at': '2026-10-04'},
        where: 'path=?',
        whereArgs: [fresh.path],
      );
      await database.db.update(
        'recording',
        {'created_at': '2024-01-01'},
        where: 'path=?',
        whereArgs: [old.path],
      );
      await store.clean(
        const AppSettings(recordingRetentionDays: 7),
        now: DateTime(2026, 10, 5),
      );
      expect(await old.exists(), isFalse);
      expect(await orphan.exists(), isFalse);
      expect(await fresh.exists(), isTrue);
      expect(await store.list(), hasLength(1));
    },
  );
  test('Disabled retention preserves old saved recordings', () async {
    final file = store.newFile();
    await file.writeAsBytes([1]);
    await store.save(file, run.id);
    await database.db.update('recording', {'created_at': '2024-01-01'});
    await store.clean(const AppSettings(autoDeleteRecordings: false));
    expect(await file.exists(), isTrue);
  });
  test(
    'A recording outside owned storage cannot be saved or deleted',
    () async {
      final outside = File('${directory.parent.path}/unowned.wav');
      await expectLater(
        store.save(outside, run.id),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        store.delete({'id': 'unowned', 'path': outside.path}),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}
