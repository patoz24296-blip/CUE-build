import 'dart:math';

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random.secure().nextInt(1 << 32).toRadixString(36)}';

enum EntryType { dialogue, stageDirection, parenthetical, sceneHeading }

enum AccuracyMode { wordPerfect, flexible, loose, improv }

enum PracticeMode { scenePartner, cueDrill, lineDrill, rehearsal }

enum ResponseTiming { fast, natural, patient }

enum LineDisplay { hidden, initials, blurred, onRequest, visible }

enum PartnerDisplay { hidden, visible, current }

enum DirectionPolicy { ignore, display, read }

enum PerformanceStyle { neutral, natural, full }

enum CueReduction { full, sentence, phrase, words }

enum DrillSelection { weakest, imperfect, custom }

enum LineClassification {
  wordPerfect,
  acceptableVariation,
  meaningPreserved,
  significantDeviation,
  wrongLine,
  skippedLine,
}

extension AccuracyLabel on AccuracyMode {
  String get label => ['Word Perfect', 'Flexible', 'Loose', 'Improv'][index];
  String get explanation => [
    'The script, word for word. Punctuation never counts against you.',
    'Room for small wording changes, while keeping the line intact.',
    'Keep the meaning, anchors and intention. Find your own phrasing.',
    'Follow the scene’s essential beats, with room to paraphrase.',
  ][index];
}

extension PracticeLabel on PracticeMode {
  String get label =>
      ['Scene Partner', 'Cue Drill', 'Line Drill', 'Rehearsal'][index];
  String get description => [
    'Someone to read opposite you.',
    'Know what comes before your line.',
    'Spend time with the lines that need it.',
    'A full run. Stay in the scene.',
  ][index];
}

class ScriptEntry {
  const ScriptEntry({
    required this.id,
    required this.type,
    required this.text,
    this.character,
    this.parenthetical = '',
    this.protectedPhrases = const [],
    this.variants = const [],
    this.flaggedVariants = const [],
  });
  final String id;
  final EntryType type;
  final String text;
  final String? character;
  final String parenthetical;
  final List<String> protectedPhrases;
  final List<String> variants;
  final List<String> flaggedVariants;
  bool get isDialogue => type == EntryType.dialogue && character != null;
  bool get isInterrupted => RegExp(r'[—–-]\s*$').hasMatch(text);
  ScriptEntry copyWith({
    String? text,
    String? character,
    EntryType? type,
    String? parenthetical,
    List<String>? protectedPhrases,
    List<String>? variants,
    List<String>? flaggedVariants,
  }) => ScriptEntry(
    id: id,
    type: type ?? this.type,
    text: text ?? this.text,
    character: character ?? this.character,
    parenthetical: parenthetical ?? this.parenthetical,
    protectedPhrases: protectedPhrases ?? this.protectedPhrases,
    variants: variants ?? this.variants,
    flaggedVariants: flaggedVariants ?? this.flaggedVariants,
  );
}

class Scene {
  const Scene({required this.id, required this.heading, required this.entries});
  final String id;
  final String heading;
  final List<ScriptEntry> entries;
  List<ScriptEntry> get dialogue => entries.where((e) => e.isDialogue).toList();
  bool involves(String character) =>
      entries.any((e) => e.character == character);
  Scene copyWith({String? heading, List<ScriptEntry>? entries}) => Scene(
    id: id,
    heading: heading ?? this.heading,
    entries: entries ?? this.entries,
  );
}

class Production {
  const Production({
    required this.id,
    required this.title,
    required this.scenes,
    required this.createdAt,
    this.author = '',
    this.selectedCharacter,
    this.sourceName = '',
    this.sourceFormat = '',
  });
  final String id;
  final String title;
  final String author;
  final List<Scene> scenes;
  final DateTime createdAt;
  final String? selectedCharacter;
  final String sourceName;
  final String sourceFormat;
  List<String> get characters {
    final counts = <String, int>{};
    for (final scene in scenes) {
      for (final line in scene.dialogue) {
        counts.update(line.character!, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  int get lineCount => scenes.fold(0, (n, s) => n + s.dialogue.length);
  Production copyWith({
    String? title,
    List<Scene>? scenes,
    String? selectedCharacter,
  }) => Production(
    id: id,
    title: title ?? this.title,
    author: author,
    scenes: scenes ?? this.scenes,
    createdAt: createdAt,
    selectedCharacter: selectedCharacter ?? this.selectedCharacter,
    sourceName: sourceName,
    sourceFormat: sourceFormat,
  );
}

class LineEvaluation {
  const LineEvaluation({
    required this.accepted,
    required this.textualAccuracy,
    required this.semanticAccuracy,
    required this.classification,
    required this.confidence,
    this.missingWords = const [],
    this.insertedWords = const [],
    this.changedWords = const [],
    this.protectedWordViolations = const [],
    this.meaningChanged = false,
    this.reason = '',
    this.usedSemanticModel = false,
  });
  final bool accepted;
  final double textualAccuracy;
  // Null means no semantic model was needed/available; never fabricate a score.
  final double? semanticAccuracy;
  final List<String> missingWords;
  final List<String> insertedWords;
  final List<String> changedWords;
  final List<String> protectedWordViolations;
  final bool meaningChanged;
  final double confidence;
  final LineClassification classification;
  final String reason;
  final bool usedSemanticModel;
}

class LineAttempt {
  const LineAttempt({
    required this.id,
    required this.line,
    required this.transcript,
    required this.evaluation,
    required this.responseDelay,
    required this.duration,
    required this.hints,
    required this.at,
    this.interrupted = false,
    this.cueRequests = const [],
  });
  final List<CueRequest> cueRequests;
  final String id;
  final ScriptEntry line;
  final String transcript;
  final LineEvaluation evaluation;
  final Duration responseDelay;
  final Duration duration;
  final int hints;
  final DateTime at;
  final bool interrupted;
}

class CueRequest {
  const CueRequest(this.level, this.at);
  final int level;
  final DateTime at;
}

class RehearsalReport {
  const RehearsalReport({
    required this.id,
    required this.productionId,
    required this.sceneId,
    required this.character,
    required this.mode,
    required this.practice,
    required this.startedAt,
    required this.finishedAt,
    required this.attempts,
    this.completed = true,
    this.sceneIds = const [],
  });
  final String id;
  final String productionId;
  final String sceneId;
  final String character;
  final AccuracyMode mode;
  final PracticeMode practice;
  final DateTime startedAt;
  final DateTime finishedAt;
  final List<LineAttempt> attempts;
  final bool completed;
  final List<String> sceneIds;
  double get accuracy => attempts.isEmpty
      ? 0
      : attempts.fold<double>(0, (n, a) => n + a.evaluation.textualAccuracy) /
            attempts.length;
  int get hintCount => attempts.fold(0, (n, a) => n + a.hints);
  int get perfect => attempts
      .where(
        (a) => a.evaluation.classification == LineClassification.wordPerfect,
      )
      .length;
  int get accepted => attempts.where((a) => a.evaluation.accepted).length;
  List<LineAttempt> get weak => attempts
      .where(
        (a) =>
            !a.evaluation.accepted ||
            a.hints > 0 ||
            a.responseDelay.inSeconds > 6 ||
            a.evaluation.confidence < .65,
      )
      .toList();
}

class VoiceAssignment {
  const VoiceAssignment({this.speaker = 0, this.rate = 1, this.direction = ''});
  final int speaker;
  final double rate;
  final String direction;
}

class AppSettings {
  const AppSettings({
    this.accuracy = AccuracyMode.flexible,
    this.timing = ResponseTiming.natural,
    this.myLines = LineDisplay.hidden,
    this.partnerLines = PartnerDisplay.current,
    this.stageDirections = DirectionPolicy.display,
    this.parentheticals = DirectionPolicy.display,
    this.performance = PerformanceStyle.natural,
    this.variableCues = true,
    this.interruptions = false,
    this.autoNext = true,
    this.spokenHints = true,
    this.contractionsEquivalent = true,
    this.recordAudio = false,
    this.theme = 'system',
    this.textScale = 1,
    this.speechRate = 1,
    this.sensitivity = .5,
    this.language = 'en',
    this.microphoneId,
    this.speechModel = 'moonshine',
    this.autoDeleteRecordings = true,
    this.recordingRetentionDays = 7,
    this.pauseMultiplier = 1,
    this.hintCommand = 'CUE please',
    this.rehearsalSounds = false,
    this.modelStoragePath = '',
  });
  final AccuracyMode accuracy;
  final ResponseTiming timing;
  final LineDisplay myLines;
  final PartnerDisplay partnerLines;
  final DirectionPolicy stageDirections;
  final DirectionPolicy parentheticals;
  final PerformanceStyle performance;
  final bool variableCues,
      interruptions,
      autoNext,
      spokenHints,
      contractionsEquivalent,
      recordAudio,
      autoDeleteRecordings;
  final int recordingRetentionDays;
  final double pauseMultiplier;
  final String hintCommand;
  final String modelStoragePath;
  final bool rehearsalSounds;
  final String theme, language, speechModel;
  final String? microphoneId;
  final double textScale, speechRate, sensitivity;
  String get effectiveSpeechModel =>
      language != 'en' && speechModel != 'whisper-multilingual'
      ? 'whisper-base-multilingual'
      : speechModel;
  String get verificationSpeechModel => language != 'en'
      ? effectiveSpeechModel == 'whisper-multilingual'
            ? 'whisper-base-multilingual'
            : 'whisper-multilingual'
      : effectiveSpeechModel == 'moonshine'
      ? 'whisper-base'
      : 'moonshine';
  Map<String, Object?> toMap() => {
    'accuracy': accuracy.index,
    'timing': timing.index,
    'myLines': myLines.index,
    'partnerLines': partnerLines.index,
    'stageDirections': stageDirections.index,
    'parentheticals': parentheticals.index,
    'performance': performance.index,
    'variableCues': variableCues,
    'interruptions': interruptions,
    'autoNext': autoNext,
    'spokenHints': spokenHints,
    'contractionsEquivalent': contractionsEquivalent,
    'recordAudio': recordAudio,
    'theme': theme,
    'textScale': textScale,
    'speechRate': speechRate,
    'sensitivity': sensitivity,
    'language': language,
    'microphoneId': microphoneId,
    'speechModel': speechModel,
    'autoDeleteRecordings': autoDeleteRecordings,
    'recordingRetentionDays': recordingRetentionDays,
    'pauseMultiplier': pauseMultiplier,
    'hintCommand': hintCommand,
    'rehearsalSounds': rehearsalSounds,
    'modelStoragePath': modelStoragePath,
    'audioRevision': 2,
  };
  factory AppSettings.fromMap(Map<String, dynamic> m) {
    T pick<T>(List<T> values, String key, T fallback) {
      final index = m[key];
      return index is int && index >= 0 && index < values.length
          ? values[index]
          : fallback;
    }

    return AppSettings(
      accuracy: pick(AccuracyMode.values, 'accuracy', AccuracyMode.flexible),
      timing: pick(ResponseTiming.values, 'timing', ResponseTiming.natural),
      myLines: pick(LineDisplay.values, 'myLines', LineDisplay.hidden),
      partnerLines: pick(
        PartnerDisplay.values,
        'partnerLines',
        PartnerDisplay.current,
      ),
      stageDirections: pick(
        DirectionPolicy.values,
        'stageDirections',
        DirectionPolicy.display,
      ),
      parentheticals: pick(
        DirectionPolicy.values,
        'parentheticals',
        DirectionPolicy.display,
      ),
      performance: pick(
        PerformanceStyle.values,
        'performance',
        PerformanceStyle.natural,
      ),
      variableCues: m['variableCues'] as bool? ?? true,
      interruptions: m['interruptions'] as bool? ?? false,
      autoNext: m['autoNext'] as bool? ?? true,
      spokenHints: m['spokenHints'] as bool? ?? true,
      contractionsEquivalent: m['contractionsEquivalent'] as bool? ?? true,
      recordAudio: m['recordAudio'] as bool? ?? false,
      theme: m['theme'] as String? ?? 'system',
      textScale: (m['textScale'] as num?)?.toDouble() ?? 1,
      speechRate: (m['speechRate'] as num?)?.toDouble() ?? 1,
      sensitivity: (m['sensitivity'] as num?)?.toDouble() ?? .5,
      language: m['language'] as String? ?? 'en',
      microphoneId: m['microphoneId'] as String?,
      speechModel: m['audioRevision'] != 2 && m['speechModel'] == 'whisper-tiny'
          ? 'moonshine'
          : m['speechModel'] as String? ?? 'moonshine',
      autoDeleteRecordings: m['autoDeleteRecordings'] as bool? ?? true,
      recordingRetentionDays: (m['recordingRetentionDays'] as int? ?? 7).clamp(
        0,
        365,
      ),
      pauseMultiplier: ((m['pauseMultiplier'] as num?)?.toDouble() ?? 1).clamp(
        .5,
        3,
      ),
      hintCommand: m['hintCommand'] as String? ?? 'CUE please',
      rehearsalSounds: m['rehearsalSounds'] as bool? ?? false,
      modelStoragePath: m['modelStoragePath'] as String? ?? '',
    );
  }
  AppSettings change(String key, dynamic value) =>
      AppSettings.fromMap({...toMap(), key: value});
}
