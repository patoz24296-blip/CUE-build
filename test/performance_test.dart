import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:cue/domain/models.dart';
import 'package:cue/domain/performance.dart';

void main() {
  test(
    'Character and scene directions control audible pacing, volume and pauses',
    () {
      final beat = PerformanceDirector()
          .plan(
            'Come here.',
            const AppSettings(variableCues: false),
            const VoiceAssignment(direction: 'Quiet and slow'),
            sceneDirection: 'Pause 2 seconds',
          )
          .single;
      expect(beat.volume, .65);
      expect(beat.rate, lessThan(1));
      expect(beat.pause.inMilliseconds, 2000);
    },
  );
  test('Full performance preserves complete neural prosody and dialogue', () {
    final beats = PerformanceDirector().plan(
      'Wait, you must go now! Never come back.',
      const AppSettings(
        performance: PerformanceStyle.full,
        variableCues: false,
      ),
      const VoiceAssignment(),
    );
    expect(beats.length, 1);
    expect(
      beats.map((b) => b.text).join(' '),
      'Wait, you must go now! Never come back.',
    );
    expect(beats.single.rate, lessThan(1));
    expect(beats.single.pause, Duration.zero);
  });
  test('Consistent cues remain identical; variable timing remains bounded', () {
    final director = PerformanceDirector();
    final consistent = director.plan(
      'Go.',
      const AppSettings(variableCues: false),
      const VoiceAssignment(),
    );
    expect(consistent.single.pause, Duration.zero);
    expect(consistent.single.rate, 1);
    final variable = director.plan(
      'Go.',
      const AppSettings(),
      const VoiceAssignment(),
      random: Random(4),
    );
    expect(variable.single.rate, inInclusiveRange(.98, 1.02));
    expect(variable.single.pause.inMilliseconds, inInclusiveRange(20, 99));
  });
  test('Multi-scene runs preserve entry identities and scene boundaries', () {
    final line = ScriptEntry(
      id: 'line',
      type: EntryType.dialogue,
      text: 'Wait.',
      character: 'A',
    );
    final scene = combineScenes([
      Scene(id: 'first', heading: 'First', entries: [line]),
      Scene(
        id: 'second',
        heading: 'Second',
        entries: [line.copyWith(text: 'Go.')],
      ),
    ]);
    expect(
      scene.entries
          .where((e) => e.type == EntryType.sceneHeading)
          .map((e) => e.text),
      ['First', 'Second'],
    );
    expect(scene.dialogue.first, same(line));
  });
}
