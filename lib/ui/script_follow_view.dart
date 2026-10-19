import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/evaluator.dart';

Set<int> heardWordPositions(String text, String transcript) {
  final normalizer = TextNormalizer();
  final heard = normalizer.tokens(transcript);
  final positions = <int>{};
  var cursor = 0;
  for (final (index, word) in text.split(RegExp(r'\s+')).indexed) {
    final tokens = normalizer.tokens(word);
    if (tokens.isEmpty) continue;
    var next = cursor;
    var matches = true;
    for (final token in tokens) {
      final found = heard.indexOf(token, next);
      if (found < 0) {
        matches = false;
        break;
      }
      next = found + 1;
    }
    if (matches) {
      positions.add(index);
      cursor = next;
    }
  }
  return positions;
}

class ScriptFollowView extends StatefulWidget {
  const ScriptFollowView({
    super.key,
    required this.scene,
    required this.activeId,
    required this.character,
    this.transcript = '',
  });
  final Scene scene;
  final String? activeId;
  final String character, transcript;
  @override
  State<ScriptFollowView> createState() => _ScriptFollowViewState();
}

class _ScriptFollowViewState extends State<ScriptFollowView> {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};
  bool _following = true;
  @override
  void initState() {
    super.initState();
    _scheduleFollow();
  }

  @override
  void didUpdateWidget(ScriptFollowView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeId != widget.activeId ||
        oldWidget.scene != widget.scene) {
      _scheduleFollow();
    }
  }

  void _scheduleFollow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_following) return;
      final context = _keys[widget.activeId]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: .22,
          duration: const Duration(milliseconds: 250),
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = widget.scene.entries
        .where((e) => e.id == widget.activeId)
        .firstOrNull;
    final heard = heardWordPositions(active?.text ?? '', widget.transcript);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 10, 6),
          child: Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Follow script',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() => _following = !_following);
                  _scheduleFollow();
                },
                icon: Icon(
                  _following ? Icons.my_location : Icons.location_searching,
                ),
                label: Text(_following ? 'Following' : 'Follow current line'),
              ),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null &&
                  _following) {
                setState(() => _following = false);
              }
              return false;
            },
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 50),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in widget.scene.entries)
                    if (entry.type != EntryType.sceneHeading ||
                        !entry.id.startsWith('boundary-'))
                      Container(
                        key: _keys.putIfAbsent(entry.id, GlobalKey.new),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: entry.id == widget.activeId
                              ? colors.primaryContainer
                              : colors.surface,
                          border: Border(
                            left: BorderSide(
                              width: 3,
                              color: entry.id == widget.activeId
                                  ? colors.primary
                                  : Colors.transparent,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Semantics(
                          selected: entry.id == widget.activeId,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (entry.isDialogue)
                                Text(
                                  '${entry.character}${entry.character == widget.character ? ' · YOU' : ''}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    letterSpacing: 1.3,
                                    color: colors.primary,
                                  ),
                                ),
                              if (entry.parenthetical.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    entry.parenthetical,
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    for (final (index, word)
                                        in entry.text
                                            .split(RegExp(r'\s+'))
                                            .indexed)
                                      TextSpan(
                                        text: '$word ',
                                        style: TextStyle(
                                          backgroundColor:
                                              entry.id == widget.activeId &&
                                                  entry.character ==
                                                      widget.character &&
                                                  heard.contains(index)
                                              ? colors.primary.withValues(
                                                  alpha: .17,
                                                )
                                              : null,
                                        ),
                                      ),
                                  ],
                                ),
                                style: TextStyle(
                                  fontFamily: entry.isDialogue
                                      ? 'Literata'
                                      : null,
                                  fontSize: entry.isDialogue ? 20 : 16,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
