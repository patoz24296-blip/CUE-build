import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:cue/main.dart';
import 'package:cue/data/app_controller.dart';
import 'package:cue/data/database.dart';
import 'package:cue/data/model_manager.dart';
import 'package:cue/domain/models.dart';
import 'package:cue/services/local_audio.dart';
import 'package:cue/services/script_import.dart';
import 'package:cue/services/semantic.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Installed iPhone import-review-role flow uses real local SQLite',
    (tester) async {
      final root = await getApplicationSupportDirectory();
      final database = await CueDatabase.open(
        path: p.join(root.path, 'integration.sqlite'),
      );
      for (final production in await database.productions()) {
        await database.deleteProduction(production.id);
      }
      final controller = AppController(
        database: database,
        models: ModelManager(Directory(p.join(root.path, 'test-models'))),
        settings: const AppSettings(),
      );
      await tester.pumpWidget(CueApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try the original sample scene'));
      await tester.pumpAndSettle();
      expect(find.text('Script check'), findsOneWidget);
      await tester.tap(find.text('Script looks good'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'MARA'));
      await tester.runAsync(() async {
        for (
          var n = 0;
          n < 50 && controller.productions.single.selectedCharacter != 'MARA';
          n++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      await tester.pumpAndSettle();
      expect(controller.productions.single.selectedCharacter, 'MARA');
      expect((await database.productions()).single.lineCount, 16);
      await tester.pumpWidget(const SizedBox.shrink());
      final pdf = File(p.join(root.path, 'script.pdf'));
      final pdfBytes = await rootBundle.load('assets/import-test.pdf');
      await pdf.writeAsBytes(pdfBytes.buffer.asUint8List());
      final imported = await ScriptImporter().importFile(pdf);
      expect(imported.characters, contains('MARA'));
      expect(
        imported.scenes.expand((s) => s.dialogue).map((e) => e.text).join(' '),
        contains('Wait for me at seven tomorrow.'),
      );
      await database.close();
    },
  );
  testWidgets(
    'iPhone frameworks run real offline recognition, VAD, TTS and OCR',
    (tester) async {
      final root = p.join(
        (await getApplicationSupportDirectory()).path,
        'cue-test-fixtures',
      );
      expect(
        await File(p.join(root, 'input.wav')).exists(),
        isTrue,
        reason:
            'CI must install verified fixtures into the simulator container',
      );
      await expectLater(
        const MethodChannel(
          'studio.cue/export',
        ).invokeMethod<bool>('exportRecording', {'path': '/outside/CUE.wav'}),
        throwsA(isA<PlatformException>()),
      );
      sherpa.initBindings();
      final input = sherpa.readWave(p.join(root, 'input.wav'));
      final asr = await InferenceWorker.open({
        'type': 'asr',
        'root': p.join(root, 'moonshine'),
        'prefix': '',
        'family': 'moonshine',
      });
      final vad = await InferenceWorker.open({
        'type': 'vad',
        'root': p.join(root, 'vad'),
        'sensitivity': .5,
      });
      final tts = await InferenceWorker.open({
        'type': 'tts',
        'root': p.join(root, 'kokoro'),
        'family': 'kokoro',
        'language': 'en',
      });
      try {
        expect(
          (await asr.call('transcribe', {'samples': input.samples}) as String)
              .toLowerCase(),
          contains('yellow lamps'),
        );
        var speech = false;
        for (var i = 0; i + 512 < input.samples.length; i += 512) {
          speech =
              await vad.call('vad', {
                    'samples': Float32List.sublistView(
                      input.samples,
                      i,
                      i + 512,
                    ),
                  })
                  as bool ||
              speech;
        }
        expect(speech, isTrue);
        final generated = p.join(root, 'partner.wav');
        await tts.call('speak', {
          'text': 'Meet me at seven tomorrow.',
          'voice': 1003,
          'speed': 1.0,
          'path': generated,
        });
        expect(sherpa.readWave(generated).samples.length, greaterThan(22050));
        final meaning = await BuiltinMeaning.open(
          p.join(root, 'meaning', 'qwen2.5-0.5b-instruct-q4_k_m.gguf'),
        );
        final embeddings = await BuiltinEmbeddings.open(
          p.join(root, 'embeddings', 'nomic-embed-text-v1.5.Q4_K_M.gguf'),
        );
        try {
          final judgment = await meaning.judge(
            expected: 'Meet me at seven tomorrow.',
            spoken: 'Meet me at seven tomorrow.',
            anchors: ['7'],
            mode: AccuracyMode.loose,
          );
          expect(judgment?.preserved, isTrue);
          expect(
            await embeddings.embed('Meet me at seven tomorrow.'),
            hasLength(768),
          );
        } finally {
          await meaning.dispose();
          await embeddings.dispose();
        }
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
        final painter = TextPainter(
          text: const TextSpan(
            text: 'MARA\nWait for me.',
            style: TextStyle(fontSize: 64, color: Colors.black),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 900);
        painter.paint(canvas, const Offset(40, 40));
        final picture = recorder.endRecording();
        final image = await picture.toImage(1000, 300);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final photo = File(p.join(root, 'ocr.png'));
        await photo.writeAsBytes(bytes!.buffer.asUint8List());
        final imported = await ScriptImporter().importFile(photo);
        expect(imported.characters, contains('MARA'));
        expect(
          imported.scenes
              .expand((s) => s.dialogue)
              .map((e) => e.text)
              .join(' ')
              .toLowerCase(),
          contains('wait for me'),
        );
        image.dispose();
        picture.dispose();
        painter.dispose();
      } finally {
        await asr.dispose();
        await vad.dispose();
        await tts.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
