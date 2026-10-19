import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class ModelStorageAccess {
  static const _channel = MethodChannel('studio.cue/model-storage');
  static Future<void> remember(String selectedFolder) async {
    if (Platform.isMacOS) {
      await _channel.invokeMethod<bool>('rememberDirectory', selectedFolder);
    }
  }

  static Future<bool> restore(String modelFolder) async {
    if (!Platform.isMacOS) return true;
    try {
      return await _channel.invokeMethod<bool>(
            'restoreDirectory',
            p.dirname(modelFolder),
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }
}
