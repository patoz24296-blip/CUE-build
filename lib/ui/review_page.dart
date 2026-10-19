import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/script_parser.dart';
import 'theme.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.production});
  final Production production;
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late Production _production = widget.production;
  final _editor = ScriptEditor();
  String _search = '';
  Future<String?> _text(String title, String initial) async {
    final input = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: input, autofocus: true, maxLines: 3),
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
    input.dispose();
    return result;
  }

  Future<void> _edit(ScriptEntry entry) async {
    final text = TextEditingController(text: entry.text);
    final anchors = TextEditingController(
      text: entry.protectedPhrases.join(', '),
    );
    var owner = entry.character ?? 'Stage direction';
    final result = await showDialog<ScriptEntry>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Check this line'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: owner,
                  decoration: const InputDecoration(labelText: 'Who speaks?'),
                  items: ['Stage direction', ..._production.characters]
                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                      .toList(),
                  onChanged: (v) => setDialog(() => owner = v!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: text,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Script text'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: anchors,
                  decoration: const InputDecoration(
                    labelText: 'Protect words or phrases',
                    helperText: 'Separate phrases with commas',
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
                ScriptEntry(
                  id: entry.id,
                  type: owner == 'Stage direction'
                      ? EntryType.stageDirection
                      : EntryType.dialogue,
                  character: owner == 'Stage direction' ? null : owner,
                  text: text.text.trim(),
                  parenthetical: entry.parenthetical,
                  protectedPhrases: anchors.text
                      .split(',')
                      .map((a) => a.trim())
                      .where((a) => a.isNotEmpty)
                      .toList(),
                  variants: entry.variants,
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    text.dispose();
    anchors.dispose();
    if (result != null && mounted) {
      setState(
        () => _production = _editor.updateEntry(_production, entry.id, result),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Script check')),
    body: PageBody(
      children: [
        Text(
          _production.title,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          '${_production.characters.length} characters · ${_production.scenes.length} scenes · ${_production.lineCount} dialogue lines',
        ),
        const SizedBox(height: 12),
        const Text(
          'Check the cast and a few lines. Tap a line to correct wording, ownership or protected phrases.',
        ),
        TextButton(
          onPressed: () async {
            final title = await _text('Script title', _production.title);
            if (title != null && title.isNotEmpty) {
              setState(() => _production = _production.copyWith(title: title));
            }
          },
          child: const Text('Edit title'),
        ),
        const SectionLabel('Characters'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _production.characters
              .map(
                (name) => ActionChip(
                  label: Text(name),
                  onPressed: () async {
                    final changed = await _text('Rename or merge $name', name);
                    if (changed != null && changed.isNotEmpty) {
                      setState(
                        () => _production = _editor.renameCharacter(
                          _production,
                          name,
                          changed.toUpperCase(),
                        ),
                      );
                    }
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search dialogue',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (s) => setState(() => _search = s.toLowerCase()),
        ),
        for (final scene in _production.scenes) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  scene.heading,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Scene boundary options',
                onSelected: (v) async {
                  if (v == 'merge') {
                    setState(
                      () => _production = _editor.mergeScene(
                        _production,
                        scene.id,
                      ),
                    );
                  } else {
                    final name = await _text('Scene heading', scene.heading);
                    if (name != null) {
                      setState(
                        () => _production = _production.copyWith(
                          scenes: _production.scenes
                              .map(
                                (s) => s.id == scene.id
                                    ? s.copyWith(heading: name)
                                    : s,
                              )
                              .toList(),
                        ),
                      );
                    }
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: Text('Rename scene'),
                  ),
                  if (_production.scenes.first.id != scene.id)
                    const PopupMenuItem(
                      value: 'merge',
                      child: Text('Merge into previous scene'),
                    ),
                ],
              ),
            ],
          ),
          for (final entry in scene.entries.where(
            (e) => e.text.toLowerCase().contains(_search),
          ))
            ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              title: Text(
                entry.character ?? 'Stage direction',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              subtitle: Text(
                entry.text,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              onTap: () => _edit(entry),
              trailing: PopupMenuButton<String>(
                tooltip: 'Line options',
                onSelected: (v) async {
                  if (v == 'remove') {
                    setState(
                      () => _production = _editor.removeEntry(
                        _production,
                        entry.id,
                      ),
                    );
                  } else {
                    final name = await _text(
                      'New scene heading',
                      'Scene ${_production.scenes.length + 1}',
                    );
                    if (name != null && name.isNotEmpty) {
                      setState(
                        () => _production = _editor.splitScene(
                          _production,
                          scene.id,
                          entry.id,
                          name,
                        ),
                      );
                    }
                  }
                },
                itemBuilder: (_) => [
                  if (scene.entries.first.id != entry.id)
                    const PopupMenuItem(
                      value: 'split',
                      child: Text('Start a scene here'),
                    ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove line / page header'),
                  ),
                ],
              ),
            ),
        ],
      ],
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _production.lineCount == 0
              ? null
              : () => Navigator.pop(context, _production),
          child: const Text('Script looks good'),
        ),
      ),
    ),
  );
}
