import 'package:flutter/material.dart';
import '../data/model_manager.dart';
import '../domain/models.dart';
import 'theme.dart';

class ModelPage extends StatelessWidget {
  const ModelPage({
    super.key,
    required this.models,
    this.speech = 'moonshine',
    this.language = 'en',
  });
  final ModelManager models;
  final String speech, language;
  String get verificationModel => AppSettings(
    language: language,
    speechModel: speech,
  ).verificationSpeechModel;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Offline components')),
    body: ListenableBuilder(
      listenable: models,
      builder: (context, _) => PageBody(
        children: [
          Text(
            'Download once.\nRehearse anywhere.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          const Text(
            'Install Natural scene partner voices and responsive recognition. Everything runs on your device. Recommended setup also includes a second recognizer to check possible hearing errors.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: models.downloading != null
                    ? null
                    : () async {
                        for (final id in [speech, 'vad', 'kokoro']) {
                          if (!models.installed.contains(id)) {
                            await models.install(id);
                          }
                          if (models.error != null) break;
                        }
                      },
                child: const Text('Lightweight setup'),
              ),
              OutlinedButton(
                onPressed: models.downloading != null
                    ? null
                    : () async {
                        for (final id in [
                          speech,
                          verificationModel,
                          'vad',
                          'kokoro',
                        ]) {
                          if (!models.installed.contains(id)) {
                            await models.install(id);
                          }
                          if (models.error != null) break;
                        }
                      },
                child: const Text('Recommended setup'),
              ),
              OutlinedButton(
                onPressed: models.downloading != null
                    ? null
                    : () async {
                        for (final id in [
                          speech,
                          verificationModel,
                          'vad',
                          'kokoro',
                          'meaning',
                          'embeddings',
                        ]) {
                          if (!models.installed.contains(id)) {
                            await models.install(id);
                          }
                          if (models.error != null) break;
                        }
                      },
                child: const Text('Extended setup'),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Extended setup adds local meaning and phrase comparison to the selected listening model. Change recognition quality in Settings.',
            ),
          ),
          if (models.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                models.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          for (final model in models.catalog)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(model.detail),
                    const SizedBox(height: 8),
                    Text(
                      '${(model.bytes / 1024 / 1024).toStringAsFixed(1)} MB · ${models.installed.contains(model.id) ? 'Installed on device' : 'Download when needed'}',
                    ),
                    if (models.downloading == model.id) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: models.progress),
                      const SizedBox(height: 8),
                      Text('${(models.progress * 100).toStringAsFixed(1)}%'),
                      TextButton(
                        onPressed: models.cancel,
                        child: const Text('Cancel · keep downloaded files'),
                      ),
                    ] else if (models.installed.contains(model.id))
                      TextButton(
                        onPressed: models.downloading != null
                            ? null
                            : () async {
                                if (await confirmDeletion(
                                  context,
                                  'Remove ${model.name}? You can download it again.',
                                )) {
                                  await models.delete(model.id);
                                }
                              },
                        child: const Text('Delete component'),
                      )
                    else
                      FilledButton(
                        onPressed: models.downloading != null
                            ? null
                            : () => models.install(model.id),
                        child: const Text('Download / resume'),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          FutureBuilder<int>(
            future: models.diskBytes(),
            builder: (context, snapshot) => Text(
              'Model storage: ${((snapshot.data ?? 0) / 1024 / 1024).toStringAsFixed(1)} MB',
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Kokoro voices support English and Spanish. Switch the rehearsal language in Settings for Spanish recognition and voices. Older basic voices remain available for existing files but are no longer used for rehearsal. Meaning and phrase comparison are optional. Use Wi-Fi for initial downloads.',
          ),
        ],
      ),
    ),
  );
}
