import 'dart:typed_data';
import 'models.dart';

class Transcript {
  const Transcript(this.text, {this.confidence});
  final String text;
  final double? confidence;
}

abstract interface class SpeechRecognitionProvider {
  Future<Transcript> transcribe(Float32List samples, {int sampleRate = 16000});
  Future<void> dispose();
}

abstract interface class VoiceActivityProvider {
  Future<bool> detect(Float32List frame);
  Future<void> reset();
}

abstract interface class TextToSpeechProvider {
  Future<void> speak(
    String text, {
    int voice = 0,
    double speed = 1,
    double volume = 1,
  });
  Future<void> stop();
  Future<void> preload(String text, {int voice = 0, double speed = 1});
  Future<void> dispose();
}

class SemanticJudgment {
  const SemanticJudgment({
    required this.preserved,
    required this.confidence,
    required this.reason,
  });
  final bool preserved;
  final double confidence;
  final String reason;
}

abstract interface class LanguageModelProvider {
  Future<SemanticJudgment?> judge({
    required String expected,
    required String spoken,
    required List<String> anchors,
    required AccuracyMode mode,
  });
  Future<void> dispose();
}

abstract interface class EmbeddingProvider {
  Future<List<double>> embed(String text);
  Future<void> dispose();
}

abstract interface class ScriptParserProvider {
  Production parse(String text, {required String filename});
}

class SpeechEvent {
  const SpeechEvent({
    required this.text,
    required this.speaking,
    required this.silence,
    this.confidence,
    this.startedAt,
  });
  final String text;
  final bool speaking;
  final Duration silence;
  final double? confidence;
  final DateTime? startedAt;
}

abstract interface class ListeningProvider {
  Stream<SpeechEvent> get events;
  Future<void> start();
  Future<void> reset();
  Future<void> stop();
  Future<void> dispose();
}

/// A second acoustic model checks the same audio, without being given the script.
abstract interface class RecognitionVerification {
  Future<Transcript?> verifyUtterance();
}
