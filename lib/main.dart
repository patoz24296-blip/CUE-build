import 'package:flutter/material.dart';
import 'data/app_controller.dart';
import 'ui/library_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final controller = await AppController.open();
    runApp(CueApp(controller: controller));
  } catch (e) {
    runApp(
      MaterialApp(
        theme: cueTheme(Brightness.light),
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'CUE',
                    style: TextStyle(fontSize: 42, fontFamily: 'Literata'),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Your local library could not be opened. Restart CUE and check device storage.',
                  ),
                  const SizedBox(height: 16),
                  Text(e.toString()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CueApp extends StatelessWidget {
  const CueApp({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      title: 'CUE',
      debugShowCheckedModeBanner: false,
      theme: cueTheme(Brightness.light),
      darkTheme: cueTheme(Brightness.dark),
      themeMode: switch (controller.settings.theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(
            MediaQuery.textScalerOf(context).scale(1) *
                controller.settings.textScale,
          ),
        ),
        child: child!,
      ),
      home: LibraryPage(controller: controller),
    ),
  );
}
