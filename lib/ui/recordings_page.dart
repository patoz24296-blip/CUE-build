import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../data/recording_store.dart';
import '../services/export_service.dart';
import 'theme.dart';

class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key, required this.store, this.productionId});
  final RecordingStore store;
  final String? productionId;
  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  final _player = AudioPlayer();
  late Future<List<Map<String, Object?>>> _rows = widget.store.list(
    productionId: widget.productionId,
  );
  String? _playing;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _rows = widget.store.list(productionId: widget.productionId);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Local recordings')),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _rows,
      builder: (context, snapshot) => PageBody(
        children: [
          const Text(
            'Recordings remain on this device. Export only when you choose a destination. Deleting a recording cannot delete an exported copy.',
          ),
          if (snapshot.hasError)
            Text('Could not load recordings: ${snapshot.error}'),
          if (snapshot.data?.isEmpty ?? false)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text(
                'No recordings. Enable recording in Settings before your next run.',
              ),
            ),
          for (final row in snapshot.data ?? <Map<String, Object?>>[])
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['title'] ?? 'Rehearsal'} · ${row['character'] ?? ''}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      DateTime.parse(
                        row['created_at'] as String,
                      ).toLocal().toString().split('.').first,
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _act(() async {
                                  if (_playing == row['id']) {
                                    await _player.stop();
                                    _playing = null;
                                  } else {
                                    await _player.stop();
                                    await _player.play(
                                      DeviceFileSource(row['path'] as String),
                                    );
                                    _playing = row['id'] as String;
                                  }
                                }),
                          icon: Icon(
                            _playing == row['id']
                                ? Icons.stop
                                : Icons.play_arrow,
                          ),
                          label: Text(_playing == row['id'] ? 'Stop' : 'Play'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _act(
                                  () => ExportService.file(
                                    File(row['path'] as String),
                                    '${ExportService.safeName(row['title'] as String? ?? 'CUE')}-${row['id']}.wav',
                                  ),
                                ),
                          child: const Text('Export WAV'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (await confirmDeletion(
                                    context,
                                    'Delete this recording from CUE?',
                                  )) {
                                    await _act(() async {
                                      await _player.stop();
                                      _playing = null;
                                      await widget.store.delete(row);
                                    });
                                  }
                                },
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (snapshot.data?.isNotEmpty ?? false)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (await confirmDeletion(
                        context,
                        'Delete all these recordings from CUE?',
                      )) {
                        await _act(() async {
                          await _player.stop();
                          _playing = null;
                          await widget.store.deleteAll(
                            productionId: widget.productionId,
                          );
                        });
                      }
                    },
              child: const Text('Delete all recordings'),
            ),
        ],
      ),
    ),
  );
}
