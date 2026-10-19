import 'dart:io';
import 'package:path/path.dart' as p;
import '../domain/models.dart';
import 'database.dart';

class RecordingStore {
  RecordingStore(this.database, this.root);
  final CueDatabase database;
  final Directory root;
  File newFile() => File(p.join(root.path, '${newId()}.wav'));
  Future<void> save(File file, String sessionId) async {
    _check(file.path);
    await database.db.insert('recording', {
      'id': newId(),
      'session_id': sessionId,
      'path': file.path,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  void _check(String path) {
    if (!p.isWithin(
      p.normalize(p.absolute(root.path)),
      p.normalize(p.absolute(path)),
    )) {
      throw const FileSystemException('Recording path is outside CUE storage');
    }
  }

  Future<List<Map<String, Object?>>> list({
    String? productionId,
  }) => database.db.rawQuery(
    'SELECT r.*,p.title,s.character FROM recording r LEFT JOIN rehearsal_session s ON s.id=r.session_id LEFT JOIN production p ON p.id=s.production_id ${productionId == null ? '' : 'WHERE s.production_id=?'} ORDER BY r.created_at DESC',
    productionId == null ? [] : [productionId],
  );
  Future<void> delete(Map<String, Object?> row) async {
    final path = row['path'] as String;
    _check(path);
    final file = File(path);
    if (await file.exists()) await file.delete();
    await database.db.delete(
      'recording',
      where: 'id=?',
      whereArgs: [row['id']],
    );
  }

  Future<void> deleteAll({String? productionId}) async {
    for (final row in await list(productionId: productionId)) {
      await delete(row);
    }
  }

  Future<void> clean(AppSettings settings, {DateTime? now}) async {
    await root.create(recursive: true);
    final rows = await list();
    final paths = rows.map((r) => p.normalize(r['path'] as String)).toSet();
    for (final file in await root.list().toList()) {
      if (file is File &&
          p.extension(file.path) == '.wav' &&
          !paths.contains(p.normalize(file.path))) {
        await file.delete();
      }
    }
    if (!settings.autoDeleteRecordings ||
        settings.recordingRetentionDays == 0) {
      return;
    }
    final cutoff = (now ?? DateTime.now()).subtract(
      Duration(days: settings.recordingRetentionDays),
    );
    for (final row in rows) {
      if (DateTime.parse(row['created_at'] as String).isBefore(cutoff)) {
        await delete(row);
      }
    }
  }
}
