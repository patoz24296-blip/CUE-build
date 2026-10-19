import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cue/main.dart';
import 'package:cue/data/app_controller.dart';
import 'package:cue/data/database.dart';
import 'package:cue/data/model_manager.dart';
import 'package:cue/domain/models.dart';
import 'package:cue/domain/script_parser.dart';
import 'package:cue/domain/evaluator.dart';
import 'package:cue/domain/rehearsal_engine.dart';
import 'package:cue/ui/rehearsal_page.dart';
import 'package:cue/ui/settings_page.dart';
import 'package:cue/ui/session_setup_card.dart';
import 'package:cue/ui/script_follow_view.dart';
import 'fakes.dart';

void main() {
  late AppController controller;
  late Directory temporary;
  setUp(() async {
    sqfliteFfiInit();
    temporary = await Directory.systemTemp.createTemp('cue-tests-');
    controller = AppController(
      database: await CueDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      ),
      models: ModelManager(temporary),
      settings: const AppSettings(),
    );
  });
  tearDown(() async {
    await controller.database.close();
    controller.models.dispose();
    await temporary.delete(recursive: true);
  });
  testWidgets(
    'Small iPhone with enlarged text can read settings without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: SettingsPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'Session preparation exposes language, script view and audio readiness',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      controller.models.installed.addAll({
        'moonshine',
        'kokoro',
        'vad',
        'whisper-base',
      });
      var settings = const AppSettings();
      var follow = false, componentsOpened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
                child: ListView(
                  children: [
                    SessionSetupCard(
                      models: controller.models,
                      settings: settings,
                      followScript: follow,
                      onFollowScript: (value) => update(() => follow = value),
                      onLanguageChanged: (value) => update(
                        () => settings = settings.change('language', value),
                      ),
                      onComponents: () => componentsOpened = true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Second hearing ready'), findsOneWidget);
      await tester.ensureVisible(find.text('Follow script'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow script'));
      await tester.pumpAndSettle();
      expect(follow, isTrue);
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spanish').last);
      await tester.pumpAndSettle();
      expect(settings.language, 'es');
      expect(find.text('Audio setup needed'), findsOneWidget);
      expect(find.text('Second hearing not installed'), findsOneWidget);
      await tester.ensureVisible(find.text('Set up offline audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set up offline audio'));
      await tester.pumpAndSettle();
      expect(componentsOpened, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Selected script view opens immediately and lets the actor retry without a score',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final production = ScriptParser()
          .parse(
            'Mara: Meet me at seven tomorrow.\nTheo: All right.\nMara: Wait for me.',
            filename: 'Play.txt',
          )
          .copyWith(selectedCharacter: 'Mara');
      final listener = FakeListening();
      final run = RehearsalEngine(
        production: production,
        scene: production.scenes.single,
        character: 'Mara',
        settings: const AppSettings(variableCues: false),
        listener: listener,
        tts: FakeTts(),
        evaluator: LineEvaluator(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RehearsalPage(
            controller: controller,
            production: production,
            scene: production.scenes.single,
            settings: const AppSettings(),
            followScript: true,
            engineFactory: () async => run,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ScriptFollowView), findsOneWidget);
      expect(find.textContaining('Your line 1 of 2'), findsOneWidget);
      listener.say('Meet me', speaking: true);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Try line again'));
      await tester.tap(find.text('Try line again'));
      await tester.pumpAndSettle();
      expect(run.attempts, isEmpty);
      expect(run.transcript, isEmpty);
      expect(listener.active, isTrue);
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'iPhone first launch -> sample import -> review -> role and scene',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(CueApp(controller: controller));
      expect(find.text('Start with a scene.'), findsOneWidget);
      await tester.tap(find.text('Try the original sample scene'));
      await tester.pumpAndSettle();
      expect(find.text('Script check'), findsOneWidget);
      await tester.tap(find.text('Script looks good'));
      await tester.pumpAndSettle();
      expect(find.text('Who are you playing?'.toUpperCase()), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'MARA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('INT. OLD LIGHTHOUSE - NIGHT'));
      await tester.pumpAndSettle();
      expect(controller.productions.single.selectedCharacter, 'MARA');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Actor dialogue hidden -> hands-free run -> results -> repeat', (
    tester,
  ) async {
    final production = ScriptParser()
        .parse(
          'INT. ROOM - DAY\n\nJACK\nWhere are you going?\n\nMARA\nMeet me at seven tomorrow.\n',
          filename: 'scene.fountain',
        )
        .copyWith(selectedCharacter: 'MARA');
    await controller.save(production);
    var listener = FakeListening();
    Future<RehearsalEngine> create() async {
      listener = FakeListening();
      return RehearsalEngine(
        production: production,
        scene: production.scenes.single,
        character: 'MARA',
        settings: const AppSettings(variableCues: false),
        listener: listener,
        tts: FakeTts(),
        evaluator: LineEvaluator(),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: RehearsalPage(
          controller: controller,
          production: production,
          scene: production.scenes.single,
          settings: const AppSettings(),
          engineFactory: create,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hidden-actor-line')), findsOneWidget);
    expect(find.text('Meet me at seven tomorrow.'), findsNothing);
    listener.say('Meet me at seven tomorrow.');
    await tester.pumpAndSettle();
    expect(find.text('Scene complete.'), findsOneWidget);
    expect(find.text('RUN IT AGAIN'), findsOneWidget);
    await tester.tap(find.text('RUN IT AGAIN'));
    await tester.pumpAndSettle();
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('Meet me at seven tomorrow.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
