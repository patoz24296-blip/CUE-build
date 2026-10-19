import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cue/data/model_manager.dart';
import 'package:cue/services/semantic.dart';

void main() {
  test('Model paths cannot escape installation folder', () {
    final root = Directory.systemTemp.path;
    for (final path in [
      '../file',
      '/file',
      'a/../../file',
      'a\\..\\file',
      'a//file',
    ]) {
      expect(() => safeModelPath(root, path), throwsFormatException);
    }
    expect(safeModelPath(root, 'voices/en'), contains('voices'));
  });
  test('Every downloadable file has pinned identity and size', () {
    final catalog =
        (jsonDecode(File('assets/models.json').readAsStringSync()) as List)
            .cast<Map>();
    for (final model in catalog) {
      expect(model['files'], isNotEmpty);
      var bytes = 0;
      for (final file in model['files']) {
        expect(file['url'], startsWith('https://'));
        expect(file['digest'].length, file['algorithm'] == 'sha256' ? 64 : 40);
        bytes += file['bytes'] as int;
      }
      expect(bytes, model['bytes']);
    }
  });
  test('Malformed semantic responses cannot invent decisions', () {
    for (final text in [
      'yes',
      '{}',
      '{"preserved":true,"confidence":2,"reason":"yes"}',
      '{"preserved":"yes","confidence":0.9,"reason":"yes"}',
    ]) {
      expect(parseJudgment(text), isNull);
    }
    expect(
      parseJudgment(
        '{"preserved":true,"confidence":0.9,"reason":"Same meaning"}',
      )?.preserved,
      isTrue,
    );
  });
}
