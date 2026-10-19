import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../domain/models.dart';
import '../domain/performance.dart';
import '../domain/voice_catalog.dart';
import '../services/local_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'progress_page.dart';
import 'recordings_page.dart';
import 'model_page.dart';
import 'review_page.dart';
import 'rehearsal_page.dart';
import 'results_view.dart';
import 'theme.dart';
import 'session_setup_card.dart';

class ProductionPage extends StatefulWidget {
  const ProductionPage({
    super.key,
    required this.controller,
    required this.production,
  });
  final AppController controller;
  final Production production;
  @override
  State<ProductionPage> createState() => _ProductionPageState();
}

class _ProductionPageState extends State<ProductionPage> {
  late Production _production = widget.production;
  String? _sceneId;
  PracticeMode _practice = PracticeMode.scenePartner;
  AccuracyMode? _accuracy;
  CueReduction _reduction = CueReduction.full;
  int _start = 0, _end = 0;
  bool _loop = false, _busy = false;
  bool _allScenes = false;
  bool _followScript = false;
  final _cast = <String, Future<VoiceAssignment>>{};
  DrillSelection _drillSelection = DrillSelection.weakest;
  final _customIds = <String>{};
  List<Scene> get _chosenScenes => _allScenes
      ? _production.scenes
      : _production.scenes.where((s) => s.id == _sceneId).toList();
  Scene? get _scene => _allScenes
      ? combineScenes(_production.scenes)
      : _production.scenes.where((s) => s.id == _sceneId).firstOrNull;
  Future<void> _run() async {
    if (_busy || _scene == null || _production.selectedCharacter == null) {
      return;
    }
    if (!_scene!.entries
        .sublist(_start, _end + 1)
        .any(
          (e) => e.isDialogue && e.character == _production.selectedCharacter,
        )) {
      showError(
        context,
        'Choose a range that includes at least one of your lines.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final models = widget.controller.models;
      if (!models.ready(widget.controller.settings.effectiveSpeechModel)) {
        await _components();
        if (!mounted ||
            !models.ready(widget.controller.settings.effectiveSpeechModel)) {
          return;
        }
      }
      final ids = _practice == PracticeMode.lineDrill
          ? (_drillSelection == DrillSelection.custom
                ? Set<String>.of(_customIds)
                : await widget.controller.database.weakLineIds(
                    _production,
                    allImperfect: _drillSelection == DrillSelection.imperfect,
                  ))
          : <String>{};
      ids.retainAll(
        _scene!.entries
            .sublist(_start, _end + 1)
            .where(
              (e) =>
                  e.isDialogue && e.character == _production.selectedCharacter,
            )
            .map((e) => e.id),
      );
      if (_practice == PracticeMode.lineDrill &&
          ids.isEmpty &&
          _drillSelection == DrillSelection.custom) {
        throw StateError(
          'Choose at least one of your lines for the custom drill.',
        );
      }
      if (_practice == PracticeMode.lineDrill && ids.isEmpty) {
        ids.addAll(
          _scene!.entries
              .sublist(_start, _end + 1)
              .where((e) => e.character == _production.selectedCharacter)
              .map((e) => e.id),
        );
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RehearsalPage(
            controller: widget.controller,
            production: _production,
            scene: _scene!,
            sceneIds: _chosenScenes.map((s) => s.id).toList(),
            settings: widget.controller.settings.change(
              'accuracy',
              (_accuracy ?? widget.controller.settings.accuracy).index,
            ),
            practice: _practice,
            start: _start,
            end: _end,
            loop: _loop,
            cueReduction: _reduction,
            drillIds: ids,
            followScript: _followScript,
          ),
        ),
      );
      await widget.controller.refresh();
      _production = widget.controller.productions.firstWhere(
        (p) => p.id == _production.id,
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _components() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ModelPage(
        models: widget.controller.models,
        speech: widget.controller.settings.effectiveSpeechModel,
        language: widget.controller.settings.language,
      ),
    ),
  );

  Future<void> _language(String language) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.controller.change('language', language);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _history() async {
    final reports = await widget.controller.database.history(_production);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Rehearsal history')),
          body: PageBody(
            children: [
              if (reports.isEmpty)
                const Text('Your first run will appear here.'),
              for (final report in reports)
                Card(
                  child: ListTile(
                    title: Text(
                      '${report.character} · ${(report.accuracy * 100).round()}% textual accuracy',
                    ),
                    subtitle: Text(
                      '${report.startedAt.toLocal().toString().split('.').first} · ${report.attempts.length} lines',
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Past run')),
                          body: ResultsView(report: report),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _voice(String character) async {
    final existing = await widget.controller.database.voice(
      _production.id,
      character,
    );
    if (!mounted) return;
    final language = widget.controller.settings.language == 'es' ? 'es' : 'en';
    var speaker = resolveVoice(
      existing.speaker,
      character,
      _production.characters.indexOf(character),
      language: language,
    ).speaker;
    var rate = existing.rate;
    final preview = PartnerVoicePreview(
      widget.controller.models,
      await getTemporaryDirectory(),
      language,
    );
    var previewing = false;
    if (!mounted) {
      await preview.dispose();
      return;
    }
    final direction = TextEditingController(text: existing.direction);
    final saved = await showDialog<VoiceAssignment>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('$character’s voice'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: speaker,
                  items: [
                    for (final voice in partnerVoices.where(
                      (v) => v.language == language,
                    ))
                      DropdownMenuItem(
                        value: voice.speaker,
                        child: Text(
                          voice.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setDialog(() => speaker = v!),
                  decoration: const InputDecoration(
                    labelText: 'Local scene partner voice',
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.volume_up_outlined),
                  label: Text(previewing ? 'Playing…' : 'Listen to this voice'),
                  onPressed: previewing
                      ? null
                      : () async {
                          if (!widget.controller.models.installed.contains(
                            'kokoro',
                          )) {
                            showError(
                              context,
                              'Download Natural scene partner voices in Offline components first.',
                            );
                            return;
                          }
                          setDialog(() => previewing = true);
                          try {
                            await preview.speak(speaker, rate);
                          } catch (e) {
                            if (context.mounted) {
                              showError(context, e);
                            }
                          } finally {
                            if (context.mounted) {
                              setDialog(() => previewing = false);
                            }
                          }
                        },
                ),
                const SizedBox(height: 16),
                Text('Pace ${(rate * 100).round()}%'),
                Slider(
                  value: rate,
                  min: .7,
                  max: 1.3,
                  divisions: 12,
                  onChanged: (v) => setDialog(() => rate = v),
                ),
                TextField(
                  controller: direction,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Character direction',
                    hintText:
                        'More annoyed. Faster and excited. Pause 1 second.',
                    helperText: 'Adjusts pace, pauses and volume locally.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                VoiceAssignment(
                  speaker: speaker,
                  rate: rate,
                  direction: direction.text.trim(),
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    await preview.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    direction.dispose();
    if (saved != null) {
      await widget.controller.database.saveVoice(
        _production.id,
        character,
        saved,
      );
      if (mounted) setState(() => _cast.remove(character));
    }
  }

  Future<void> _sceneDirection() async {
    if (_allScenes || _scene == null) return;
    final directions = await widget.controller.database.sceneDirections(
      _production,
    );
    if (!mounted) return;
    final input = TextEditingController(text: directions[_scene!.id] ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scene direction'),
        content: TextField(
          controller: input,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Slower and quiet. Leave a pause before responses.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null) {
      await widget.controller.database.saveSceneDirection(_scene!.id, value);
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    input.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final character = _production.selectedCharacter;
    final scenes = _production.scenes
        .where((s) => character == null || s.involves(character))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your rehearsal'),
        actions: [
          PopupMenuButton<String>(
            enabled: !_busy,
            tooltip: 'Script options',
            onSelected: (v) async {
              if (v == 'check') {
                final edited = await Navigator.push<Production>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReviewPage(production: _production),
                  ),
                );
                if (edited != null) {
                  await widget.controller.save(edited);
                  if (mounted) {
                    setState(() {
                      _production = edited;
                      _sceneId = null;
                      _cast.clear();
                    });
                  }
                }
              }
              if (v == 'history') await _history();
              if (v == 'progress' && context.mounted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProgressPage(
                      controller: widget.controller,
                      production: _production,
                    ),
                  ),
                );
              }
              if (v == 'recordings' &&
                  context.mounted &&
                  widget.controller.recordings != null) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecordingsPage(
                      store: widget.controller.recordings!,
                      productionId: _production.id,
                    ),
                  ),
                );
              }
              if (v == 'delete' &&
                  context.mounted &&
                  await confirmDeletion(
                    context,
                    'Delete this script and its rehearsal history from this device?',
                  )) {
                await widget.controller.deleteProduction(_production.id);
                await widget.controller.refresh();
                if (context.mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'check', child: Text('Check / edit script')),
              PopupMenuItem(value: 'history', child: Text('Rehearsal history')),
              PopupMenuItem(
                value: 'progress',
                child: Text('Progress & weak lines'),
              ),
              PopupMenuItem(
                value: 'recordings',
                child: Text('Recordings / export'),
              ),
              PopupMenuItem(value: 'delete', child: Text('Delete script')),
            ],
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: PageBody(
          children: [
            Text(
              _production.title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SectionLabel('Who are you playing?'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _production.characters
                  .map(
                    (name) => ChoiceChip(
                      label: Text(name),
                      selected: character == name,
                      onSelected: (_) async {
                        setState(() {
                          _production = _production.copyWith(
                            selectedCharacter: name,
                          );
                          _sceneId = null;
                          _allScenes = false;
                        });
                        await widget.controller.save(_production);
                      },
                    ),
                  )
                  .toList(),
            ),
            const SectionLabel('Scene'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Run all scenes in script order'),
              value: _allScenes,
              onChanged: (v) => setState(() {
                _allScenes = v;
                _start = 0;
                _end = _scene?.entries.length != null
                    ? _scene!.entries.length - 1
                    : 0;
              }),
            ),
            if (!_allScenes)
              RadioGroup<String>(
                groupValue: _sceneId,
                onChanged: (v) => setState(() {
                  _sceneId = v;
                  _start = 0;
                  _end = scenes.firstWhere((s) => s.id == v).entries.length - 1;
                }),
                child: Column(
                  children: [
                    for (final scene in scenes)
                      Card(
                        child: RadioListTile<String>(
                          value: scene.id,
                          title: Text(scene.heading),
                          subtitle: Text('${scene.dialogue.length} lines'),
                        ),
                      ),
                  ],
                ),
              ),
            if (_scene != null) ...[
              SessionSetupCard(
                models: widget.controller.models,
                settings: widget.controller.settings,
                followScript: _followScript,
                onFollowScript: (value) =>
                    setState(() => _followScript = value),
                onLanguageChanged: _language,
                onComponents: _components,
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Practice options'),
                subtitle: Text(
                  '${_practice.label} · ${(_accuracy ?? widget.controller.settings.accuracy).label}',
                ),
                children: [
                  const SectionLabel('Practice'),
                  RadioGroup<PracticeMode>(
                    groupValue: _practice,
                    onChanged: (v) => setState(() => _practice = v!),
                    child: Column(
                      children: [
                        for (final mode in PracticeMode.values)
                          RadioListTile<PracticeMode>(
                            contentPadding: EdgeInsets.zero,
                            value: mode,
                            title: Text(mode.label),
                            subtitle: Text(mode.description),
                          ),
                      ],
                    ),
                  ),
                  const SectionLabel('Accuracy'),
                  if (_practice == PracticeMode.lineDrill) ...[
                    DropdownButtonFormField<DrillSelection>(
                      key: ValueKey(_drillSelection),
                      initialValue: _drillSelection,
                      decoration: const InputDecoration(labelText: 'Drill set'),
                      items: [
                        for (final option in DrillSelection.values)
                          DropdownMenuItem(
                            value: option,
                            child: Text(
                              [
                                'Weakest lines',
                                'All imperfect lines',
                                'Custom lines',
                              ][option.index],
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _drillSelection = v!),
                    ),
                    if (_drillSelection == DrillSelection.custom)
                      ExpansionTile(
                        title: const Text('Select your lines'),
                        children: [
                          for (final entry in _scene!.dialogue.where(
                            (e) => e.character == character,
                          ))
                            CheckboxListTile(
                              value: _customIds.contains(entry.id),
                              title: Text(
                                'Line ${_scene!.entries.indexOf(entry) + 1} · $character',
                              ),
                              subtitle: const Text('Dialogue hidden'),
                              onChanged: (v) => setState(() {
                                if (v!) {
                                  _customIds.add(entry.id);
                                } else {
                                  _customIds.remove(entry.id);
                                }
                              }),
                            ),
                        ],
                      ),
                  ],
                  DropdownButtonFormField<AccuracyMode>(
                    initialValue:
                        _accuracy ?? widget.controller.settings.accuracy,
                    items: AccuracyMode.values
                        .map(
                          (m) =>
                              DropdownMenuItem(value: m, child: Text(m.label)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _accuracy = v),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    (_accuracy ?? widget.controller.settings.accuracy)
                        .explanation,
                  ),
                  if (_practice == PracticeMode.cueDrill) ...[
                    const SectionLabel('Cue length'),
                    DropdownButtonFormField<CueReduction>(
                      initialValue: _reduction,
                      items: CueReduction.values
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(
                                [
                                  'Full cue',
                                  'Last sentence',
                                  'Last phrase',
                                  'Last four words',
                                ][m.index],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _reduction = v!),
                    ),
                  ],
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Range & repetition'),
                    children: [
                      const Text(
                        'Choose a starting line and an ending line. Your dialogue stays hidden here.',
                      ),
                      DropdownButtonFormField<int>(
                        key: ValueKey('start-$_sceneId-$_start'),
                        initialValue: _start,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Start from',
                        ),
                        items: List.generate(
                          _scene!.entries.length,
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text(
                              'Line ${i + 1} · ${_scene!.entries[i].character ?? 'Direction'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        onChanged: (v) => setState(() {
                          _start = v!;
                          if (_end < _start) _end = _start;
                        }),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: ValueKey('end-$_sceneId-$_end-$_start'),
                        initialValue: _end,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'End at'),
                        items: List.generate(_scene!.entries.length - _start, (
                          n,
                        ) {
                          final i = n + _start;
                          return DropdownMenuItem(
                            value: i,
                            child: Text(
                              'Line ${i + 1} · ${_scene!.entries[i].character ?? 'Direction'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                        onChanged: (v) => setState(() => _end = v!),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Loop this section'),
                        value: _loop,
                        onChanged: (v) => setState(() => _loop = v),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            const SectionLabel('Scene partners'),
            if (!_allScenes && _scene != null)
              TextButton(
                onPressed: _sceneDirection,
                child: const Text('Direction for this scene'),
              ),
            for (final name in _production.characters.where(
              (n) => n != character,
            ))
              FutureBuilder<VoiceAssignment>(
                future: _cast.putIfAbsent(
                  name,
                  () => widget.controller.database.voice(_production.id, name),
                ),
                builder: (context, snapshot) {
                  final voice = snapshot.data;
                  final chosen = voice == null
                      ? null
                      : resolveVoice(
                          voice.speaker,
                          name,
                          _production.characters.indexOf(name),
                          language: widget.controller.settings.language == 'es'
                              ? 'es'
                              : 'en',
                        );
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(name),
                    subtitle: Text(
                      chosen == null
                          ? snapshot.hasError
                                ? 'Voice could not be loaded. Tap to retry.'
                                : 'Loading voice…'
                          : '${chosen.label} · ${(voice!.rate * 100).round()}% pace',
                    ),
                    trailing: const Icon(Icons.record_voice_over_outlined),
                    onTap: () => _voice(name),
                  );
                },
              ),
            const SizedBox(height: 20),
            Text(
              'During the scene, say “${widget.controller.settings.hintCommand}” for a hint. Pauses are allowed. Your upcoming lines are hidden by default.',
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: character == null || _scene == null || _busy
                ? null
                : _run,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(_busy ? 'Preparing…' : 'Rehearse'),
          ),
        ),
      ),
    );
  }
}
