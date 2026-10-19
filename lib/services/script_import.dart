import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';
import '../domain/models.dart';
import '../domain/script_parser.dart';

class ScriptImporter {
  Future<Production?> pick({void Function(String)? status}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'fountain',
        'txt',
        'fdx',
        'docx',
        'pdf',
        'png',
        'jpg',
        'jpeg',
        'heic',
      ],
    );
    if (result == null || result.files.single.path == null) return null;
    return importFile(File(result.files.single.path!), status: status);
  }

  Future<Production> importFile(
    File file, {
    void Function(String)? status,
  }) async {
    if (await file.length() > 100 * 1024 * 1024) {
      throw const ScriptParseException(
        'This file is larger than 100 MB. Export a smaller copy or import one scene at a time.',
      );
    }
    final extension = p.extension(file.path).toLowerCase();
    String text;
    status?.call('Reading your script on this device…');
    switch (extension) {
      case '.docx':
        try {
          final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
          final document = archive.findFile('word/document.xml');
          if (document == null || document.size > 20 * 1024 * 1024) {
            throw const FormatException();
          }
          final xml = XmlDocument.parse(utf8.decode(document.content));
          text = xml.descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'p')
              .map(
                (e) => e.descendants
                    .whereType<XmlElement>()
                    .where((t) => t.name.local == 't')
                    .map((t) => t.innerText)
                    .join(),
              )
              .join('\n');
        } catch (_) {
          throw const ScriptParseException(
            'This Word document could not be read. Export it as plain text or Fountain and try again.',
          );
        }
      case '.pdf':
        await pdfrxFlutterInitialize();
        PdfDocument? document;
        try {
          document = await PdfDocument.openFile(file.path);
          final pages = <String>[];
          for (final page in document.pages) {
            status?.call(
              'Reading page ${page.pageNumber} of ${document.pages.length}…',
            );
            var pageText = (await page.loadText())?.fullText ?? '';
            if (pageText.trim().length < 20) {
              final rendered = await page.render(
                fullWidth: page.width * 2,
                fullHeight: page.height * 2,
              );
              if (rendered == null) {
                throw const ScriptParseException(
                  'A scanned page could not be rendered. Try a clearer scan.',
                );
              }
              try {
                final image = await rendered.createImage();
                try {
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  if (bytes == null) {
                    throw const FormatException('No page image');
                  }
                  final temporary = File(
                    p.join(
                      (await getTemporaryDirectory()).path,
                      'cue-ocr-${newId()}.png',
                    ),
                  );
                  try {
                    await temporary.writeAsBytes(bytes.buffer.asUint8List());
                    pageText = await _ocr(temporary);
                  } finally {
                    if (await temporary.exists()) await temporary.delete();
                  }
                } finally {
                  image.dispose();
                }
              } finally {
                rendered.dispose();
              }
            }
            pages.add(pageText);
          }
          text = pages.join('\n\n');
        } on ScriptParseException {
          rethrow;
        } catch (_) {
          throw const ScriptParseException(
            'This PDF could not be read. Check whether it is damaged or password protected.',
          );
        } finally {
          await document?.dispose();
        }
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.heic':
        text = await _ocr(file);
      default:
        try {
          text = utf8.decode(await file.readAsBytes());
        } catch (_) {
          throw const ScriptParseException(
            'This text file is not UTF-8. Save a UTF-8 copy and try again.',
          );
        }
    }
    return ScriptParser().parse(text, filename: p.basename(file.path));
  }

  Future<String> _ocr(File file) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      Process? process;
      try {
        process = await Process.start('tesseract', [
          file.path,
          'stdout',
          '-l',
          'eng',
          '--psm',
          '6',
        ]);
        final output = utf8.decoder.bind(process.stdout).join();
        final diagnostics = utf8.decoder.bind(process.stderr).join();
        final code = await process.exitCode.timeout(
          const Duration(seconds: 90),
        );
        final text = await output;
        await diagnostics;
        if (code != 0 || text.trim().isEmpty) {
          throw const ScriptParseException(
            'No readable text was found. Use a clear, straight-on scan or photo.',
          );
        }
        return text;
      } on ProcessException {
        throw const ScriptParseException(
          'Install the free Tesseract OCR engine on this computer to import photos and scanned PDFs. Text PDF, Fountain, TXT, DOCX and FDX import work without it.',
        );
      } finally {
        process?.kill();
      }
    }
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      if (result.text.trim().isEmpty) {
        throw const ScriptParseException(
          'No readable text was found. Use a well-lit, straight-on photo.',
        );
      }
      return result.text;
    } finally {
      await recognizer.close();
    }
  }
}
