import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:audio_session/audio_session.dart' as session;
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../domain/models.dart';
import '../domain/providers.dart';
import '../data/model_manager.dart';
import 'session_recording.dart';

// Each engine owns a persistent isolate; native handles never cross isolates.
class InferenceWorker {
  InferenceWorker._(this._isolate, this._port);
  final Isolate _isolate;
  final SendPort _port;
  bool _closed = false;
  static Future<InferenceWorker> open(Map<String, Object> config) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_inferenceMain, [
      ready.sendPort,
      config,
    ]);
    try {
      final response = await ready.first.timeout(const Duration(seconds: 90));
      if (response is String) throw StateError(response);
      return InferenceWorker._(isolate, response as SendPort);
    } catch (_) {
      isolate.kill();
      rethrow;
    } finally {
      ready.close();
    }
  }

  Future<dynamic> call(
    String method, [
    Map<String, Object> args = const {},
  ]) async {
    if (_closed) throw StateError('Audio engine is closed');
    final reply = ReceivePort();
    _port.send([reply.sendPort, method, args]);
    try {
      final value = await reply.first.timeout(const Duration(seconds: 90));
      if (value is Map && value.containsKey('error')) {
        throw StateError(value['error']);
      }
      return value;
    } finally {
      reply.close();
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    try {
      await call('dispose');
    } finally {
      _closed = true;
      _isolate.kill();
    }
  }
}

void _inferenceMain(List<dynamic> initial) {
  final parent = initial[0] as SendPort;
  final config = initial[1] as Map<String, Object>;
  sherpa.OfflineRecognizer? recognizer;
  sherpa.OfflineTts? tts;
  sherpa.VoiceActivityDetector? vad;
  try {
    sherpa.initBindings(config['library'] as String?);
    final root = config['root'] as String;
    switch (config['type']) {
      case 'asr':
        final prefix = config['prefix'] as String;
        recognizer = sherpa.OfflineRecognizer(
          sherpa.OfflineRecognizerConfig(
            model: sherpa.OfflineModelConfig(
              moonshine: config['family'] == 'moonshine'
                  ? sherpa.OfflineMoonshineModelConfig(
                      encoder: p.join(root, 'encoder_model.ort'),
                      mergedDecoder: p.join(root, 'decoder_model_merged.ort'),
                    )
                  : const sherpa.OfflineMoonshineModelConfig(),
              whisper: config['family'] == 'moonshine'
                  ? const sherpa.OfflineWhisperModelConfig()
                  : sherpa.OfflineWhisperModelConfig(
                      encoder: p.join(root, '$prefix-encoder.int8.onnx'),
                      decoder: p.join(root, '$prefix-decoder.int8.onnx'),
                      language: config['language'] as String? ?? 'en',
                      task: 'transcribe',
                    ),
              tokens: p.join(
                root,
                config['family'] == 'moonshine'
                    ? 'tokens.txt'
                    : '$prefix-tokens.txt',
              ),
              numThreads: 2,
              debug: false,
              provider: 'cpu',
            ),
          ),
        );
      case 'tts':
        tts = sherpa.OfflineTts(
          sherpa.OfflineTtsConfig(
            model: sherpa.OfflineTtsModelConfig(
              kokoro: config['family'] == 'kokoro'
                  ? sherpa.OfflineTtsKokoroModelConfig(
                      model: p.join(root, 'model.onnx'),
                      voices: p.join(root, 'voices.bin'),
                      tokens: p.join(root, 'tokens.txt'),
                      dataDir: p.join(root, 'espeak-ng-data'),
                      lexicon: config['language'] == 'es'
                          ? ''
                          : p.join(root, 'lexicon-us-en.txt'),
                      lang: config['language'] == 'es' ? 'es' : 'en-us',
                    )
                  : const sherpa.OfflineTtsKokoroModelConfig(),
              vits: config['family'] == 'kokoro'
                  ? const sherpa.OfflineTtsVitsModelConfig()
                  : sherpa.OfflineTtsVitsModelConfig(
                      model: p.join(root, 'en_US-libritts_r-medium.onnx'),
                      tokens: p.join(root, 'tokens.txt'),
                      dataDir: p.join(root, 'espeak-ng-data'),
                    ),
              numThreads: 2,
              debug: false,
              provider: 'cpu',
            ),
          ),
        );
      case 'vad':
        vad = sherpa.VoiceActivityDetector(
          config: sherpa.VadModelConfig(
            sileroVad: sherpa.SileroVadModelConfig(
              model: p.join(root, 'silero_vad.onnx'),
              threshold: config['sensitivity'] as double,
              minSilenceDuration: .1,
              minSpeechDuration: .15,
              maxSpeechDuration: 60,
            ),
            sampleRate: 16000,
            numThreads: 1,
            debug: false,
          ),
          bufferSizeInSeconds: 65,
        );
    }
    final requests = ReceivePort();
    parent.send(requests.sendPort);
    requests.listen((dynamic message) {
      final reply = message[0] as SendPort;
      final method = message[1] as String;
      final args = message[2] as Map;
      try {
        switch (method) {
          case 'transcribe':
            final stream = recognizer!.createStream();
            try {
              stream.acceptWaveform(
                samples: args['samples'] as Float32List,
                sampleRate: 16000,
              );
              recognizer.decode(stream);
              reply.send(recognizer.getResult(stream).text);
            } finally {
              stream.free();
            }
          case 'vad':
            vad!.acceptWaveform(args['samples'] as Float32List);
            final speaking = vad.isDetected();
            while (!vad.isEmpty()) {
              vad.pop();
            }
            reply.send(speaking);
          case 'reset':
            vad?.reset();
            reply.send(true);
          case 'speak':
            final audio = tts!.generate(
              text: args['text'],
              sid: (args['voice'] as int) >= 1000
                  ? (args['voice'] as int) - 1000
                  : args['voice'],
              speed: args['speed'],
            );
            if (!sherpa.writeWave(
              filename: args['path'],
              samples: audio.samples,
              sampleRate: audio.sampleRate,
            )) {
              throw StateError('Could not prepare the scene partner audio');
            }
            reply.send(true);
          case 'dispose':
            recognizer?.free();
            tts?.free();
            vad?.free();
            reply.send(true);
            requests.close();
        }
      } catch (e) {
        reply.send({'error': e.toString()});
      }
    });
  } catch (e) {
    parent.send('Could not load the local audio model: $e');
  }
}

class LocalRecognizer implements SpeechRecognitionProvider {
  LocalRecognizer(this.worker);
  final InferenceWorker worker;
  @override
  Future<Transcript> transcribe(
    Float32List samples, {
    int sampleRate = 16000,
  }) async => Transcript(await worker.call('transcribe', {'samples': samples}));
  @override
  Future<void> dispose() => worker.dispose();
}

class LocalVad implements VoiceActivityProvider {
  LocalVad(this.worker);
  final InferenceWorker worker;
  @override
  Future<bool> detect(Float32List frame) async =>
      await worker.call('vad', {'samples': frame}) as bool;
  @override
  Future<void> reset() async {
    await worker.call('reset');
  }
}

class LocalListening implements ListeningProvider, RecognitionVerification {
  LocalListening(
    this.asr,
    this.vad,
    this.vadWorker, {
    this.settings = const AppSettings(),
    this.recording,
    this.verifier,
    AudioRecorder? recorder,
  }) : _recorder = recorder ?? AudioRecorder();
  final AppSettings settings;
  SessionRecording? recording;
  final LocalRecognizer asr;
  final LocalRecognizer? verifier;
  final LocalVad vad;
  final InferenceWorker vadWorker;
  final AudioRecorder _recorder;
  Future<void>? _starting;
  final _events = StreamController<SpeechEvent>.broadcast();
  @override
  Stream<SpeechEvent> get events => _events.stream;
  StreamSubscription<Uint8List>? _microphone;
  Timer? _timer;
  final _samples = <double>[];
  final _vadSamples = <double>[];
  DateTime? _speechAt, _lastSpeech;
  bool _running = false,
      _detecting = false,
      _decoding = false,
      _speaking = false;
  int _generation = 0, _decodedLength = 0, _voicedLength = 0;
  String _text = '', _prefixText = '';
  Float32List? _lastUtterance;
  String _lastPrefix = '';
  DateTime _lastDecodeAt = DateTime.fromMillisecondsSinceEpoch(0);
  Transcript? _verified;
  bool get _incremental => settings.effectiveSpeechModel == 'moonshine';
  @override
  Future<void> start() {
    if (_running) return Future<void>.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    final generation = _generation;
    if (!await _recorder.hasPermission()) {
      throw StateError(
        'Microphone access is needed to hear your lines. Enable it in device Settings, then retry.',
      );
    }
    if (generation != _generation) return;
    if (Platform.isIOS) await _recorder.ios?.manageAudioSession(false);
    if (generation != _generation) return;
    _running = true;
    try {
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
          device: settings.microphoneId == null
              ? null
              : InputDevice(
                  id: settings.microphoneId!,
                  label: 'Selected microphone',
                ),
        ),
      );
      if (generation != _generation) {
        _running = false;
        await _recorder.stop();
        return;
      }
      _microphone = stream.listen(
        _accept,
        onError: (Object e) => _events.addError(e),
      );
      _timer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _tick(),
      );
    } catch (_) {
      _running = false;
      rethrow;
    }
  }

  void _accept(Uint8List bytes) {
    if (!_running) return;
    recording?.addMicrophone(bytes);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final value = data.getInt16(i, Endian.little) / 32768;
      _samples.add(value);
      _vadSamples.add(value);
    }
    if (_speechAt == null && _samples.length > 16000) {
      _samples.removeRange(0, _samples.length - 16000);
    } else if (!_speaking && _samples.length > _voicedLength + 16000) {
      // Retain the performed words and a fresh second of room audio. A long
      // dramatic pause must not grow memory or lose the start of resumed speech.
      _samples.removeRange(_voicedLength, _samples.length - 16000);
    }
  }

  Future<void> _tick() async {
    if (!_running) return;
    final generation = _generation;
    try {
      if (!_detecting && _vadSamples.length >= 512) {
        _detecting = true;
        final length = (_vadSamples.length ~/ 512) * 512;
        final frame = Float32List.fromList(_vadSamples.take(length).toList());
        _vadSamples.removeRange(0, length);
        try {
          final speaking = await vad.detect(frame);
          if (generation != _generation || !_running) return;
          _speaking = speaking;
          if (speaking) {
            _lastSpeech = DateTime.now();
            _speechAt ??= _lastSpeech;
            _voicedLength = _samples.length;
          }
        } finally {
          _detecting = false;
        }
      }
      if (generation != _generation || !_running) return;
      final silence = _lastSpeech == null
          ? Duration.zero
          : DateTime.now().difference(_lastSpeech!);
      final longSegment = _samples.length >= 16000 * 25;
      if (_speechAt != null &&
          (longSegment ||
              (!_speaking && silence.inMilliseconds >= 180) ||
              (_incremental &&
                  _speaking &&
                  DateTime.now().difference(_lastDecodeAt).inMilliseconds >=
                      700 &&
                  _samples.length >= 16000)) &&
          !_decoding &&
          _decodedLength < _voicedLength) {
        _decoding = true;
        final samples = Float32List.fromList(_samples);
        _lastDecodeAt = DateTime.now();
        // Ignore trailing room silence when deciding whether to decode again.
        _decodedLength = _voicedLength;
        try {
          final result = await asr.transcribe(samples);
          if (generation == _generation && _running) {
            _lastUtterance = samples;
            _lastPrefix = _prefixText;
            _verified = null;
            _text = '$_prefixText ${result.text}'.trim();
            if (longSegment) {
              _prefixText = _text;
              _samples.removeRange(0, min(samples.length, _samples.length));
              _voicedLength = max(0, _voicedLength - samples.length);
              _decodedLength = 0;
            }
          }
        } finally {
          _decoding = false;
        }
      }
      if (generation == _generation && _running) {
        _events.add(
          SpeechEvent(
            text: _text,
            speaking: _speaking || _decoding,
            silence: silence,
            startedAt: _speechAt,
          ),
        );
      }
    } catch (e) {
      if (generation == _generation && !_events.isClosed) _events.addError(e);
    }
  }

  @override
  Future<void> reset() async {
    ++_generation;
    _samples.clear();
    _vadSamples.clear();
    _speechAt = null;
    _lastSpeech = null;
    _speaking = false;
    _decodedLength = 0;
    _voicedLength = 0;
    _text = '';
    _prefixText = '';
    _lastUtterance = null;
    _verified = null;
    await vad.reset();
  }

  @override
  Future<Transcript?> verifyUtterance() async {
    if (verifier == null || _lastUtterance == null) return null;
    if (_verified != null) return _verified;
    final generation = _generation;
    final audio = _lastUtterance!;
    final prefix = _lastPrefix;
    final result = await verifier!.transcribe(audio);
    if (generation != _generation || !identical(audio, _lastUtterance)) {
      return null;
    }
    return _verified = Transcript(
      '$prefix ${result.text}'.trim(),
      confidence: result.confidence,
    );
  }

  @override
  Future<void> stop() async {
    _running = false;
    ++_generation;
    _timer?.cancel();
    try {
      await _starting;
    } catch (_) {
      // A denied permission or failed start must not prevent cleanup.
    }
    await _microphone?.cancel();
    _microphone = null;
    await _recorder.stop();
    _samples.clear();
    _vadSamples.clear();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
    await asr.dispose();
    await verifier?.dispose();
    await vadWorker.dispose();
    await _events.close();
  }
}

class LocalTts implements TextToSpeechProvider {
  LocalTts(this.worker, this.cache, {this.recording});
  SessionRecording? recording;
  final InferenceWorker worker;
  final Directory cache;
  final _player = AudioPlayer();
  final _files = <String, String>{};
  String? _currentFile;
  int _generation = 0;
  Completer<void>? _playing;
  Completer<void>? _settled;
  Future<String> _prepare(String text, int voice, double speed) async {
    speed = (speed * 20).round() / 20;
    final key = '$voice|$speed|$text';
    if (_files.containsKey(key)) return _files[key]!;
    final file = p.join(cache.path, '${newId()}.wav');
    await worker.call('speak', {
      'text': text,
      'voice': voice,
      'speed': speed,
      'path': file,
    });
    _files[key] = file;
    if (_files.length > 128) {
      final oldest = _files.entries
          .where((entry) => entry.value != _currentFile && entry.value != file)
          .firstOrNull;
      if (oldest != null) {
        _files.remove(oldest.key);
        final old = File(oldest.value);
        if (await old.exists()) await old.delete();
      }
    }
    return file;
  }

  @override
  Future<void> speak(
    String text, {
    int voice = 0,
    double speed = 1,
    double volume = 1,
  }) async {
    final generation = ++_generation;
    final file = await _prepare(text, voice, speed);
    if (generation != _generation) return;
    _currentFile = file;
    final done = Completer<void>();
    _playing = done;
    final settled = Completer<void>();
    _settled = settled;
    final subscription = _player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    final playback = Stopwatch();
    var atMs = 0;
    try {
      await _player.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.allowBluetooth,
            },
          ),
        ),
      );
      if (generation != _generation) return;
      await _player.setVolume(volume);
      if (generation != _generation) return;
      await _player.play(DeviceFileSource(file));
      if (generation != _generation) {
        await _player.stop();
        return;
      }
      atMs = recording?.elapsedMs ?? 0;
      playback.start();
      await done.future.timeout(const Duration(minutes: 3));
    } finally {
      playback.stop();
      await recording?.addWave(
        File(file),
        atMs: atMs,
        playedMs: playback.elapsedMilliseconds,
        volume: volume,
      );
      await subscription.cancel();
      if (identical(_playing, done)) _playing = null;
      if (_currentFile == file) _currentFile = null;
      if (!settled.isCompleted) settled.complete();
      if (identical(_settled, settled)) _settled = null;
    }
  }

  @override
  Future<void> preload(String text, {int voice = 0, double speed = 1}) async {
    await _prepare(text, voice, speed);
  }

  @override
  Future<void> stop() async {
    ++_generation;
    final settled = _settled;
    await _player.stop();
    if (_playing != null && !_playing!.isCompleted) _playing!.complete();
    await settled?.future;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _player.dispose();
    await worker.dispose();
    if (await cache.exists()) await cache.delete(recursive: true);
  }
}

class LocalAudioBundle {
  LocalAudioBundle(this.listener, this.tts);
  final LocalListening listener;
  final LocalTts tts;
  static Future<LocalAudioBundle> open(
    ModelManager models,
    AppSettings settings,
    Directory temporary, {
    SessionRecording? recording,
  }) async {
    final audioSession = await session.AudioSession.instance;
    await audioSession.configure(
      session.AudioSessionConfiguration(
        avAudioSessionCategory: session.AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            session.AVAudioSessionCategoryOptions.defaultToSpeaker |
            session.AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: session.AVAudioSessionMode.voiceChat,
        androidAudioAttributes: session.AndroidAudioAttributes(
          contentType: session.AndroidAudioContentType.speech,
          usage: session.AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: session.AndroidAudioFocusGainType.gain,
      ),
    );
    await audioSession.setActive(true);
    final workers = <InferenceWorker>[];
    try {
      final speechModel = settings.effectiveSpeechModel;
      final asr = await InferenceWorker.open({
        'type': 'asr',
        'root': models.path(speechModel),
        'family': speechModel == 'moonshine' ? 'moonshine' : 'whisper',
        'prefix':
            {
              'whisper-base': 'base.en',
              'whisper-small': 'small.en',
              'whisper-multilingual': 'tiny',
              'whisper-base-multilingual': 'base',
            }[speechModel] ??
            'tiny.en',
        'language':
            speechModel == 'whisper-multilingual' ||
                speechModel == 'whisper-base-multilingual'
            ? settings.language
            : 'en',
      });
      workers.add(asr);
      InferenceWorker? verification;
      final verificationId = settings.verificationSpeechModel;
      if (verificationId != speechModel &&
          models.installed.contains(verificationId)) {
        try {
          verification = await InferenceWorker.open({
            'type': 'asr',
            'root': models.path(verificationId),
            'family': verificationId == 'moonshine' ? 'moonshine' : 'whisper',
            'prefix': verificationId == 'whisper-multilingual'
                ? 'tiny'
                : verificationId == 'whisper-base-multilingual'
                ? 'base'
                : 'base.en',
            'language': settings.language,
          });
          workers.add(verification);
        } catch (_) {
          // The primary recognizer remains usable if optional verification fails.
        }
      }
      final vad = await InferenceWorker.open({
        'type': 'vad',
        'root': models.path('vad'),
        'sensitivity': settings.sensitivity,
      });
      workers.add(vad);
      final tts = await InferenceWorker.open({
        'type': 'tts',
        'root': models.path('kokoro'),
        'family': 'kokoro',
        'language': settings.language,
      });
      workers.add(tts);
      final cache = Directory(p.join(temporary.path, 'cue-audio', newId()));
      await cache.create(recursive: true);
      return LocalAudioBundle(
        LocalListening(
          LocalRecognizer(asr),
          LocalVad(vad),
          vad,
          settings: settings,
          recording: recording,
          verifier: verification == null ? null : LocalRecognizer(verification),
        ),
        LocalTts(tts, cache, recording: recording),
      );
    } catch (_) {
      for (final worker in workers) {
        await worker.dispose();
      }
      rethrow;
    }
  }
}

class PartnerVoicePreview {
  PartnerVoicePreview(this.models, this.temporary, this.language);
  final ModelManager models;
  final Directory temporary;
  final String language;
  Future<LocalTts>? _opening;
  bool _disposed = false;
  Future<LocalTts> _open() async {
    final worker = await InferenceWorker.open({
      'type': 'tts',
      'family': 'kokoro',
      'root': models.path('kokoro'),
      'language': language,
    });
    final cache = Directory(p.join(temporary.path, 'cue-preview', newId()));
    try {
      await cache.create(recursive: true);
      return LocalTts(worker, cache);
    } catch (_) {
      await worker.dispose();
      rethrow;
    }
  }

  Future<void> speak(int voice, double speed) async {
    final tts = await (_opening ??= _open());
    if (_disposed) return;
    await tts.stop();
    await tts.speak(
      language == 'es'
          ? 'No te vayas todavía. Necesito decirte algo.'
          : 'Wait. Before you go, there is something I need to tell you.',
      voice: voice,
      speed: speed,
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    if (_opening != null) {
      try {
        await (await _opening!).dispose();
      } catch (_) {
        /* Opening errors are reported by the preview action. */
      }
    }
  }
}
