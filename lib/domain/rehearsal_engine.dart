import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'models.dart';
import 'providers.dart';
import 'evaluator.dart';
import 'performance.dart';

enum RehearsalState {
  ready,
  speaking,
  listening,
  evaluating,
  paused,
  finished,
  error,
}

String progressiveHint(String text, int level) {
  final words = text.split(RegExp(r'\s+'));
  return words
      .take(
        level >= 3
            ? words.length
            : level == 2
            ? max(4, (words.length / 2).ceil())
            : min(3, words.length),
      )
      .join(' ');
}

String reduceCue(String text, CueReduction reduction) {
  switch (reduction) {
    case CueReduction.full:
      return text;
    case CueReduction.sentence:
      return text.split(RegExp(r'(?<=[.!?])\s+')).last;
    case CueReduction.phrase:
      return text.split(RegExp(r'[,;—]\s*')).last;
    case CueReduction.words:
      final words = text.split(RegExp(r'\s+'));
      return words.skip(max(0, words.length - 4)).join(' ');
  }
}

class CompletionPolicy {
  const CompletionPolicy();
  bool isUnfinishedPrefix(
    ScriptEntry line,
    String text,
    LineEvaluator evaluator,
  ) {
    final expected = evaluator.normalizer.tokens(line.text);
    final actual = evaluator.normalizer.tokens(text);
    return actual.isNotEmpty &&
        actual.length < expected.length &&
        listEquals(actual, expected.take(actual.length).toList());
  }

  bool complete(
    ScriptEntry line,
    SpeechEvent event,
    ResponseTiming timing,
    LineEvaluator evaluator, [
    double pauseMultiplier = 1,
  ]) {
    if (event.speaking || event.text.trim().isEmpty) return false;
    final expected = evaluator.normalizer.tokens(line.text);
    final actual = evaluator.normalizer.tokens(event.text);
    if (isUnfinishedPrefix(line, event.text, evaluator)) return false;
    final matched = evaluator.diff(expected, actual).matches;
    final completeEnding =
        expected.isNotEmpty &&
        actual.isNotEmpty &&
        expected.last == actual.last &&
        matched / expected.length >= .85;
    final delay = completeEnding
        ? [280, 550, 1100][timing.index]
        : [650, 1200, 2200][timing.index];
    return event.silence.inMilliseconds >= delay * pauseMultiplier &&
        evaluator.hasEnoughContent(line, event.text);
  }
}

class RehearsalEngine extends ChangeNotifier {
  RehearsalEngine({
    required this.production,
    required this.scene,
    required this.character,
    required this.settings,
    required this.listener,
    required this.tts,
    required this.evaluator,
    this.practice = PracticeMode.scenePartner,
    this.cueReduction = CueReduction.full,
    this.start = 0,
    int? end,
    this.loop = false,
    this.drillIds = const {},
    this.voices = const {},
    this.sceneIds = const [],
    this.sceneDirections = const {},
  }) : end = end ?? scene.entries.length - 1;
  Production production;
  Scene scene;
  final String character;
  final AppSettings settings;
  final ListeningProvider listener;
  final TextToSpeechProvider tts;
  final LineEvaluator evaluator;
  PracticeMode practice;
  final CueReduction cueReduction;
  final int start, end;
  final bool loop;
  Set<String> drillIds;
  final Map<String, VoiceAssignment> voices;
  final List<String> sceneIds;
  final Map<String, String> sceneDirections;
  String? _activeSceneId;
  String get sceneHeading {
    final boundaries = scene.entries
        .take(_index + 1)
        .where((e) => e.type == EntryType.sceneHeading);
    return boundaries.lastOrNull?.text ?? scene.heading;
  }

  RehearsalState state = RehearsalState.ready;
  ScriptEntry? current;
  ScriptEntry? partner;
  String transcript = '', hint = '', error = '';
  String recognitionAlternative = '', recognitionNotice = '';
  bool _reviewingHearing = false;
  bool get reviewingHearing => _reviewingHearing;
  String stageDirection = '';
  final attempts = <LineAttempt>[];
  final _cues = <CueRequest>[];
  int _index = 0, _generation = 0;
  bool _disposed = false, _handling = false;
  DateTime _started = DateTime.now(), _listenAt = DateTime.now();
  DateTime? _speechAt;
  StreamSubscription<SpeechEvent>? _subscription;
  SpeechEvent? _bargeIn;
  bool _checking = false, _speakingNow = false;
  String _checkedText = '';
  int _performanceSeed = 0;
  String? _turnId;

  Iterable<ScriptEntry> get _actorLines => scene.entries
      .skip(max(0, start))
      .take(max(0, end - start + 1))
      .where(
        (e) =>
            e.isDialogue &&
            e.character == character &&
            (practice != PracticeMode.lineDrill || drillIds.contains(e.id)),
      );
  int get actorLineCount => _actorLines.length;
  int get actorLineNumber {
    final passed = scene.entries
        .skip(max(0, start))
        .take(max(0, _index - start))
        .where(
          (e) =>
              e.isDialogue &&
              e.character == character &&
              (practice != PracticeMode.lineDrill || drillIds.contains(e.id)),
        )
        .length;
    return min(passed + 1, actorLineCount);
  }

  void _publish(RehearsalState next) {
    state = next;
    if (!_disposed) notifyListeners();
  }

  Future<void> begin({bool paused = false}) async {
    if (start < 0 ||
        end < start ||
        end >= scene.entries.length ||
        !scene.entries
            .sublist(start, end + 1)
            .any(
              (e) =>
                  e.isDialogue &&
                  e.character == character &&
                  (practice != PracticeMode.lineDrill ||
                      drillIds.contains(e.id)),
            )) {
      _fail(
        StateError(
          'Choose a rehearsal range and drill set containing one of your lines.',
        ),
      );
      return;
    }
    _started = DateTime.now();
    _performanceSeed = Random().nextInt(1 << 30);
    _index = start;
    final boundary = scene.entries
        .take(start + 1)
        .where((e) => e.id.startsWith('boundary-'))
        .lastOrNull;
    _activeSceneId = boundary?.id.substring('boundary-'.length);
    attempts.clear();
    current = null;
    partner = null;
    transcript = '';
    recognitionAlternative = '';
    recognitionNotice = '';
    hint = '';
    _turnId = null;
    stageDirection = '';
    _subscription ??= listener.events.listen(
      _onSpeech,
      onError: (Object e) => _fail(e),
    );
    final generation = ++_generation;
    if (paused) {
      _publish(RehearsalState.paused);
    } else {
      await _advance(generation);
    }
  }

  Future<void> _advance(int generation) async {
    try {
      await listener.stop();
      while (!_disposed &&
          generation == _generation &&
          _index <= end &&
          _index < scene.entries.length) {
        final line = scene.entries[_index];
        current = line;
        if (line.type == EntryType.stageDirection &&
            settings.stageDirections != DirectionPolicy.ignore) {
          stageDirection = line.text;
        }
        if (line.id.startsWith('boundary-')) {
          _activeSceneId = line.id.substring('boundary-'.length);
          _index++;
          continue;
        }
        if (line.isDialogue && line.character == character) {
          if (practice == PracticeMode.lineDrill &&
              !drillIds.contains(line.id)) {
            _index++;
            continue;
          }
          if (practice == PracticeMode.lineDrill ||
              practice == PracticeMode.cueDrill) {
            final previous = scene.entries
                .take(_index)
                .where((e) => e.isDialogue && e.character != character)
                .lastOrNull;
            if (previous != null) {
              await _speak(previous, generation, reduce: true);
            }
          }
          if (generation != _generation || _disposed) return;
          transcript = '';
          recognitionAlternative = '';
          recognitionNotice = '';
          _checkedText = '';
          if (_turnId != line.id) {
            hint = '';
            _cues.clear();
            _turnId = line.id;
          }
          final interruption = _bargeIn;
          _bargeIn = null;
          _speechAt = interruption?.startedAt;
          _listenAt = DateTime.now();
          if (interruption == null) await listener.reset();
          if (generation != _generation || _disposed) return;
          _publish(RehearsalState.listening);
          await listener.start();
          if (generation != _generation || _disposed) return;
          if (interruption != null) await _onSpeech(interruption);
          final nextPartner = scene.entries
              .skip(_index + 1)
              .where((e) => e.isDialogue && e.character != character)
              .firstOrNull;
          if (nextPartner != null) {
            final voice =
                voices[nextPartner.character] ?? const VoiceAssignment();
            final plan = PerformanceDirector().plan(
              nextPartner.text,
              settings,
              voice,
              parenthetical: nextPartner.parenthetical,
              sceneDirection: sceneDirections[_activeSceneId ?? scene.id] ?? '',
              random: Random(
                nextPartner.text.hashCode ^ voice.speaker ^ _performanceSeed,
              ),
            );
            for (final beat in plan) {
              unawaited(
                tts
                    .preload(beat.text, voice: voice.speaker, speed: beat.rate)
                    .catchError((Object _) {}),
              );
            }
          }
          return;
        }
        if (practice != PracticeMode.lineDrill &&
            practice != PracticeMode.cueDrill &&
            (line.isDialogue ||
                settings.stageDirections == DirectionPolicy.read)) {
          await _speak(line, generation);
        }
        _index++;
      }
      if (generation != _generation || _disposed) return;
      current = null;
      if (loop) {
        _index = start;
        await _advance(generation);
      } else {
        _publish(RehearsalState.finished);
      }
    } catch (e) {
      if (generation == _generation) _fail(e);
    }
  }

  Future<void> _speak(
    ScriptEntry line,
    int generation, {
    bool reduce = false,
  }) async {
    if (generation != _generation) return;
    partner = line;
    _publish(RehearsalState.speaking);
    final voice = voices[line.character] ?? const VoiceAssignment();
    final canOverlap =
        settings.interruptions &&
        !reduce &&
        line.isDialogue &&
        _index + 1 < scene.entries.length &&
        scene.entries[_index + 1].character == character;
    if (canOverlap) {
      await listener.reset();
      await listener.start();
    }
    final beats = PerformanceDirector().plan(
      reduce ? reduceCue(line.text, cueReduction) : line.text,
      settings,
      voice,
      sceneDirection: sceneDirections[_activeSceneId ?? scene.id] ?? '',
      parenthetical: line.parenthetical,
      random: Random(
        (reduce ? reduceCue(line.text, cueReduction) : line.text).hashCode ^
            voice.speaker ^
            _performanceSeed,
      ),
    );
    for (final beat in beats) {
      await Future<void>.delayed(beat.pause);
      if (generation != _generation || _bargeIn != null) break;
      await tts.speak(
        beat.text,
        voice: voice.speaker,
        speed: beat.rate,
        volume: beat.volume,
      );
    }
    if (canOverlap && _bargeIn == null) await listener.stop();
  }

  Future<void> _onSpeech(SpeechEvent event) async {
    if (_disposed || _handling || _reviewingHearing) return;
    if (state == RehearsalState.speaking &&
        settings.interruptions &&
        _index + 1 < scene.entries.length &&
        partner != null) {
      final actor = scene.entries[_index + 1];
      if (actor.character == character && event.text.trim().isNotEmpty) {
        final actual = evaluator.normalizer.tokens(event.text);
        final actorScore = evaluator.bagSimilarity(
          evaluator.normalizer.tokens(actor.text),
          actual,
        );
        final partnerScore = evaluator.bagSimilarity(
          evaluator.normalizer.tokens(partner!.text),
          actual,
        );
        // VAD alone cannot identify who spoke. Require actor-line evidence
        // that clearly beats speaker echo before cutting the partner off.
        if (actorScore >= .65 && actorScore > partnerScore + .25) {
          _bargeIn = event;
          await tts.stop();
        }
      }
      return;
    }
    if (state != RehearsalState.listening || recognitionNotice.isNotEmpty) {
      return;
    }
    transcript = event.text;
    _speakingNow = event.speaking;
    if (event.speaking) _speechAt ??= event.startedAt ?? DateTime.now();
    notifyListeners();
    final normalized = evaluator.normalizer.tokens(event.text).join(' ');
    // Exact command avoids triggering a hint when dialogue merely contains "line".
    final commands = {
      evaluator.normalizer.tokens(settings.hintCommand).join(' '),
    };
    if (commands.contains('cue please')) {
      commands.addAll({'queue please', 'q please'});
    }
    if (!event.speaking && commands.contains(normalized)) {
      await requestHint();
      return;
    }
    // A pause inside the scripted line must not enter the looser meaning or
    // independent-recognizer path either. The actor can still finish manually.
    if (current != null &&
        const CompletionPolicy().isUnfinishedPrefix(
          current!,
          event.text,
          evaluator,
        )) {
      return;
    }
    if (current != null &&
        const CompletionPolicy().complete(
          current!,
          event,
          settings.timing,
          evaluator,
          settings.pauseMultiplier,
        )) {
      await submit(event.text, confidence: event.confidence);
    } else if (!event.speaking &&
        !_checking &&
        current != null &&
        event.text.trim().isNotEmpty &&
        event.text != _checkedText &&
        event.silence.inMilliseconds >=
            [600, 1400, 2600][settings.timing.index] *
                settings.pauseMultiplier &&
        (listener is RecognitionVerification ||
            settings.accuracy == AccuracyMode.loose ||
            settings.accuracy == AccuracyMode.improv)) {
      _checking = true;
      final generation = _generation;
      final line = current!;
      final text = event.text;
      try {
        final result = await evaluator.evaluate(
          line: line,
          spoken: text,
          mode: settings.accuracy,
          names: production.characters,
          asrConfidence: event.confidence,
        );
        if (generation == _generation &&
            transcript == text &&
            !_speakingNow &&
            state == RehearsalState.listening) {
          _checkedText = text;
          if (result.accepted) {
            await submit(text, confidence: event.confidence, evaluated: result);
          } else if (listener is RecognitionVerification &&
              evaluator.normalizer.tokens(text).length >=
                  max(
                    1,
                    (evaluator.normalizer.tokens(line.text).length * .6).ceil(),
                  )) {
            final checked = await (listener as RecognitionVerification)
                .verifyUtterance();
            if (checked != null &&
                checked.text.trim().isNotEmpty &&
                generation == _generation &&
                transcript == text &&
                !_speakingNow &&
                state == RehearsalState.listening) {
              final second = await evaluator.evaluate(
                line: line,
                spoken: checked.text,
                mode: settings.accuracy,
                names: production.characters,
                contractionsEquivalent: settings.contractionsEquivalent,
              );
              if (second.accepted &&
                  !_disposed &&
                  generation == _generation &&
                  transcript == text &&
                  !_speakingNow &&
                  state == RehearsalState.listening) {
                await listener.stop();
                if (_disposed || generation != _generation) return;
                recognitionAlternative = checked.text;
                recognitionNotice =
                    'The second hearing matches your script. Confirm it or try the line again.';
                notifyListeners();
              }
            }
          }
        }
      } catch (_) {
        // Optional verification must not terminate a usable rehearsal.
        if (!_disposed && generation == _generation) _checkedText = text;
      } finally {
        _checking = false;
      }
    }
  }

  Future<void> submit(
    String text, {
    double? confidence,
    bool skipped = false,
    LineEvaluation? evaluated,
  }) async {
    if (state != RehearsalState.listening || current == null || _handling) {
      return;
    }
    if (!skipped && evaluated == null && recognitionNotice.isNotEmpty) return;
    _handling = true;
    final generation = _generation;
    final line = current!;
    _publish(RehearsalState.evaluating);
    try {
      await listener.stop();
      var result =
          evaluated ??
          await evaluator.evaluate(
            line: line,
            spoken: skipped ? '' : text,
            mode: settings.accuracy,
            names: production.characters,
            contractionsEquivalent: settings.contractionsEquivalent,
            asrConfidence: confidence,
          );
      if (_disposed || generation != _generation) return;
      if (!skipped &&
          !result.accepted &&
          evaluated == null &&
          listener is RecognitionVerification) {
        Transcript? checked;
        try {
          checked = await (listener as RecognitionVerification)
              .verifyUtterance();
        } catch (_) {
          // Keep the first hearing available when an optional model fails.
        }
        if (_disposed || generation != _generation) return;
        final second = checked?.text.trim() ?? '';
        if (second.isEmpty ||
            evaluator.normalizer.tokens(second).join(' ') !=
                evaluator.normalizer.tokens(text).join(' ')) {
          transcript = text;
          recognitionAlternative = second;
          recognitionNotice = second.isEmpty
              ? 'Only one hearing is available. Check what CUE heard before counting a mistake.'
              : 'Two local recognizers heard different words. Check the hearing before counting a mistake.';
          _publish(RehearsalState.listening);
          return;
        }
      }
      final now = DateTime.now();
      attempts.add(
        LineAttempt(
          id: newId(),
          line: line,
          transcript: text,
          evaluation: result,
          responseDelay: Duration(
            milliseconds: max(
              0,
              (_speechAt ?? now).difference(_listenAt).inMilliseconds,
            ),
          ),
          duration: now.difference(_speechAt ?? _listenAt),
          hints: _cues.length,
          cueRequests: List.of(_cues),
          at: now,
        ),
      );
      if (practice == PracticeMode.lineDrill && !result.accepted && !skipped) {
        _cues.clear();
        _publish(RehearsalState.listening);
        await requestHint(full: true);
        return;
      }
      _index++;
      _turnId = null;
      _handling = false;
      if (settings.autoNext || skipped) {
        await _advance(generation);
      } else {
        _publish(RehearsalState.paused);
      }
    } catch (e) {
      if (generation == _generation) _fail(e);
    } finally {
      _handling = false;
    }
  }

  Future<void> useSecondHearing() => _confirmHearing(second: true);

  Future<void> useFirstHearing() => _confirmHearing(second: false);

  Future<void> _confirmHearing({required bool second}) async {
    if (_disposed ||
        _reviewingHearing ||
        _handling ||
        state != RehearsalState.listening ||
        recognitionNotice.isEmpty ||
        current == null) {
      return;
    }
    final text = second ? recognitionAlternative : transcript;
    if (text.isEmpty) return;
    final generation = _generation;
    final line = current!;
    LineEvaluation? confirmed;
    _reviewingHearing = true;
    notifyListeners();
    try {
      final result = await evaluator.evaluate(
        line: line,
        spoken: text,
        mode: settings.accuracy,
        names: production.characters,
        contractionsEquivalent: settings.contractionsEquivalent,
      );
      if (_disposed ||
          generation != _generation ||
          state != RehearsalState.listening ||
          current?.id != line.id) {
        return;
      }
      confirmed = result;
    } catch (e) {
      if (!_disposed && generation == _generation) _fail(e);
    } finally {
      _reviewingHearing = false;
      if (!_disposed) notifyListeners();
    }
    if (confirmed != null && !_disposed && generation == _generation) {
      recognitionAlternative = '';
      recognitionNotice = '';
      await submit(text, evaluated: confirmed);
    }
  }

  Future<void> retryHearing() async {
    if (_disposed ||
        _reviewingHearing ||
        _handling ||
        state != RehearsalState.listening ||
        current == null) {
      return;
    }
    final generation = ++_generation;
    _reviewingHearing = true;
    notifyListeners();
    try {
      await listener.stop();
      if (_disposed || generation != _generation) return;
      await listener.reset();
      if (_disposed || generation != _generation) return;
      recognitionAlternative = '';
      recognitionNotice = '';
      transcript = '';
      _checkedText = '';
      _speechAt = null;
      _speakingNow = false;
      _listenAt = DateTime.now();
      await listener.start();
    } catch (e) {
      if (!_disposed && generation == _generation) _fail(e);
    } finally {
      _reviewingHearing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> requestHint({bool full = false}) async {
    if (_disposed ||
        _reviewingHearing ||
        recognitionNotice.isNotEmpty ||
        state != RehearsalState.listening ||
        current == null) {
      return;
    }
    final generation = ++_generation;
    final level = full ? 3 : min(3, _cues.length + 1);
    _cues.add(CueRequest(level, DateTime.now()));
    hint = progressiveHint(current!.text, level);
    try {
      await listener.stop();
      _publish(RehearsalState.speaking);
      if (settings.spokenHints) await tts.speak(hint, voice: 3);
      if (_disposed || generation != _generation) return;
      await listener.reset();
      transcript = '';
      _speechAt = null;
      _listenAt = DateTime.now();
      _publish(RehearsalState.listening);
      await listener.start();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> pause() async {
    ++_generation;
    _bargeIn = null;
    _publish(RehearsalState.paused);
    await listener.stop();
    await tts.stop();
  }

  Future<void> resume() async {
    if (state == RehearsalState.paused || state == RehearsalState.error) {
      await _advance(++_generation);
    }
  }

  void _fail(Object e) {
    if (_disposed) return;
    error = e.toString();
    _publish(RehearsalState.error);
    unawaited(listener.stop());
    unawaited(tts.stop());
  }

  RehearsalReport report({bool? completed}) {
    final saved = List<LineAttempt>.of(attempts);
    final line = current;
    if (line != null &&
        line.character == character &&
        _turnId == line.id &&
        (_cues.isNotEmpty || transcript.trim().isNotEmpty)) {
      final now = DateTime.now();
      saved.add(
        LineAttempt(
          id: newId(),
          line: line,
          transcript: transcript,
          evaluation: const LineEvaluation(
            accepted: false,
            textualAccuracy: 0,
            semanticAccuracy: null,
            classification: LineClassification.skippedLine,
            confidence: 0,
            reason: 'Rehearsal ended before this line was evaluated.',
          ),
          responseDelay: Duration(
            milliseconds: max(
              0,
              (_speechAt ?? now).difference(_listenAt).inMilliseconds,
            ),
          ),
          duration: now.difference(_speechAt ?? _listenAt),
          hints: _cues.length,
          cueRequests: List.of(_cues),
          at: now,
        ),
      );
    }
    return RehearsalReport(
      id: newId(),
      productionId: production.id,
      sceneId: scene.id,
      character: character,
      mode: settings.accuracy,
      practice: practice,
      startedAt: _started,
      finishedAt: DateTime.now(),
      attempts: saved,
      completed: completed ?? state == RehearsalState.finished,
      sceneIds: sceneIds.isEmpty ? [scene.id] : sceneIds,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_subscription?.cancel());
    unawaited(listener.dispose());
    unawaited(tts.dispose());
    super.dispose();
  }
}
