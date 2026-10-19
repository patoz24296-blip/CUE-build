import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../domain/models.dart';
import '../services/model_storage_access.dart';
import 'database.dart';
import 'model_manager.dart';
import 'recording_store.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.database,
    required this.models,
    required this.settings,
    this.productions = const [],
  });
  final CueDatabase database;
  final ModelManager models;
  RecordingStore? recordings;
  AppSettings settings;
  List<Production> productions;
  static Future<AppController> open() async {
    final database = await CueDatabase.open();
    final root = await getApplicationSupportDirectory();
    var settings = await database.settings();
    final canRestore =
        settings.modelStoragePath.isEmpty ||
        await ModelStorageAccess.restore(settings.modelStoragePath);
    var models = ModelManager(
      Directory(
        canRestore &&
                settings.modelStoragePath.isNotEmpty &&
                !Platform.isIOS &&
                !Platform.isAndroid
            ? settings.modelStoragePath
            : p.join(root.path, 'models'),
      ),
    );
    try {
      await models.load();
    } on FileSystemException {
      if (settings.modelStoragePath.isEmpty) rethrow;
      models.dispose();
      models = ModelManager(Directory(p.join(root.path, 'models')));
      await models.load();
    }
    if (settings.modelStoragePath.isNotEmpty &&
        models.root.path != settings.modelStoragePath) {
      settings = settings.change('modelStoragePath', '');
      await database.saveSettings(settings);
      models.error =
          'Your previous component folder could not be opened. Choose it again in Settings to restore access. Existing files were kept.';
    }
    final controller = AppController(
      database: database,
      models: models,
      settings: settings,
      productions: await database.productions(),
    );
    controller.recordings = RecordingStore(
      database,
      Directory(p.join(root.path, 'cue-recordings')),
    );
    await controller.recordings!.clean(controller.settings);
    return controller;
  }

  Future<void> refresh() async {
    productions = await database.productions();
    notifyListeners();
  }

  Future<void> save(Production production) async {
    await database.saveProduction(production);
    await refresh();
  }

  Future<void> change(String key, dynamic value) async {
    settings = settings.change(key, value);
    await database.saveSettings(settings);
    notifyListeners();
  }

  Future<void> deleteHistory({String? productionId}) async {
    await recordings?.deleteAll(productionId: productionId);
    await database.deleteHistory(productionId: productionId);
    notifyListeners();
  }

  Future<void> deleteProduction(String id) async {
    await recordings?.deleteAll(productionId: id);
    await database.deleteProduction(id);
    await refresh();
  }

  @override
  void dispose() {
    models.dispose();
    database.close();
    super.dispose();
  }
}
