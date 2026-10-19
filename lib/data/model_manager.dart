import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

String safeModelPath(String root, String relative) {
  if (relative.contains('\\') ||
      p.posix.isAbsolute(relative) ||
      relative.split('/').any((s) => s == '..' || s.isEmpty)) {
    throw const FormatException('Unsafe model file path');
  }
  final result = p.normalize(p.join(root, relative));
  if (!p.isWithin(root, result)) {
    throw const FormatException('Model path escapes its folder');
  }
  return result;
}

class ModelSpec {
  ModelSpec(Map<String, dynamic> m)
    : id = m['id'],
      name = m['name'],
      detail = m['detail'],
      bytes = m['bytes'],
      files = (m['files'] as List).cast<Map<String, dynamic>>();
  final String id, name, detail;
  final int bytes;
  final List<Map<String, dynamic>> files;
}

class ModelManager extends ChangeNotifier {
  ModelManager(this.root);
  Directory root;
  List<ModelSpec> catalog = [];
  final installed = <String>{};
  String? downloading, error;
  double progress = 0;
  bool _cancelled = false;
  HttpClient? _client;
  Future<void> load() async {
    await root.create(recursive: true);
    catalog =
        (jsonDecode(await rootBundle.loadString('assets/models.json')) as List)
            .map((m) => ModelSpec(m as Map<String, dynamic>))
            .toList();
    for (final model in catalog) {
      final folder = Directory(path(model.id));
      if (await File(p.join(folder.path, '.ready')).exists() &&
          await _hasFiles(model)) {
        installed.add(model.id);
      }
    }
    notifyListeners();
  }

  String path(String id) => p.join(root.path, id);
  Future<void> relocate(Directory destination) async {
    if (downloading != null) {
      throw StateError(
        'Finish or cancel the download before moving components.',
      );
    }
    final old = root;
    if (p.equals(p.absolute(old.path), p.absolute(destination.path))) return;
    if (p.isWithin(old.path, destination.path) ||
        p.isWithin(destination.path, old.path)) {
      throw const FileSystemException(
        'Choose a separate folder for model storage.',
      );
    }
    await destination.create(recursive: true);
    for (final id in installed) {
      final spec = catalog.firstWhere((s) => s.id == id);
      final folder = Directory(p.join(destination.path, id));
      await folder.create(recursive: true);
      for (final item in spec.files) {
        final target = File(safeModelPath(folder.path, item['path']));
        if (await _valid(target, item)) continue;
        await target.parent.create(recursive: true);
        final copy = File('${target.path}.relocating');
        await File(safeModelPath(path(id), item['path'])).copy(copy.path);
        if (!await _valid(copy, item)) {
          throw const FileSystemException(
            'Copied component failed verification; previous storage is still intact.',
          );
        }
        if (await target.exists()) await target.delete();
        await copy.rename(target.path);
      }
      await File(p.join(folder.path, '.ready')).writeAsString('verified');
    }
    root = destination;
    notifyListeners();
  }

  bool ready(String speech) => installed.containsAll({speech, 'vad', 'kokoro'});
  Future<bool> _hasFiles(ModelSpec spec) async {
    for (final f in spec.files) {
      final file = File(safeModelPath(path(spec.id), f['path']));
      if (!await file.exists() || await file.length() != f['bytes']) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _valid(File file, Map<String, dynamic> spec) async {
    if (!await file.exists() || await file.length() != spec['bytes']) {
      return false;
    }
    if (spec['algorithm'] == 'git-sha1') {
      final controller = StreamController<List<int>>();
      final digest = sha1.bind(controller.stream).first;
      controller.add(utf8.encode('blob ${spec['bytes']}\x00'));
      await controller.addStream(file.openRead());
      await controller.close();
      return (await digest).toString() == spec['digest'];
    }
    return (await sha256.bind(file.openRead()).first).toString() ==
        spec['digest'];
  }

  Future<void> install(String id) async {
    if (downloading != null) return;
    final spec = catalog.firstWhere((m) => m.id == id);
    downloading = id;
    error = null;
    progress = 0;
    _cancelled = false;
    notifyListeners();
    _client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    var received = 0;
    final staging = Directory('${path(id)}.staging');
    try {
      await staging.create(recursive: true);
      for (final f in spec.files) {
        if (_cancelled) {
          throw const HttpException('Download cancelled. Retry to resume.');
        }
        final file = File(safeModelPath(staging.path, f['path']));
        await file.parent.create(recursive: true);
        if (await _valid(file, f)) {
          received += f['bytes'] as int;
          progress = received / spec.bytes;
          notifyListeners();
          continue;
        }
        final part = File('${file.path}.part');
        if (await _valid(part, f)) {
          await part.rename(file.path);
          received += f['bytes'] as int;
          progress = received / spec.bytes;
          notifyListeners();
          continue;
        }
        var offset = await part.exists() ? await part.length() : 0;
        if (offset >= f['bytes']) {
          await part.delete();
          offset = 0;
        }
        final request = await _client!.getUrl(Uri.parse(f['url']));
        if (offset > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        }
        final response = await request.close().timeout(
          const Duration(seconds: 45),
        );
        if (response.statusCode == 200) {
          offset = 0;
        } else if (response.statusCode != 206) {
          throw HttpException(
            'Download returned ${response.statusCode}. Please retry.',
          );
        }
        final sink = part.openWrite(
          mode: offset > 0 ? FileMode.append : FileMode.write,
        );
        var current = offset;
        try {
          await for (final bytes in response.timeout(
            const Duration(seconds: 45),
          )) {
            if (_cancelled) {
              throw const HttpException('Download cancelled. Retry to resume.');
            }
            current += bytes.length;
            if (current > f['bytes']) {
              throw const FormatException(
                'Model download exceeded its expected size',
              );
            }
            sink.add(bytes);
            progress = (received + current) / spec.bytes;
            notifyListeners();
          }
        } finally {
          await sink.close();
        }
        if (!await _valid(part, f)) {
          await part.delete();
          throw const FormatException(
            'Model checksum did not match. Retry the download.',
          );
        }
        await part.rename(file.path);
        received += f['bytes'] as int;
      }
      if (_cancelled) {
        throw const HttpException('Download cancelled. Retry to resume.');
      }
      final destination = Directory(path(id));
      if (await destination.exists()) await destination.delete(recursive: true);
      await staging.rename(destination.path);
      await File(p.join(destination.path, '.ready')).writeAsString('verified');
      installed.add(id);
    } on FileSystemException catch (e) {
      error =
          'Could not store the model. Check available device storage. ${e.osError?.message ?? ''}';
    } catch (e) {
      error = e.toString();
    } finally {
      _client?.close(force: true);
      _client = null;
      downloading = null;
      notifyListeners();
    }
  }

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<void> delete(String id) async {
    if (downloading != null) return;
    final folder = Directory(path(id));
    if (await folder.exists()) await folder.delete(recursive: true);
    installed.remove(id);
    notifyListeners();
  }

  Future<int> diskBytes() async {
    var total = 0;
    await for (final file in root.list(recursive: true, followLinks: false)) {
      if (file is File) total += await file.length();
    }
    return total;
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}
