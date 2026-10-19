import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';

class ExportService {
  static String safeName(String name) =>
      name.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '').trim();
  static Future<void> file(File source, String name) async {
    if (Platform.isIOS || Platform.isAndroid) {
      await const MethodChannel('studio.cue/export').invokeMethod<bool>(
        'exportRecording',
        {'path': source.path, 'name': name},
      );
      return;
    }
    final mobile = Platform.isIOS || Platform.isAndroid;
    final target = await FilePicker.platform.saveFile(
      fileName: name,
      type: FileType.custom,
      allowedExtensions: ['wav'],
      bytes: mobile ? await source.readAsBytes() : null,
    );
    if (!mobile && target != null) await source.copy(target);
  }

  static String csv(RehearsalReport report) {
    String cell(Object? value) {
      var text = value.toString();
      if (RegExp(r'^\s*[=+@-]').hasMatch(text)) text = "'$text";
      return '"${text.replaceAll('"', '""')}"';
    }

    return [
      'Expected,Spoken,Accepted,Textual accuracy,Classification,Hints,Response seconds,Reason',
      for (final a in report.attempts)
        [
          a.line.text,
          a.transcript,
          a.evaluation.accepted,
          a.evaluation.textualAccuracy,
          a.evaluation.classification.name,
          a.hints,
          a.responseDelay.inMilliseconds / 1000,
          a.evaluation.reason,
        ].map(cell).join(','),
    ].join('\r\n');
  }

  static Map<String, Object?> reportMap(RehearsalReport report) => {
    'id': report.id,
    'character': report.character,
    'accuracyMode': report.mode.name,
    'practice': report.practice.name,
    'startedAt': report.startedAt.toIso8601String(),
    'completed': report.completed,
    'sceneIds': report.sceneIds,
    'attempts': [
      for (final a in report.attempts)
        {
          'lineId': a.line.id,
          'expected': a.line.text,
          'spoken': a.transcript,
          'accepted': a.evaluation.accepted,
          'textualAccuracy': a.evaluation.textualAccuracy,
          'classification': a.evaluation.classification.name,
          'reason': a.evaluation.reason,
          'missing': a.evaluation.missingWords,
          'added': a.evaluation.insertedWords,
          'protectedViolations': a.evaluation.protectedWordViolations,
          'responseMs': a.responseDelay.inMilliseconds,
          'durationMs': a.duration.inMilliseconds,
          'cueRequests': [
            for (final c in a.cueRequests)
              {'level': c.level, 'at': c.at.toIso8601String()},
          ],
        },
    ],
  };
  static Future<void> report(
    RehearsalReport report, {
    bool json = false,
  }) async {
    final text = json
        ? const JsonEncoder.withIndent('  ').convert(reportMap(report))
        : csv(report);
    await FilePicker.platform.saveFile(
      fileName: 'CUE-${report.id}.${json ? 'json' : 'csv'}',
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
  }
}
