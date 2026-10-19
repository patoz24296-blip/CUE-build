import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/app_controller.dart';
import '../domain/models.dart';
import '../domain/script_parser.dart';
import '../services/script_import.dart';
import 'review_page.dart';
import 'production_page.dart';
import 'settings_page.dart';
import 'theme.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  bool _busy = false;
  String _status = '';
  Future<void> _add({bool sample = false}) async {
    setState(() => _busy = true);
    try {
      final production = sample
          ? ScriptParser().parse(
              await rootBundle.loadString('assets/sample.fountain'),
              filename: 'The Last Light.fountain',
            )
          : await ScriptImporter().pick(
              status: (s) {
                if (mounted) setState(() => _status = s);
              },
            );
      if (!mounted || production == null) return;
      final reviewed = await Navigator.push<Production>(
        context,
        MaterialPageRoute(builder: (_) => ReviewPage(production: production)),
      );
      if (reviewed == null) return;
      await widget.controller.save(reviewed);
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductionPage(
              controller: widget.controller,
              production: reviewed,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'CUE',
        style: TextStyle(letterSpacing: 5, fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          tooltip: 'Settings',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SettingsPage(controller: widget.controller),
            ),
          ),
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => PageBody(
        children: [
          Text(
            'Your next\ngreat rehearsal.',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 16),
          const Text(
            'A scene partner, whenever you need one.',
            style: TextStyle(fontSize: 17),
          ),
          const SectionLabel('My scripts'),
          if (widget.controller.productions.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.menu_book_rounded, size: 32),
                    const SizedBox(height: 16),
                    Text(
                      'Start with a scene.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Import your script, choose your role, and put the phone down. CUE reads opposite you.',
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _add(sample: true),
                      child: const Text('Try the original sample scene'),
                    ),
                  ],
                ),
              ),
            ),
          for (final production in widget.controller.productions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  title: Text(
                    production.title,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall?.copyWith(fontFamily: 'Literata'),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FutureBuilder<int>(
                      future: widget.controller.database.offBookLines(
                        production,
                      ),
                      builder: (context, snapshot) {
                        final total = production.scenes
                            .expand((s) => s.dialogue)
                            .where(
                              (e) =>
                                  e.character == production.selectedCharacter,
                            )
                            .length;
                        return Text(
                          '${production.selectedCharacter ?? 'Choose your role'} · ${production.scenes.length} scenes · ${production.lineCount} lines${total > 0 && snapshot.hasData ? '\n${((snapshot.data! / total) * 100).round()}% off book · latest attempts without hints' : ''}',
                        );
                      },
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProductionPage(
                        controller: widget.controller,
                        production: production,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _add(),
            icon: const Icon(Icons.add),
            label: const Text('Add script'),
          ),
          if (widget.controller.productions.isNotEmpty)
            TextButton(
              onPressed: _busy ? null : () => _add(sample: true),
              child: const Text('Add the sample scene'),
            ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(_status),
                ],
              ),
            ),
          const SizedBox(height: 32),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Private by design. Scripts, audio processing and rehearsal history stay on your device.',
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
