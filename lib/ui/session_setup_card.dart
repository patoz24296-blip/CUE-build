import 'package:flutter/material.dart';
import '../data/model_manager.dart';
import '../domain/models.dart';

class SessionSetupCard extends StatelessWidget {
  const SessionSetupCard({
    super.key,
    required this.models,
    required this.settings,
    required this.followScript,
    required this.onFollowScript,
    required this.onLanguageChanged,
    required this.onComponents,
  });
  final ModelManager models;
  final AppSettings settings;
  final bool followScript;
  final ValueChanged<bool> onFollowScript;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback onComponents;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: models,
    builder: (context, _) {
      final ready = models.ready(settings.effectiveSpeechModel);
      final checked = models.installed.contains(
        settings.verificationSpeechModel,
      );
      return Card(
        margin: const EdgeInsets.only(top: 20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Session setup',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('session-language-${settings.language}'),
                initialValue: settings.language,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Scene language'),
                items: [
                  for (final language in {
                    'en': 'English',
                    'es': 'Spanish',
                    'fr': 'French',
                    'de': 'German',
                    'it': 'Italian',
                  }.entries)
                    DropdownMenuItem(
                      value: language.key,
                      child: Text(language.value),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onLanguageChanged(value);
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Script view',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('Off book'),
                    selected: !followScript,
                    onSelected: (_) => onFollowScript(false),
                  ),
                  ChoiceChip(
                    label: const Text('Follow script'),
                    selected: followScript,
                    onSelected: (_) => onFollowScript(true),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                followScript
                    ? 'Keep the scene beside you. The active line and heard words are highlighted.'
                    : 'Keep your dialogue hidden. Ask for a line when you need it.',
              ),
              const Divider(height: 28),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  ready ? Icons.check_circle_outline : Icons.download_outlined,
                ),
                title: Text(
                  ready ? 'Voices and listening ready' : 'Audio setup needed',
                ),
                subtitle: Text(
                  ready
                      ? 'Available on this device for the selected language.'
                      : 'Download the selected language’s components before rehearsing.',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  checked
                      ? Icons.hearing_outlined
                      : Icons.hearing_disabled_outlined,
                ),
                title: Text(
                  checked
                      ? 'Second hearing ready'
                      : 'Second hearing not installed',
                ),
                subtitle: Text(
                  checked
                      ? 'A separate recognizer checks uncertain words against the same audio.'
                      : 'Recommended setup adds a separate check. Without it, uncertain words need your review.',
                ),
              ),
              OutlinedButton.icon(
                onPressed: onComponents,
                icon: Icon(
                  ready && checked ? Icons.tune : Icons.download_outlined,
                ),
                label: Text(
                  ready && checked
                      ? 'Manage offline audio'
                      : 'Set up offline audio',
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
