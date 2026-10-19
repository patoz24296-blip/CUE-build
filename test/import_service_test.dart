import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cue/services/script_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Real DOCX archive imports paragraphs and adjacent formatting runs locally',
    () async {
      final root = await Directory.systemTemp.createTemp('cue-docx-');
      try {
        final xml = utf8.encode(
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>MARA</w:t></w:r></w:p><w:p><w:r><w:t>Wait for </w:t></w:r><w:r><w:t>me.</w:t></w:r></w:p></w:body></w:document>',
        );
        final archive = Archive()
          ..addFile(ArchiveFile('word/document.xml', xml.length, xml));
        final file = File('${root.path}/scene.docx');
        await file.writeAsBytes(ZipEncoder().encode(archive));
        final production = await ScriptImporter().importFile(file);
        expect(production.characters, ['MARA']);
        expect(production.scenes.single.dialogue.single.text, 'Wait for me.');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test('Malformed DOCX returns a recoverable import message', () async {
    final root = await Directory.systemTemp.createTemp('cue-docx-');
    try {
      final file = File('${root.path}/broken.docx');
      await file.writeAsString('broken');
      await expectLater(
        ScriptImporter().importFile(file),
        throwsA(predicate((e) => e.toString().contains('could not be read'))),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
