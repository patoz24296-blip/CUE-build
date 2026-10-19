import 'dart:io';
import 'package:record/record.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import '../data/app_controller.dart';
import '../domain/models.dart';
import '../services/model_storage_access.dart';
import 'model_page.dart';
import 'theme.dart';
import 'recordings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});
  final AppController controller;
  Future<void> _microphone(BuildContext context) async {
    final recorder = AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        throw StateError(
          'Enable microphone access in your device Settings, then try again.',
        );
      }
      final devices = await recorder.listInputDevices();
      if (!context.mounted) return;
      final id = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Microphone'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Automatic device route'),
            ),
            for (final device in devices)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, device.id),
                child: Text(device.label),
              ),
          ],
        ),
      );
      if (id != null) {
        await controller.change('microphoneId', id.isEmpty ? null : id);
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    } finally {
      await recorder.dispose();
    }
  }

  Future<void> _hintCommand(BuildContext context) async {
    final input = TextEditingController(text: controller.settings.hintCommand);
    final command = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Spoken hint command'),
        content: TextField(
          controller: input,
          decoration: const InputDecoration(
            helperText: 'Use a distinctive phrase of at least two words.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().split(RegExp(r'\s+')).length >= 2) {
                Navigator.pop(context, input.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (command != null) await controller.change('hintCommand', command);
    // The dialog route releases its text field after its closing animation.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    input.dispose();
  }

  Widget _choice(
    BuildContext context,
    String label,
    String key,
    List<String> labels,
    int selected,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<int>(
      key: ValueKey('$key-$selected'),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: List.generate(
        labels.length,
        (i) => DropdownMenuItem(
          value: i,
          child: Text(labels[i], maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
      onChanged: (v) => controller.change(key, v),
    ),
  );
  Widget _toggle(String label, String key, bool value, {String? help}) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: help == null ? null : Text(help),
        value: value,
        onChanged: (v) => controller.change(key, v),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final settings = controller.settings;
        return PageBody(
          children: [
            const SectionLabel('Rehearsal'),
            _choice(
              context,
              'Default accuracy',
              'accuracy',
              AccuracyMode.values.map((m) => m.label).toList(),
              settings.accuracy.index,
            ),
            _choice(context, 'Response timing', 'timing', [
              'Fast',
              'Natural',
              'Patient',
            ], settings.timing.index),
            Text(
              'Dramatic pause allowance ${settings.pauseMultiplier.toStringAsFixed(1)}×',
            ),
            Slider(
              value: settings.pauseMultiplier,
              min: .5,
              max: 3,
              divisions: 10,
              onChanged: (v) => controller.change('pauseMultiplier', v),
            ),
            _toggle('Automatic next line', 'autoNext', settings.autoNext),
            _toggle(
              'Allow overlapping dialogue',
              'interruptions',
              settings.interruptions,
              help:
                  'Uses actor-line evidence to stop a partner cue. Headphones give the best separation.',
            ),
            _toggle('Speak hints aloud', 'spokenHints', settings.spokenHints),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Spoken hint command'),
              subtitle: Text(settings.hintCommand),
              onTap: () => _hintCommand(context),
            ),
            _toggle(
              'Rehearsal sounds',
              'rehearsalSounds',
              settings.rehearsalSounds,
              help: 'A quiet sound marks the start and end of a run.',
            ),
            _toggle(
              'Equivalent contractions',
              'contractionsEquivalent',
              settings.contractionsEquivalent,
              help: '“Don’t” and “do not” can count as the same wording.',
            ),
            const SectionLabel('Script display'),
            _choice(context, 'My lines', 'myLines', [
              'Hidden',
              'First letters',
              'Blurred',
              'Reveal on request',
              'Visible',
            ], settings.myLines.index),
            _choice(context, 'Partner lines', 'partnerLines', [
              'Hidden',
              'Visible',
              'Current line',
            ], settings.partnerLines.index),
            _choice(
              context,
              'Stage directions',
              'stageDirections',
              ['Ignore', 'Display', 'Read aloud'],
              settings.stageDirections.index,
            ),
            _choice(
              context,
              'Parentheticals',
              'parentheticals',
              ['Ignore', 'Display', 'Affect pacing'],
              settings.parentheticals.index,
            ),
            const SectionLabel('Scene partners'),
            _choice(context, 'Performance', 'performance', [
              'Neutral',
              'Natural',
              'Full performance',
            ], settings.performance.index),
            _toggle('Vary cue timing', 'variableCues', settings.variableCues),
            Text('Speech rate ${(settings.speechRate * 100).round()}%'),
            Slider(
              value: settings.speechRate,
              min: .7,
              max: 1.3,
              divisions: 12,
              onChanged: (v) => controller.change('speechRate', v),
            ),
            const SectionLabel('Offline listening'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Microphone'),
              subtitle: Text(
                settings.microphoneId == null
                    ? 'Automatic device route'
                    : 'Custom input selected',
              ),
              onTap: () => _microphone(context),
            ),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: settings.speechModel,
              decoration: const InputDecoration(labelText: 'Recognition'),
              items: const [
                DropdownMenuItem(
                  value: 'moonshine',
                  child: Text(
                    'Responsive · Moonshine v2',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'whisper-base-multilingual',
                  child: Text(
                    'Detailed · English and Spanish',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'whisper-tiny',
                  child: Text(
                    'Quick · lower memory',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'whisper-base',
                  child: Text(
                    'Detailed · better recognition',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'whisper-small',
                  child: Text(
                    'High quality · more memory',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'whisper-multilingual',
                  child: Text(
                    'Multilingual · choose a language',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: (v) => controller.change('speechModel', v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey('lang-${settings.language}'),
              initialValue: settings.language,
              decoration: const InputDecoration(
                labelText: 'Recognition language',
              ),
              items: [
                for (final language in {
                  'en': 'English',
                  'es': 'Spanish',
                  'fr': 'French',
                  'de': 'German',
                  'it': 'Italian',
                  'pt': 'Portuguese',
                  'ja': 'Japanese',
                  'zh': 'Chinese',
                  'ko': 'Korean',
                  'ru': 'Russian',
                }.entries)
                  DropdownMenuItem(
                    value: language.key,
                    child: Text(language.value),
                  ),
              ],
              onChanged: (v) => controller.change('language', v),
            ),
            const SizedBox(height: 16),
            const Text('Listening threshold · increase in a noisy room'),
            Slider(
              value: settings.sensitivity,
              min: .25,
              max: .85,
              divisions: 12,
              onChanged: (v) => controller.change('sensitivity', v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Manage offline components'),
              trailing: const Icon(Icons.download_outlined),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ModelPage(
                    models: controller.models,
                    speech: settings.effectiveSpeechModel,
                    language: settings.language,
                  ),
                ),
              ),
            ),
            const SectionLabel('Meaning comparison'),
            if (!Platform.isIOS && !Platform.isAndroid)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Model storage folder'),
                subtitle: Text(controller.models.root.path),
                onTap: () async {
                  try {
                    final selected = await FilePicker.platform.getDirectoryPath(
                      dialogTitle: 'Choose where to store CUE components',
                    );
                    if (selected == null) return;
                    await controller.models.relocate(
                      Directory(p.join(selected, 'CUE-models')),
                    );
                    await ModelStorageAccess.remember(selected);
                    await controller.change(
                      'modelStoragePath',
                      controller.models.root.path,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Components copied and verified. Previous copies can be removed from their old folder.',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
              ),
            const Text(
              'Built-in meaning comparison is optional. Deterministic checks protect names, numbers and negation before any model decision.',
            ),
            const SectionLabel('Appearance'),
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey(settings.theme),
              initialValue: settings.theme,
              decoration: const InputDecoration(labelText: 'Theme'),
              items: const [
                DropdownMenuItem(value: 'system', child: Text('System')),
                DropdownMenuItem(value: 'light', child: Text('Light')),
                DropdownMenuItem(value: 'dark', child: Text('Dark')),
              ],
              onChanged: (v) => controller.change('theme', v),
            ),
            const SizedBox(height: 16),
            Text('Text size ${(settings.textScale * 100).round()}%'),
            Slider(
              value: settings.textScale,
              min: .85,
              max: 1.5,
              divisions: 13,
              onChanged: (v) => controller.change('textScale', v),
            ),
            const SectionLabel('Privacy'),
            const Text(
              'Free for everyone. Every feature is included, with no subscriptions, usage credits or external AI services. Voices, listening and meaning comparison run on this device. Normal microphone audio is discarded after each line. Optional recordings stay here until you export or delete them.',
            ),
            _toggle(
              'Record rehearsals',
              'recordAudio',
              settings.recordAudio,
              help:
                  'Off by default. Saves your microphone and played partner cues in a local WAV file. Headphones improve the recording.',
            ),
            _toggle(
              'Automatically delete old recordings',
              'autoDeleteRecordings',
              settings.autoDeleteRecordings,
            ),
            DropdownButtonFormField<int>(
              isExpanded: true,
              key: ValueKey('retention-${settings.recordingRetentionDays}'),
              initialValue:
                  [1, 7, 30, 90, 0].contains(settings.recordingRetentionDays)
                  ? settings.recordingRetentionDays
                  : 7,
              decoration: const InputDecoration(labelText: 'Keep recordings'),
              items: [
                for (final days in [1, 7, 30, 90, 0])
                  DropdownMenuItem(
                    value: days,
                    child: Text(
                      days == 0 ? 'Until I delete them' : '$days days',
                    ),
                  ),
              ],
              onChanged: (v) async {
                await controller.change('recordingRetentionDays', v);
                await controller.recordings?.clean(controller.settings);
              },
            ),
            if (controller.recordings != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Manage / export recordings'),
                trailing: const Icon(Icons.audio_file_outlined),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        RecordingsPage(store: controller.recordings!),
                  ),
                ),
              ),
            TextButton(
              onPressed: () async {
                try {
                  final cache = Directory(
                    p.join((await getTemporaryDirectory()).path, 'cue-audio'),
                  );
                  if (await cache.exists()) await cache.delete(recursive: true);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Temporary partner audio deleted.'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
              child: const Text('Delete cached partner audio'),
            ),
            TextButton(
              onPressed: () async {
                if (await confirmDeletion(
                  context,
                  'Delete all rehearsal history? Your scripts will remain.',
                )) {
                  await controller.deleteHistory();
                }
              },
              child: const Text('Delete rehearsal history'),
            ),
          ],
        );
      },
    ),
  );
}
