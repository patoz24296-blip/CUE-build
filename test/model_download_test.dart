import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:cue/data/model_manager.dart';

void main() {
  late Directory temporary;
  late HttpServer server;
  late ModelManager manager;
  final data = utf8.encode('verified model content');
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cue-download-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    manager = ModelManager(temporary);
  });
  tearDown(() async {
    manager.dispose();
    await server.close(force: true);
    await temporary.delete(recursive: true);
  });
  ModelSpec spec({String? digest}) => ModelSpec({
    'id': 'test',
    'name': 'Test',
    'detail': 'fixture',
    'bytes': data.length,
    'files': [
      {
        'path': 'model.onnx',
        'bytes': data.length,
        'digest': digest ?? sha256.convert(data).toString(),
        'algorithm': 'sha256',
        'url': 'http://127.0.0.1:${server.port}/model',
      },
    ],
  });
  test(
    'Relocation verifies models and retains previous storage until settings are saved',
    () async {
      server.listen((request) async {
        request.response.add(data);
        await request.response.close();
      });
      manager.catalog = [spec()];
      await manager.install('test');
      final original = manager.root;
      final destination = await Directory.systemTemp.createTemp(
        'cue-relocation-',
      );
      try {
        await manager.relocate(destination);
        expect(
          await File(p.join(manager.path('test'), 'model.onnx')).readAsBytes(),
          data,
        );
        expect(
          await File(p.join(original.path, 'test', 'model.onnx')).exists(),
          isTrue,
        );
        expect(manager.installed, contains('test'));
        await expectLater(
          manager.relocate(Directory(p.join(destination.path, 'nested'))),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        await destination.delete(recursive: true);
      }
    },
  );
  test(
    'A verified download installs atomically with no staging marker',
    () async {
      server.listen((request) async {
        request.response.add(data);
        await request.response.close();
      });
      manager.catalog = [spec()];
      await manager.install('test');
      expect(manager.error, isNull);
      expect(manager.installed, contains('test'));
      expect(
        await File(p.join(manager.path('test'), '.ready')).exists(),
        isTrue,
      );
      expect(
        await Directory('${manager.path('test')}.staging').exists(),
        isFalse,
      );
    },
  );
  test('Corrupt model never becomes installed', () async {
    server.listen((request) async {
      request.response.add(data);
      await request.response.close();
    });
    manager.catalog = [spec(digest: '0' * 64)];
    await manager.install('test');
    expect(manager.error, contains('checksum'));
    expect(manager.installed, isEmpty);
    expect(
      await File(p.join(manager.path('test'), '.ready')).exists(),
      isFalse,
    );
  });
  test('Partially downloaded bytes resume using HTTP Range', () async {
    var range = '';
    server.listen((request) async {
      range = request.headers.value('Range') ?? '';
      request.response.statusCode = 206;
      request.response.add(data.skip(5).toList());
      await request.response.close();
    });
    manager.catalog = [spec()];
    final part = File('${manager.path('test')}.staging/model.onnx.part');
    await part.parent.create(recursive: true);
    await part.writeAsBytes(data.take(5).toList());
    await manager.install('test');
    expect(range, 'bytes=5-');
    expect(manager.error, isNull);
    expect(manager.installed, contains('test'));
  });
  test(
    'Already completed part is verified and recovered without a 416 loop',
    () async {
      manager.catalog = [spec()];
      final part = File('${manager.path('test')}.staging/model.onnx.part');
      await part.parent.create(recursive: true);
      await part.writeAsBytes(data);
      await manager.install('test');
      expect(manager.error, isNull);
      expect(manager.installed, contains('test'));
    },
  );
}
