import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

class CueNativeModel {
  CueNativeModel(String path, {String? libraryPath}) {
    final DynamicLibrary library;
    if (libraryPath != null) {
      library = DynamicLibrary.open(libraryPath);
    } else if (Platform.isIOS || Platform.isMacOS) {
      final executable = File(Platform.resolvedExecutable).parent.path;
      final frameworks = Platform.isIOS
          ? '$executable/Frameworks'
          : '$executable/../Frameworks';
      library = DynamicLibrary.open(
        '$frameworks/cue_native.framework/cue_native',
      );
    } else {
      library = DynamicLibrary.open(
        Platform.isWindows ? 'cue_native.dll' : 'libcue_native.so',
      );
    }
    final load = library
        .lookupFunction<
          Pointer<Void> Function(Pointer<Utf8>),
          Pointer<Void> Function(Pointer<Utf8>)
        >('cue_load');
    _complete = library
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Int32),
          int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, int)
        >('cue_complete');
    _embed = library
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Float>, Int32),
          int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Float>, int)
        >('cue_embed');
    _free = library
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('cue_free');
    final filename = path.toNativeUtf8();
    try {
      _handle = load(filename);
    } finally {
      calloc.free(filename);
    }
    if (_handle == nullptr) {
      throw StateError(
        'The local meaning model could not be loaded. Check device memory and reinstall the component.',
      );
    }
  }
  late Pointer<Void> _handle;
  late int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, int) _complete;
  late int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Float>, int) _embed;
  late void Function(Pointer<Void>) _free;
  String complete(String prompt) {
    final input = prompt.toNativeUtf8(),
        output = calloc<Uint8>(4096).cast<Utf8>();
    try {
      final length = _complete(_handle, input, output, 4096);
      if (length < 0) {
        throw StateError('Meaning comparison could not complete ($length).');
      }
      return output.toDartString(length: length);
    } finally {
      calloc.free(input);
      calloc.free(output);
    }
  }

  List<double> embed(String text) {
    final input = text.toNativeUtf8();
    final output = calloc<Float>(2048);
    try {
      final count = _embed(_handle, input, output, 2048);
      if (count <= 0) throw StateError('Phrase comparison failed ($count)');
      return List<double>.from(output.asTypedList(count));
    } finally {
      calloc.free(input);
      calloc.free(output);
    }
  }

  void dispose() {
    if (_handle != nullptr) {
      _free(_handle);
      _handle = nullptr;
    }
  }
}
