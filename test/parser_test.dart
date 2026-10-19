import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cue/domain/models.dart';
import 'package:cue/domain/script_parser.dart';

void main() {
  final parser = ScriptParser();
  test(
    'Original sample has two scenes, two roles and intact repeated dialogue',
    () {
      final production = parser.parse(
        File('assets/sample.fountain').readAsStringSync(),
        filename: 'sample.fountain',
      );
      expect(production.title, 'The Last Light');
      expect(production.scenes.length, 2);
      expect(production.characters.toSet(), {'MARA', 'THEO'});
      expect(production.lineCount, 16);
      expect(
        production.scenes.first.dialogue.first.text,
        "Tell Ellis I'll come tomorrow.",
      );
      expect(production.scenes.first.dialogue[2].parenthetical, '(quietly)');
      expect(
        production.scenes.first.dialogue.any((l) => l.isInterrupted),
        isTrue,
      );
    },
  );
  test('Fountain forced character, continuation, dual dialogue and action', () {
    final production = parser.parse(
      'Title: Test\n    Title metadata\n\n.INT. ROOM - NIGHT\n\nTHE DOOR SLAMS\n\n@Mary\nHello there.\n\nJOHN (CONT\'D) ^\n(softly)\nI will not leave.\n\n!DOOR CLOSES\n',
      filename: 'test.fountain',
    );
    expect(production.characters.toSet(), {'Mary', 'JOHN'});
    expect(
      production.scenes.single.entries
          .where((e) => e.type == EntryType.stageDirection)
          .length,
      2,
    );
    expect(production.scenes.single.dialogue.last.parenthetical, '(softly)');
  });
  test('Plain play inline ownership and page furniture', () {
    final production = parser.parse(
      'SCENE I\n\nJACK: Hello.\n\nPage 1 of 2\nJILL: Goodbye.\n',
      filename: 'play.txt',
    );
    expect(production.lineCount, 2);
    expect(production.characters.toSet(), {'JACK', 'JILL'});
  });
  test('FDX preserves structured dialogue and parentheticals', () {
    final production = parser.parse(
      '<FinalDraft><Content><Paragraph Type="Scene Heading"><Text>INT. ROOM</Text></Paragraph><Paragraph Type="Character"><Text>MARA</Text></Paragraph><Paragraph Type="Parenthetical"><Text>(quietly)</Text></Paragraph><Paragraph Type="Dialogue"><Text>Wait.</Text><Text> Wait.</Text></Paragraph></Content></FinalDraft>',
      filename: 'test.fdx',
    );
    expect(production.scenes.single.dialogue.single.text, 'Wait. Wait.');
    expect(production.scenes.single.dialogue.single.parenthetical, '(quietly)');
  });
  test('Corrupt XML and text without dialogue fail usefully', () {
    expect(
      () => parser.parse('<bad>', filename: 'bad.fdx'),
      throwsA(isA<ScriptParseException>()),
    );
    expect(
      () => parser.parse('An empty room.', filename: 'bad.txt'),
      throwsA(isA<ScriptParseException>()),
    );
  });
  test('Boundary edits preserve IDs and character merge updates role', () {
    final production = parser
        .parse(
          File('assets/sample.fountain').readAsStringSync(),
          filename: 'sample.fountain',
        )
        .copyWith(selectedCharacter: 'MARA');
    final editor = ScriptEditor();
    final first = production.scenes.first;
    final split = editor.splitScene(
      production,
      first.id,
      first.dialogue[3].id,
      'Part two',
    );
    final merged = editor.mergeScene(split, split.scenes[1].id);
    expect(
      merged.scenes.first.entries.map((e) => e.id),
      first.entries.map((e) => e.id),
    );
    expect(editor.renameCharacter(production, 'MARA', 'THEO').characters, [
      'THEO',
    ]);
    expect(
      editor.renameCharacter(production, 'MARA', 'THEO').selectedCharacter,
      'THEO',
    );
  });
}
