import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

Uint8List waveHeader(int bytes, {int rate = 16000}) {
  final data = ByteData(44);
  void label(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      data.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  label(0, 'RIFF');
  data.setUint32(4, bytes + 36, Endian.little);
  label(8, 'WAVE');
  label(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  label(36, 'data');
  data.setUint32(40, bytes, Endian.little);
  return data.buffer.asUint8List();
}

/// Disk-backed recording; no microphone data is retained without explicit opt-in.
class SessionRecording extends ChangeNotifier {
  SessionRecording._(this.file, this._output);
  final File file;
  final RandomAccessFile _output;
  final _clock = Stopwatch();
  Future<void> _queue = Future.value();
  int _bytes = 0;
  bool _closed = false;
  bool _notifierClosed = false;
  Future<File?>? _finishing;
  String? error;
  bool get active => !_closed && error == null && _clock.isRunning;
  int get elapsedMs => _clock.elapsedMilliseconds;
  static Future<SessionRecording> open(File file) async {
    await file.parent.create(recursive: true);
    final output = await file.open(mode: FileMode.write);
    await output.writeFrom(waveHeader(0));
    return SessionRecording._(file, output);
  }

  void resume() {
    if (!_closed && error == null) _clock.start();
  }

  void pause() => _clock.stop();
  void addMicrophone(Uint8List pcm) {
    if (!active) return;
    addPcm(pcm, atMs: max(0, elapsedMs - pcm.length * 1000 ~/ 32000));
  }

  Future<void> addPcm(Uint8List pcm, {required int atMs}) {
    if (_closed || error != null) return Future.value();
    final copy = Uint8List.fromList(pcm);
    final offset = max(0, atMs) * 32;
    _queue = _queue.then((_) async {
      if (error != null) return;
      try {
        if (offset + copy.length > 0xffffff00) {
          throw const FileSystemException(
            'Recording exceeds WAV file capacity. Start a new run.',
          );
        }
        await _output.setPosition(44 + offset);
        final existing = await _output.read(copy.length);
        final old = ByteData.sublistView(existing);
        final mixed = ByteData.sublistView(copy);
        for (var i = 0; i + 1 < existing.length; i += 2) {
          mixed.setInt16(
            i,
            (mixed.getInt16(i, Endian.little) + old.getInt16(i, Endian.little))
                .clamp(-32768, 32767),
            Endian.little,
          );
        }
        await _output.setPosition(44 + offset);
        await _output.writeFrom(copy);
        _bytes = max(_bytes, offset + copy.length);
      } catch (e) {
        error = 'Recording stopped: $e';
        _clock.stop();
        if (!_notifierClosed) notifyListeners();
      }
    });
    return _queue;
  }

  Future<void> addWave(
    File wave, {
    required int atMs,
    required int playedMs,
    double volume = 1,
  }) async {
    if (_closed || error != null || playedMs <= 0) return;
    try {
      final bytes = await wave.readAsBytes();
      final data = ByteData.sublistView(bytes);
      var cursor = 12, rate = 16000, channels = 1, bits = 16, format = 1;
      var start = -1, length = 0;
      while (cursor + 8 <= bytes.length) {
        final size = data.getUint32(cursor + 4, Endian.little);
        final name = String.fromCharCodes(bytes.sublist(cursor, cursor + 4));
        if (name == 'fmt ') {
          format = data.getUint16(cursor + 8, Endian.little);
          channels = data.getUint16(cursor + 10, Endian.little);
          rate = data.getUint32(cursor + 12, Endian.little);
          bits = data.getUint16(cursor + 22, Endian.little);
        }
        if (name == 'data') {
          start = cursor + 8;
          length = min(size, bytes.length - start);
          break;
        }
        cursor += 8 + size + size % 2;
      }
      if (start < 0 || format != 1 || bits != 16) {
        throw const FormatException('Unsupported partner audio encoding');
      }
      final frames = length ~/ (2 * channels);
      final count = min(frames * 16000 ~/ rate, playedMs * 16);
      final pcm = ByteData(count * 2);
      for (var i = 0; i < count; i++) {
        final source = min(frames - 1, i * rate ~/ 16000);
        var sample = 0.0;
        for (var c = 0; c < channels; c++) {
          sample += data.getInt16(
            start + (source * channels + c) * 2,
            Endian.little,
          );
        }
        pcm.setInt16(
          i * 2,
          (sample / channels * volume).round().clamp(-32768, 32767),
          Endian.little,
        );
      }
      await addPcm(pcm.buffer.asUint8List(), atMs: atMs);
    } catch (e) {
      error = 'Recording stopped: $e';
      if (!_notifierClosed) notifyListeners();
    }
  }

  Future<File?> finish() => _finishing ??= _finish();
  Future<File?> _finish() async {
    if (_closed) return _bytes > 0 ? file : null;
    pause();
    await _queue;
    _closed = true;
    try {
      await _output.setPosition(0);
      await _output.writeFrom(waveHeader(_bytes));
      await _output.flush();
    } finally {
      await _output.close();
    }
    if (_bytes == 0) {
      await file.delete();
      return null;
    }
    return file;
  }

  Future<void> discard() async {
    await finish();
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      if (await file.exists()) rethrow;
    }
  }

  @override
  void dispose() {
    if (_notifierClosed) return;
    _notifierClosed = true;
    super.dispose();
  }
}
