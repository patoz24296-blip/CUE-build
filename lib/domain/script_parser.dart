import 'package:xml/xml.dart';
import 'models.dart';
import 'providers.dart';

class ScriptParseException implements Exception {
  const ScriptParseException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ScriptParser implements ScriptParserProvider {
  @override
  Production parse(String text, {required String filename}) {
    if (filename.toLowerCase().endsWith('.fdx')) {
      return _fdx(text, filename);
    }
    final cleaned = text
        .replaceAll('\u00a0', ' ')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u000c', '\n\n');
    final raw = cleaned.split('\n');
    final lines = _removePageFurniture(raw);
    final cueCounts = <String, int>{};
    final inlineNames = <String>{};
    final inlinePattern = RegExp(
      r'^(@?[\p{L}][\p{L}\p{N} .’\x27_-]{0,45}?)[.:]\s+(.+)$',
      unicode: true,
    );
    bool titleName(String name) => name
        .split(RegExp(r'\s+'))
        .every(
          (w) =>
              w.isNotEmpty && RegExp(r'^[\p{Lu}]', unicode: true).hasMatch(w),
        );
    for (final rawLine in lines) {
      final s = rawLine.trim();
      if (s.length <= 48 &&
          titleName(s) &&
          !RegExp(r'[.!?:;,]').hasMatch(s) &&
          !_sceneHeading(s)) {
        cueCounts.update(s, (n) => n + 1, ifAbsent: () => 1);
      }
      final match = inlinePattern.firstMatch(s);
      if (match != null &&
          titleName(match[1]!) &&
          (s[match[1]!.length] == ':' || match[1] == match[1]!.toUpperCase()) &&
          !_sceneHeading(match[1]!) &&
          !{
            'Title',
            'Author',
            'Credit',
            'Source',
            'Contact',
            'Notes',
            'Copyright',
          }.contains(match[1])) {
        inlineNames.add(match[1]!);
      }
    }
    var title = filename
        .replaceAll(RegExp(r'\.[^.]+$'), '')
        .replaceAll('_', ' ');
    var author = '';
    final scenes = <Scene>[];
    var heading = 'Scene 1';
    var entries = <ScriptEntry>[];
    String? speaker;
    var dialogue = <String>[];
    var parenthetical = '';
    var inMetadata = true, inComment = false, sawMetadata = false;
    void flushDialogue() {
      if (speaker != null && dialogue.isNotEmpty) {
        entries.add(
          ScriptEntry(
            id: newId(),
            type: EntryType.dialogue,
            text: dialogue.join(' ').trim(),
            character: speaker,
            parenthetical: parenthetical,
          ),
        );
      }
      dialogue = [];
      parenthetical = '';
      speaker = null;
    }

    void flushScene() {
      flushDialogue();
      if (entries.isNotEmpty) {
        scenes.add(Scene(id: newId(), heading: heading, entries: entries));
      }
      entries = [];
    }

    for (var i = 0; i < lines.length; i++) {
      var s = lines[i].trim();
      if (s.contains('/*')) {
        inComment = true;
      }
      if (inComment) {
        if (s.contains('*/')) {
          inComment = false;
        }
        continue;
      }
      if (s.isEmpty) {
        flushDialogue();
        continue;
      }
      if (inMetadata &&
          sawMetadata &&
          lines[i].startsWith('   ') &&
          !_isCharacter(s) &&
          inlinePattern.firstMatch(s) == null) {
        continue;
      }
      if (inMetadata &&
          RegExp(
            r'^(Title|Author|Credit|Source|Draft date|Contact|Copyright|Notes):',
            caseSensitive: false,
          ).hasMatch(s)) {
        sawMetadata = true;
        final colon = s.indexOf(':');
        if (s.substring(0, colon).toLowerCase() == 'title') {
          title = s.substring(colon + 1).trim();
        }
        if (s.substring(0, colon).toLowerCase() == 'author') {
          author = s.substring(colon + 1).trim();
        }
        continue;
      }
      inMetadata = false;
      if (s.startsWith('#') || s.startsWith('=') || s.startsWith('[[')) {
        continue;
      }
      if (_sceneHeading(s)) {
        flushScene();
        heading = s.replaceFirst(RegExp(r'^\.(?=[^\.])'), '');
        continue;
      }
      if (RegExp(
            r'^(FADE (IN|OUT)|CUT TO|DISSOLVE TO|THE END|END OF (ACT|SCENE))\b',
            caseSensitive: false,
          ).hasMatch(s) ||
          s.endsWith('TO:')) {
        flushDialogue();
        entries.add(
          ScriptEntry(id: newId(), type: EntryType.stageDirection, text: s),
        );
        continue;
      }
      final inline = inlinePattern.firstMatch(s);
      if (inline != null &&
          (s[inline[1]!.length] == ':' ||
              inline[1] == inline[1]!.toUpperCase()) &&
          _isCharacter(
            inline.group(1)!,
            forced:
                inline.group(1)!.startsWith('@') ||
                (inlineNames.contains(inline[1]) &&
                    (inlineNames.length >= 2 ||
                        (cueCounts[inline[1]] ?? 0) > 1)),
          )) {
        flushDialogue();
        speaker = _characterName(inline.group(1)!);
        final spoken = inline.group(2)!;
        final direction = RegExp(r'^\(([^)]+)\)\s*').firstMatch(spoken);
        if (direction != null) parenthetical = direction[0]!.trim();
        dialogue.add(spoken.substring(direction?.end ?? 0));
        continue;
      }
      final next = i + 1 < lines.length ? lines[i + 1].trim() : '';
      final prevBlank = i == 0 || lines[i - 1].trim().isEmpty;
      final knownCue = (cueCounts[s] ?? 0) >= 2 && titleName(s);
      if (_isCharacter(s, forced: s.startsWith('@') || knownCue) &&
          next.isNotEmpty &&
          !_sceneHeading(next) &&
          (speaker == null || prevBlank || knownCue)) {
        flushDialogue();
        speaker = _characterName(s);
        continue;
      }
      if (s.startsWith('(') && s.endsWith(')') && speaker != null) {
        parenthetical = parenthetical.isEmpty ? s : '$parenthetical $s';
        continue;
      }
      if (s.startsWith('[') && s.endsWith(']') ||
          s.startsWith('!') ||
          (s.startsWith('(') && s.endsWith(')') && speaker == null)) {
        flushDialogue();
        entries.add(
          ScriptEntry(
            id: newId(),
            type: EntryType.stageDirection,
            text: s.replaceFirst(RegExp(r'^!'), ''),
          ),
        );
        continue;
      }
      if (speaker != null) {
        dialogue.add(s);
      } else {
        entries.add(
          ScriptEntry(id: newId(), type: EntryType.stageDirection, text: s),
        );
      }
    }
    flushScene();
    return _validated(
      Production(
        id: newId(),
        title: title.trim().isEmpty ? 'Untitled script' : title,
        author: author,
        scenes: scenes,
        createdAt: DateTime.now(),
        sourceName: filename,
        sourceFormat: filename.split('.').last.toLowerCase(),
      ),
    );
  }

  bool _sceneHeading(String s) => RegExp(
    r'^(\.(?!\.)|(?:INT\.?|EXT\.?|INT\.?/EXT\.?|I/E\.?)\s|(?:ACT|SCENE|ACTO|ESCENA)\s+(?:[\dIVXLCDM]+|ONE|TWO|THREE|FOUR|FIVE|SIX|SEVEN|EIGHT|NINE|TEN)\b)',
    caseSensitive: false,
  ).hasMatch(s);
  bool _isCharacter(String s, {bool forced = false}) {
    final name = _characterName(s);
    if (name.isEmpty ||
        name.length > 48 ||
        _sceneHeading(s) ||
        RegExp(r'[!?;:]').hasMatch(name) ||
        RegExp(r'^\d').hasMatch(name)) {
      return false;
    }
    if (forced) {
      return true;
    }
    return name == name.toUpperCase() &&
        RegExp(r'[\p{L}]', unicode: true).hasMatch(name) &&
        !{
          'CONTINUED',
          'CONTINUED:',
          'MORE',
          'END',
          'FADE IN',
          'FADE OUT',
        }.contains(name) &&
        name.split(' ').length <= 5;
  }

  String _characterName(String s) => s
      .replaceFirst(RegExp(r'^@'), '')
      .replaceAll(
        RegExp(
          r'\s*\((?:V\.?O\.?|O\.?S\.?|CONT[’\x27]?D|CONTINUED|OFF)\)',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'\s*\^$'), '')
      .trim();
  List<String> _removePageFurniture(List<String> lines) {
    final repeated = <String, int>{};
    for (final line in lines) {
      final s = line.trim();
      if (s.isNotEmpty) {
        repeated.update(s, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return lines.where((line) {
      final s = line.trim();
      if (RegExp(
        r'^(?:Page\s+)?\d+(?:\s+of\s+\d+)?[.]?$',
        caseSensitive: false,
      ).hasMatch(s)) {
        return false;
      }
      if (RegExp(
        r'^(?:CONTINUED|\(MORE\))[ :()\d]*$',
        caseSensitive: false,
      ).hasMatch(s)) {
        return false;
      }
      // Only remove recognisable repeated page furniture, never repeated dialogue.
      if ((repeated[s] ?? 0) > 1 &&
          RegExp(
            r'^(?:DRAFT|CONFIDENTIAL|COPYRIGHT|Revision date)\b',
            caseSensitive: false,
          ).hasMatch(s)) {
        return false;
      }
      return true;
    }).toList();
  }

  Production _fdx(String text, String filename) {
    try {
      final doc = XmlDocument.parse(text);
      final content = doc.findAllElements('Content').firstOrNull;
      if (content == null) {
        throw const ScriptParseException(
          'This Final Draft file has no script content.',
        );
      }
      final scenes = <Scene>[];
      var entries = <ScriptEntry>[];
      var heading = 'Scene 1';
      String? speaker;
      var parenthetical = '';
      void flush() {
        if (entries.isNotEmpty) {
          scenes.add(Scene(id: newId(), heading: heading, entries: entries));
        }
        entries = [];
      }

      for (final p in content.findElements('Paragraph')) {
        final type = p.getAttribute('Type');
        final text = p
            .findAllElements('Text')
            .map((e) => e.innerText)
            .join()
            .trim();
        if (text.isEmpty) {
          continue;
        }
        switch (type) {
          case 'Scene Heading':
            flush();
            heading = text;
            speaker = null;
            break;
          case 'Character':
            speaker = _characterName(text);
            parenthetical = '';
            break;
          case 'Parenthetical':
            parenthetical = text;
            break;
          case 'Dialogue':
            if (speaker == null) {
              entries.add(
                ScriptEntry(
                  id: newId(),
                  type: EntryType.stageDirection,
                  text: text,
                ),
              );
            } else {
              entries.add(
                ScriptEntry(
                  id: newId(),
                  type: EntryType.dialogue,
                  text: text,
                  character: speaker,
                  parenthetical: parenthetical,
                ),
              );
              parenthetical = '';
            }
            break;
          default:
            speaker = null;
            entries.add(
              ScriptEntry(
                id: newId(),
                type: EntryType.stageDirection,
                text: text,
              ),
            );
        }
      }
      flush();
      return _validated(
        Production(
          id: newId(),
          title: filename.replaceAll(
            RegExp(r'\.fdx$', caseSensitive: false),
            '',
          ),
          scenes: scenes,
          createdAt: DateTime.now(),
          sourceName: filename,
          sourceFormat: 'fdx',
        ),
      );
    } on ScriptParseException {
      rethrow;
    } catch (_) {
      throw const ScriptParseException(
        'This Final Draft XML is damaged or unsupported. Try exporting it as Fountain.',
      );
    }
  }

  Production _validated(Production p) {
    if (p.lineCount == 0) {
      throw const ScriptParseException(
        'No dialogue was detected. Use character names on their own lines, followed by dialogue, or import a Fountain / Final Draft file.',
      );
    }
    return p;
  }
}

class ScriptEditor {
  Production renameCharacter(
    Production p,
    String from,
    String to,
  ) => p.copyWith(
    selectedCharacter: p.selectedCharacter == from ? to : p.selectedCharacter,
    scenes: p.scenes
        .map(
          (s) => s.copyWith(
            entries: s.entries
                .map((e) => e.character == from ? e.copyWith(character: to) : e)
                .toList(),
          ),
        )
        .toList(),
  );
  Production updateEntry(Production p, String id, ScriptEntry entry) =>
      p.copyWith(
        scenes: p.scenes
            .map(
              (s) => s.copyWith(
                entries: s.entries.map((e) => e.id == id ? entry : e).toList(),
              ),
            )
            .toList(),
      );
  Production removeEntry(Production p, String id) => p.copyWith(
    scenes: p.scenes
        .map(
          (s) =>
              s.copyWith(entries: s.entries.where((e) => e.id != id).toList()),
        )
        .toList(),
  );
  Production splitScene(
    Production p,
    String sceneId,
    String beforeEntry,
    String heading,
  ) {
    final result = <Scene>[];
    for (final s in p.scenes) {
      final index = s.entries.indexWhere((e) => e.id == beforeEntry);
      if (s.id != sceneId || index <= 0) {
        result.add(s);
        continue;
      }
      result.add(s.copyWith(entries: s.entries.take(index).toList()));
      result.add(
        Scene(
          id: newId(),
          heading: heading,
          entries: s.entries.skip(index).toList(),
        ),
      );
    }
    return p.copyWith(scenes: result);
  }

  Production mergeScene(Production p, String sceneId) {
    final scenes = [...p.scenes];
    final index = scenes.indexWhere((s) => s.id == sceneId);
    if (index > 0) {
      scenes[index - 1] = scenes[index - 1].copyWith(
        entries: [...scenes[index - 1].entries, ...scenes[index].entries],
      );
      scenes.removeAt(index);
    }
    return p.copyWith(scenes: scenes);
  }
}
