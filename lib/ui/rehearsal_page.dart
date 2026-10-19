import 'dart:async';
import 'dart:ui';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/app_controller.dart';
import '../domain/models.dart';
import '../domain/providers.dart';
import '../domain/evaluator.dart';
import '../domain/rehearsal_engine.dart';
import '../services/local_audio.dart';
import '../services/semantic.dart';
import '../services/session_recording.dart';
import '../domain/script_parser.dart';
import '../domain/performance.dart';
import '../domain/voice_catalog.dart';
import 'results_view.dart';
import 'recordings_page.dart';
import 'theme.dart';
import 'script_follow_view.dart';

class RehearsalPage extends StatefulWidget {
  const RehearsalPage({
    super.key,
    required this.controller,
    required this.production,
    required this.scene,
    required this.settings,
    this.practice = PracticeMode.scenePartner,
    this.start = 0,
    this.end,
    this.loop = false,
    this.cueReduction = CueReduction.full,
    this.drillIds = const {},
    this.engineFactory,
    this.sceneIds = const [],
    this.followScript = false,
  });
  final AppController controller;
  final Production production;
  final Scene scene;
  final List<String> sceneIds;
  final bool followScript;
  final AppSettings settings;
  final PracticeMode practice;
  final int start;
  final int? end;
  final bool loop;
  final CueReduction cueReduction;
  final Set<String> drillIds;
  final Future<RehearsalEngine> Function()? engineFactory;
  @override
  State<RehearsalPage> createState() => _RehearsalPageState();
}

class _RehearsalPageState extends State<RehearsalPage>
    with WidgetsBindingObserver {
  RehearsalEngine? _engine;
  LanguageModelProvider? _meaning;
  EmbeddingProvider? _embeddings;
  SessionRecording? _recording;
  LocalAudioBundle? _bundle;
  int _countdown = 0;
  bool _recordingSaved = false;
  RehearsalReport? _report;
  String? _error;
  bool _saving = false, _loading = true;
  late bool _showScript = widget.followScript;
  String? _audioNotice;
  bool _foreground = true;
  StreamSubscription<AudioInterruptionEvent>? _interruptions;
  StreamSubscription<void>? _unplugged;
  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_create());
  }

  Future<void> _create({PracticeMode? practice, Set<String>? drill}) async {
    if (_recording != null) {
      if (!_recordingSaved) await _recording!.discard();
      _recording!.removeListener(_changed);
      _recording!.dispose();
      _recording = null;
    }
    _recordingSaved = false;
    _engine?.removeListener(_changed);
    _engine?.dispose();
    _engine = null;
    await _meaning?.dispose();
    _meaning = null;
    await _embeddings?.dispose();
    _embeddings = null;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _report = null;
        _saving = false;
      });
    }
    LocalAudioBundle? bundle;
    try {
      RehearsalEngine engine;
      if (widget.engineFactory != null) {
        engine = await widget.engineFactory!();
      } else {
        if (widget.settings.recordAudio &&
            widget.controller.recordings != null) {
          _recording = await SessionRecording.open(
            widget.controller.recordings!.newFile(),
          );
          _recording!.addListener(_changed);
        }
        bundle = await LocalAudioBundle.open(
          widget.controller.models,
          widget.settings,
          await getTemporaryDirectory(),
          recording: _recording,
        );
        _bundle = bundle;
        _audioNotice = bundle.listener.verifier == null
            ? 'Second hearing is unavailable. Uncertain words will need your review; you can retry without counting a mistake.'
            : null;
        final voices = <String, VoiceAssignment>{};
        for (final character in widget.production.characters) {
          final stored = await widget.controller.database.voice(
            widget.production.id,
            character,
          );
          voices[character] = VoiceAssignment(
            speaker: resolveVoice(
              stored.speaker,
              character,
              widget.production.characters.indexOf(character),
              language: widget.settings.language == 'es' ? 'es' : 'en',
            ).speaker,
            rate: stored.rate,
            direction: stored.direction,
          );
        }
        if (widget.controller.models.installed.contains('meaning') &&
            (widget.settings.accuracy == AccuracyMode.loose ||
                widget.settings.accuracy == AccuracyMode.improv)) {
          try {
            _meaning = await BuiltinMeaning.open(
              p.join(
                widget.controller.models.path('meaning'),
                'qwen2.5-0.5b-instruct-q4_k_m.gguf',
              ),
            );
          } catch (_) {
            _meaning = null;
          }
        }
        if (widget.controller.models.installed.contains('embeddings') &&
            (widget.settings.accuracy == AccuracyMode.loose ||
                widget.settings.accuracy == AccuracyMode.improv)) {
          try {
            _embeddings = await BuiltinEmbeddings.open(
              p.join(
                widget.controller.models.path('embeddings'),
                'nomic-embed-text-v1.5.Q4_K_M.gguf',
              ),
            );
          } catch (_) {
            _embeddings = null;
          }
        }
        engine = RehearsalEngine(
          production: widget.production,
          scene: widget.scene,
          character: widget.production.selectedCharacter!,
          settings: widget.settings,
          listener: bundle.listener,
          tts: bundle.tts,
          evaluator: LineEvaluator(
            languageModel: _meaning,
            embeddings: _embeddings,
          ),
          practice: practice ?? widget.practice,
          start: widget.start,
          end: widget.end,
          loop: widget.loop,
          cueReduction: widget.cueReduction,
          drillIds: drill ?? widget.drillIds,
          voices: voices,
          sceneIds: widget.sceneIds,
          sceneDirections: await widget.controller.database.sceneDirections(
            widget.production,
          ),
        );
      }
      if (!mounted) {
        engine.dispose();
        await _meaning?.dispose();
        await _embeddings?.dispose();
        await _recording?.discard();
        return;
      }
      _engine = engine;
      _engine!.addListener(_changed);
      setState(() => _loading = false);
      if (widget.engineFactory == null) {
        final audio = await AudioSession.instance;
        _interruptions ??= audio.interruptionEventStream.listen((event) {
          if (event.begin) unawaited(_engine?.pause());
        });
        _unplugged ??= audio.becomingNoisyEventStream.listen(
          (_) => unawaited(_engine?.pause()),
        );
      }
      if (widget.settings.rehearsalSounds) {
        await SystemSound.play(SystemSoundType.click);
      }
      if (!mounted) return;
      _recording?.resume();
      await _engine!.begin(paused: !_foreground);
    } catch (e) {
      if (_engine == null && bundle != null) {
        await bundle.listener.dispose();
        await bundle.tts.dispose();
      }
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_engine == null) {
      setState(() {});
      return;
    }
    if (_engine!.state == RehearsalState.paused ||
        _engine!.state == RehearsalState.error ||
        _engine!.state == RehearsalState.finished) {
      _recording?.pause();
    } else {
      _recording?.resume();
    }
    setState(() {});
    if (_engine!.state == RehearsalState.finished &&
        !_saving &&
        _report == null) {
      unawaited(_finish());
    }
  }

  Future<void> _finish({bool? completed}) async {
    if (_saving || _report != null || _engine == null) return;
    _saving = true;
    final report = _engine!.report(completed: completed);
    await _engine!.pause();
    try {
      await widget.controller.database.saveReport(report);
      try {
        final recorded = await _recording?.finish();
        if (recorded != null) {
          await widget.controller.recordings?.save(recorded, report.id);
          _recordingSaved = true;
        }
      } catch (e) {
        await _recording?.discard();
        if (mounted) {
          showError(
            context,
            'Your results were saved, but recording could not be saved: $e',
          );
        }
      }
      if (widget.settings.rehearsalSounds) {
        await SystemSound.play(SystemSoundType.click);
      }
      if (mounted) setState(() => _report = report);
      if (mounted) await _reviewVariations();
    } catch (e) {
      if (mounted) {
        _report = report;
        showError(
          context,
          'The run finished, but history could not be saved: $e',
        );
        setState(() {});
      }
    } finally {
      _saving = false;
    }
  }

  Future<void> _reviewVariations() async {
    final candidates = await widget.controller.database.repeatedVariants(
      widget.production.id,
    );
    for (final candidate in candidates.take(3)) {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('A wording you return to'),
          content: SingleChildScrollView(
            child: Text(
              'You have used this wording ${candidate['repetitions']} times:\n\n“${candidate['transcript']}”\n\nScript: “${candidate['original']}”\n\nHow would you like CUE to handle it?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'later'),
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'flag'),
              child: const Text('Keep flagging'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'edit'),
              child: const Text('Edit script'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'accept'),
              child: const Text('Accept variation'),
            ),
          ],
        ),
      );
      if (choice == 'accept') {
        await widget.controller.database.acceptVariation(
          candidate['line_id'] as String,
          candidate['transcript'] as String,
        );
      }
      if (choice == 'flag') {
        await widget.controller.database.dismissVariation(
          candidate['line_id'] as String,
          candidate['normalized'] as String,
        );
      }
      if (choice == 'edit') {
        final production = (await widget.controller.database.productions())
            .firstWhere((p) => p.id == widget.production.id);
        final edited = ScriptEditor().updateEntry(
          production,
          candidate['line_id'] as String,
          production.scenes
              .expand((s) => s.entries)
              .firstWhere((e) => e.id == candidate['line_id'])
              .copyWith(text: candidate['transcript'] as String),
        );
        await widget.controller.save(edited);
      }
    }
  }

  Future<void> _repeat({PracticeMode? practice, Set<String>? drill}) async {
    if (_engine == null || _loading) return;
    setState(() {
      _loading = true;
      _report = null;
      _saving = false;
    });
    try {
      final production = (await widget.controller.database.productions())
          .firstWhere((p) => p.id == widget.production.id);
      final ids = widget.sceneIds.isEmpty ? [widget.scene.id] : widget.sceneIds;
      final scenes = production.scenes
          .where((s) => ids.contains(s.id))
          .toList();
      _engine!.production = production;
      _engine!.scene = scenes.length == 1
          ? scenes.single
          : combineScenes(scenes);
      _engine!.practice = practice ?? widget.practice;
      _engine!.drillIds = drill ?? widget.drillIds;
      _recording?.removeListener(_changed);
      _recording?.dispose();
      _recording = null;
      _recordingSaved = false;
      if (widget.settings.recordAudio &&
          widget.controller.recordings != null &&
          _bundle != null) {
        _recording = await SessionRecording.open(
          widget.controller.recordings!.newFile(),
        );
        _recording!.addListener(_changed);
      }
      _bundle?.listener.recording = _recording;
      _bundle?.tts.recording = _recording;
      for (var n = 2; n > 0; n--) {
        if (!mounted) return;
        setState(() => _countdown = n);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      setState(() {
        _countdown = 0;
        _loading = false;
      });
      _recording?.resume();
      await _engine!.begin(paused: !_foreground);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed && _report == null) {
      unawaited(_engine?.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine?.removeListener(_changed);
    _engine?.dispose();
    unawaited(_meaning?.dispose());
    unawaited(_embeddings?.dispose());
    unawaited(_interruptions?.cancel());
    unawaited(_unplugged?.cancel());
    _recording?.removeListener(_changed);
    if (!_recordingSaved) unawaited(_recording?.discard());
    _recording?.dispose();
    super.dispose();
  }

  Widget _actorLine(RehearsalEngine engine) {
    final line = engine.current;
    if (line == null ||
        line.character != engine.character ||
        engine.state != RehearsalState.listening) {
      return const SizedBox.shrink();
    }
    final text = line.text;
    switch (widget.settings.myLines) {
      case LineDisplay.hidden:
      case LineDisplay.onRequest:
        return const Text(
          'Your line is yours.',
          key: ValueKey('hidden-actor-line'),
          style: TextStyle(fontFamily: 'Literata', fontSize: 28, height: 1.5),
        );
      case LineDisplay.initials:
        return Text(
          text
              .split(RegExp(r'\s+'))
              .map((w) => w.isEmpty ? '' : w[0])
              .join(' '),
          style: const TextStyle(fontSize: 24, height: 1.5),
        );
      case LineDisplay.blurred:
        return ExcludeSemantics(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: Text(
              text,
              style: const TextStyle(fontFamily: 'Literata', fontSize: 28),
            ),
          ),
        );
      case LineDisplay.visible:
        return Text(
          text,
          style: const TextStyle(
            fontFamily: 'Literata',
            fontSize: 28,
            height: 1.5,
          ),
        );
    }
  }

  Widget _recognitionCheck(RehearsalEngine engine) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            engine.recognitionNotice,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('First hearing: ${engine.transcript}'),
          if (engine.recognitionAlternative.isNotEmpty)
            Text('Second hearing: ${engine.recognitionAlternative}'),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed:
                    engine.reviewingHearing ||
                        engine.state != RehearsalState.listening
                    ? null
                    : engine.useFirstHearing,
                child: const Text('Use first hearing'),
              ),
              if (engine.recognitionAlternative.isNotEmpty)
                TextButton(
                  onPressed:
                      engine.reviewingHearing ||
                          engine.state != RehearsalState.listening
                      ? null
                      : engine.useSecondHearing,
                  child: const Text('Use second hearing'),
                ),
              TextButton(
                onPressed:
                    engine.reviewingHearing ||
                        engine.state != RehearsalState.listening
                    ? null
                    : engine.retryHearing,
                child: const Text('Try line again'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _sessionPosition(RehearsalEngine engine) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      '${engine.sceneHeading} · Your line ${engine.actorLineNumber} of ${engine.actorLineCount}',
      style: Theme.of(context).textTheme.labelLarge,
    ),
  );

  Widget _recordingStatus() => _recording == null
      ? const SizedBox.shrink()
      : Text(
          _recording!.error ??
              (_recording!.active ? '● Recording locally' : 'Recording paused'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        );

  String _status(RehearsalEngine engine, {bool compact = false}) {
    if (engine.reviewingHearing) return 'Checking hearing';
    if (engine.recognitionNotice.isNotEmpty &&
        engine.state == RehearsalState.listening) {
      return 'Check hearing';
    }
    return switch (engine.state) {
      RehearsalState.listening =>
        compact ? 'Your turn · listening' : 'Listening',
      RehearsalState.speaking => 'Scene partner',
      RehearsalState.evaluating => 'Checking line',
      RehearsalState.error => 'Needs attention',
      RehearsalState.paused => 'Paused',
      RehearsalState.ready => 'Preparing',
      RehearsalState.finished => 'Scene complete',
    };
  }

  Widget _liveRehearsal(RehearsalEngine engine, Widget hiddenView) {
    if (!_showScript) return hiddenView;
    final controls = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _sessionPosition(engine),
          _recordingStatus(),
          if (_audioNotice != null) Text(_audioNotice!),
          Text(
            '${_status(engine, compact: true)} · ${engine.character}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (engine.transcript.isNotEmpty && engine.recognitionNotice.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Heard: ${engine.transcript}'),
            ),
          if (engine.recognitionNotice.isNotEmpty) _recognitionCheck(engine),
          if (engine.hint.isNotEmpty) Text(engine.hint),
          if (engine.state == RehearsalState.error) Text(engine.error),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton(
                onPressed:
                    engine.state == RehearsalState.listening &&
                        !engine.reviewingHearing &&
                        engine.recognitionNotice.isEmpty
                    ? engine.requestHint
                    : null,
                onLongPress:
                    engine.state == RehearsalState.listening &&
                        !engine.reviewingHearing &&
                        engine.recognitionNotice.isEmpty
                    ? () => engine.requestHint(full: true)
                    : null,
                child: const Text('I NEED A LINE'),
              ),
              OutlinedButton.icon(
                onPressed:
                    engine.state == RehearsalState.paused ||
                        engine.state == RehearsalState.error
                    ? engine.resume
                    : engine.pause,
                icon: Icon(
                  engine.state == RehearsalState.paused ||
                          engine.state == RehearsalState.error
                      ? Icons.play_arrow
                      : Icons.pause,
                ),
                label: Text(
                  engine.state == RehearsalState.error
                      ? 'Retry'
                      : engine.state == RehearsalState.paused
                      ? 'Resume'
                      : 'Pause',
                ),
              ),
              if (engine.state == RehearsalState.listening)
                TextButton(
                  onPressed:
                      engine.transcript.isEmpty ||
                          engine.reviewingHearing ||
                          engine.recognitionNotice.isNotEmpty
                      ? null
                      : () => engine.submit(engine.transcript),
                  child: const Text('Finish line'),
                ),
              if (engine.state == RehearsalState.listening &&
                  engine.recognitionNotice.isEmpty)
                TextButton(
                  onPressed: engine.reviewingHearing
                      ? null
                      : engine.retryHearing,
                  child: const Text('Try line again'),
                ),
              if (engine.state == RehearsalState.listening)
                PopupMenuButton<String>(
                  tooltip: 'Line options',
                  enabled: !engine.reviewingHearing,
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (_) =>
                      unawaited(engine.submit('', skipped: true)),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'skip', child: Text('Skip this line')),
                  ],
                ),
              TextButton(
                onPressed: () => _finish(completed: false),
                child: const Text('End rehearsal'),
              ),
            ],
          ),
        ],
      ),
    );
    final script = ScriptFollowView(
      scene: engine.scene,
      activeId: engine.current?.id,
      character: engine.character,
      transcript: engine.transcript,
    );
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, size) => size.maxWidth >= 800
            ? Row(
                children: [
                  Expanded(flex: 2, child: script),
                  Expanded(child: controls),
                ],
              )
            : Column(
                children: [
                  Expanded(child: script),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: size.maxHeight * .38,
                    ),
                    child: controls,
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    return PopScope(
      canPop: _report != null || engine == null,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _finish(completed: false);
        if (context.mounted) Navigator.pop(context);
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): () {
            if (engine?.state == RehearsalState.paused) {
              unawaited(engine?.resume());
            } else {
              unawaited(engine?.pause());
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyH): () =>
              unawaited(engine?.requestHint()),
          const SingleActivator(LogicalKeyboardKey.enter): () =>
              unawaited(engine?.submit(engine.transcript)),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                widget.production.title,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                if (engine != null && _report == null)
                  IconButton(
                    tooltip: _showScript ? 'Hide script' : 'Follow script',
                    onPressed: () => setState(() => _showScript = !_showScript),
                    icon: Icon(
                      _showScript
                          ? Icons.visibility_off_outlined
                          : Icons.menu_book_outlined,
                    ),
                  ),
              ],
            ),
            body: _loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 20),
                        Text(
                          _countdown > 0
                              ? 'Ready in $_countdown…'
                              : 'Preparing your local scene partner…',
                        ),
                      ],
                    ),
                  )
                : _error != null
                ? PageBody(
                    children: [
                      const SectionLabel('Let’s get ready'),
                      Text(_error!),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => _create(),
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : _report != null
                ? ResultsView(
                    report: _report!,
                    runAgain: () => _repeat(),
                    drill: () => _repeat(
                      practice: PracticeMode.lineDrill,
                      drill: _report!.weak.map((a) => a.line.id).toSet(),
                    ),
                    cueDrill: () => _repeat(practice: PracticeMode.cueDrill),
                    recordings: widget.controller.recordings == null
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RecordingsPage(
                                store: widget.controller.recordings!,
                                productionId: widget.production.id,
                              ),
                            ),
                          ),
                    acceptVariation: (attempt) async {
                      await widget.controller.database.acceptVariation(
                        attempt.line.id,
                        attempt.transcript,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Variation saved for Flexible, Loose and Improv. The script text is unchanged.',
                            ),
                          ),
                        );
                      }
                    },
                  )
                : engine == null
                ? const SizedBox.shrink()
                : _liveRehearsal(
                    engine,
                    PageBody(
                      children: [
                        Text(
                          engine.sceneHeading,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 12),
                        _recordingStatus(),
                        if (engine.stageDirection.isNotEmpty &&
                            widget.settings.stageDirections ==
                                DirectionPolicy.display)
                          Text(engine.stageDirection),
                        Text(
                          'Playing ${engine.character} · ${widget.settings.accuracy.label}',
                        ),
                        const SizedBox(height: 32),
                        Semantics(
                          liveRegion: true,
                          child: Row(
                            children: [
                              Icon(
                                engine.state == RehearsalState.listening &&
                                        engine.recognitionNotice.isEmpty &&
                                        !engine.reviewingHearing
                                    ? Icons.mic_rounded
                                    : engine.state == RehearsalState.speaking
                                    ? Icons.volume_up_rounded
                                    : Icons.pause_circle_outline,
                                size: 38,
                                color: engine.state == RehearsalState.listening
                                    ? const Color(0xff58a77a)
                                    : Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _status(engine),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _sessionPosition(engine),
                        if (_audioNotice != null) Text(_audioNotice!),
                        const SizedBox(height: 16),
                        if (engine.partner != null &&
                            widget.settings.partnerLines !=
                                PartnerDisplay.hidden &&
                            (engine.state == RehearsalState.speaking ||
                                widget.settings.partnerLines ==
                                    PartnerDisplay.visible)) ...[
                          Text(
                            engine.partner!.character ?? 'Stage direction',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            engine.partner!.text,
                            style: const TextStyle(
                              fontFamily: 'Literata',
                              fontSize: 28,
                              height: 1.6,
                            ),
                          ),
                          if (widget.settings.parentheticals ==
                                  DirectionPolicy.display &&
                              engine.partner!.parenthetical.isNotEmpty)
                            Text(engine.partner!.parenthetical),
                        ],
                        _actorLine(engine),
                        if (engine.recognitionNotice.isNotEmpty)
                          _recognitionCheck(engine),
                        if (engine.hint.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(
                            engine.hint,
                            style: const TextStyle(
                              fontFamily: 'Literata',
                              fontSize: 26,
                              height: 1.5,
                            ),
                          ),
                        ],
                        if (engine.state == RehearsalState.error) ...[
                          Text(engine.error),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: engine.resume,
                            child: const Text('Retry this line'),
                          ),
                        ],
                        const SizedBox(height: 36),
                        if (engine.state == RehearsalState.listening) ...[
                          FilledButton(
                            onPressed:
                                engine.recognitionNotice.isNotEmpty ||
                                    engine.reviewingHearing
                                ? null
                                : engine.requestHint,
                            onLongPress:
                                engine.recognitionNotice.isNotEmpty ||
                                    engine.reviewingHearing
                                ? null
                                : () => engine.requestHint(full: true),
                            child: const Text('I NEED A LINE'),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Say “${widget.settings.hintCommand}” for a hint. Hold the button for the full line.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed:
                                engine.transcript.isEmpty ||
                                    engine.reviewingHearing ||
                                    engine.recognitionNotice.isNotEmpty
                                ? null
                                : () => engine.submit(engine.transcript),
                            child: const Text('Finish line'),
                          ),
                          if (engine.recognitionNotice.isEmpty)
                            TextButton(
                              onPressed: engine.reviewingHearing
                                  ? null
                                  : engine.retryHearing,
                              child: const Text('Try line again'),
                            ),
                          TextButton(
                            onPressed: () => engine.submit('', skipped: true),
                            child: const Text('Skip this line'),
                          ),
                        ],
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: engine.state == RehearsalState.paused
                              ? engine.resume
                              : engine.pause,
                          icon: Icon(
                            engine.state == RehearsalState.paused
                                ? Icons.play_arrow
                                : Icons.pause,
                          ),
                          label: Text(
                            engine.state == RehearsalState.paused
                                ? 'Resume'
                                : 'Pause',
                          ),
                        ),
                        TextButton(
                          onPressed: () => _finish(completed: false),
                          child: const Text('End rehearsal & see results'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
