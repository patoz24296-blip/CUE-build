import 'dart:math';
import 'models.dart';

class SpeechBeat {
  const SpeechBeat(this.text, this.rate, this.volume, this.pause);
  final String text;
  final double rate, volume;
  final Duration pause;
}

/// Converts practical acting directions into controls supported by local TTS.
class PerformanceDirector {
  List<SpeechBeat> plan(
    String text,
    AppSettings settings,
    VoiceAssignment voice, {
    String sceneDirection = '',
    String parenthetical = '',
    Random? random,
  }) {
    final direction =
        '${voice.direction} $sceneDirection ${settings.parentheticals == DirectionPolicy.read ? parenthetical : ''}'
            .toLowerCase();
    var rate = settings.speechRate * voice.rate;
    var volume = 1.0;
    var before = 0;
    if (RegExp(r'slow|patient|sad|tired|quiet|longer').hasMatch(direction)) {
      rate *= .88;
    }
    if (RegExp(
      r'fast|quick|excited|urgent|annoyed|angry',
    ).hasMatch(direction)) {
      rate *= 1.12;
    }
    if (RegExp(r'quiet|soft|whisper|gentle').hasMatch(direction)) volume = .65;
    if (RegExp(r'pause|hesitat|longer|wait').hasMatch(direction)) before = 650;
    final explicitPause = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:seconds?|s)\b',
    ).firstMatch(direction);
    if (explicitPause != null) {
      before = (double.parse(explicitPause[1]!) * 1000).round().clamp(0, 10000);
    }
    final rng = random ?? Random();
    if (settings.variableCues &&
        settings.performance != PerformanceStyle.neutral) {
      before += 20 + rng.nextInt(80);
      rate *= .98 + rng.nextDouble() * .04;
    }
    final full = settings.performance == PerformanceStyle.full;
    // Preserve sentence context so the neural model handles punctuation and
    // prosody continuously, rather than restarting at every comma.
    final parts = [text];
    return List.generate(parts.length, (i) {
      final emphasis =
          full &&
          (parts[i].endsWith('!') ||
              RegExp(
                r'\b(never|always|must|now)\b',
                caseSensitive: false,
              ).hasMatch(parts[i]));
      return SpeechBeat(
        parts[i],
        (rate * (emphasis ? .94 : 1)).clamp(.55, 1.6),
        volume,
        Duration(
          milliseconds: i == 0
              ? before
              : (parts[i - 1].endsWith(',') ? 100 : 220),
        ),
      );
    });
  }
}

Scene combineScenes(List<Scene> scenes) {
  assert(scenes.isNotEmpty);
  return Scene(
    id: scenes.first.id,
    heading: 'Full rehearsal · ${scenes.length} scenes',
    entries: [
      for (final scene in scenes) ...[
        ScriptEntry(
          id: 'boundary-${scene.id}',
          type: EntryType.sceneHeading,
          text: scene.heading,
        ),
        ...scene.entries,
      ],
    ],
  );
}
