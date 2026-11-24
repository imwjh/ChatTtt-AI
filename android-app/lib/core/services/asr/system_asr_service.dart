import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kReleaseMode;
import 'package:speech_to_text/speech_to_text.dart';

typedef SystemAsrTranscriptCallback =
    void Function(String transcript, bool isFinal);
typedef SystemAsrSoundLevelCallback = void Function(double level);
typedef SystemAsrErrorCallback = void Function(SystemAsrError error);

/// macOS debug/profile builds are excluded from the plugin authorization path.
///
/// Flutter currently starts desktop debug apps by executing the bundle binary
/// directly. macOS TCC can then attribute speech authorization to the parent
/// IDE instead of this app and terminates the process before Dart can handle
/// the failure. Normal release bundles are launched through LaunchServices and
/// keep native macOS system recognition available.
bool canInitializeSystemAsrOnPlatform(
  TargetPlatform platform, {
  bool isReleaseMode = kReleaseMode,
}) => platform != TargetPlatform.macOS || isReleaseMode;

enum SystemAsrState {
  uninitialized,
  initializing,
  ready,
  listening,
  stopping,
  unavailable,
  disposed,
}

class SystemAsrLocale {
  const SystemAsrLocale({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SystemAsrLocale && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

class SystemAsrError {
  const SystemAsrError({required this.message, required this.isPermanent});

  final String message;
  final bool isPermanent;
}

/// Small boundary around [SpeechToText] so the service can be tested without
/// platform channels.
abstract interface class SystemAsrBackend {
  Future<bool> initialize({
    required SystemAsrErrorCallback onError,
    required void Function(String status) onStatus,
  });

  Future<List<SystemAsrLocale>> locales();

  Future<SystemAsrLocale?> systemLocale();

  Future<void> listen({
    required String? localeId,
    required Duration listenFor,
    required Duration pauseFor,
    required SystemAsrTranscriptCallback onTranscript,
    required SystemAsrSoundLevelCallback onSoundLevel,
  });

  Future<void> stop();

  Future<void> cancel();
}

class SpeechToTextSystemAsrBackend implements SystemAsrBackend {
  SpeechToTextSystemAsrBackend({SpeechToText? speechToText})
    : _speechToText = speechToText ?? SpeechToText();

  final SpeechToText _speechToText;

  @override
  Future<bool> initialize({
    required SystemAsrErrorCallback onError,
    required void Function(String status) onStatus,
  }) {
    if (!canInitializeSystemAsrOnPlatform(defaultTargetPlatform)) {
      return Future<bool>.value(false);
    }
    return _speechToText.initialize(
      onError: (error) => onError(
        SystemAsrError(message: error.errorMsg, isPermanent: error.permanent),
      ),
      onStatus: onStatus,
      options: <SpeechConfigOption>[SpeechToText.androidIntentLookup],
    );
  }

  @override
  Future<List<SystemAsrLocale>> locales() async {
    final values = await _speechToText.locales();
    return values
        .map(
          (locale) => SystemAsrLocale(id: locale.localeId, name: locale.name),
        )
        .toList(growable: false);
  }

  @override
  Future<SystemAsrLocale?> systemLocale() async {
    final locale = await _speechToText.systemLocale();
    if (locale == null) return null;
    return SystemAsrLocale(id: locale.localeId, name: locale.name);
  }

  @override
  Future<void> listen({
    required String? localeId,
    required Duration listenFor,
    required Duration pauseFor,
    required SystemAsrTranscriptCallback onTranscript,
    required SystemAsrSoundLevelCallback onSoundLevel,
  }) async {
    await _speechToText.listen(
      onResult: (result) {
        onTranscript(result.recognizedWords, result.finalResult);
      },
      onSoundLevelChange: onSoundLevel,
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        listenFor: listenFor,
        pauseFor: pauseFor,
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  @override
  Future<void> stop() => _speechToText.stop();

  @override
  Future<void> cancel() => _speechToText.cancel();
}

class SystemAsrService {
  SystemAsrService({SystemAsrBackend? backend})
    : _backend = backend ?? SpeechToTextSystemAsrBackend();

  static const Duration defaultListenFor = Duration(minutes: 1);
  static const Duration defaultPauseFor = Duration(seconds: 4);

  final SystemAsrBackend _backend;

  SystemAsrState _state = SystemAsrState.uninitialized;
  Future<bool>? _initializeFuture;
  bool _available = false;
  bool _sessionActive = false;
  int _sessionGeneration = 0;
  SystemAsrTranscriptCallback? _onTranscript;
  SystemAsrSoundLevelCallback? _onSoundLevel;
  SystemAsrErrorCallback? _onError;
  void Function()? _onDone;

  SystemAsrState get state => _state;
  bool get isAvailable => _available;
  bool get isListening => _state == SystemAsrState.listening;

  Future<bool> initialize() {
    _ensureNotDisposed();
    return _initializeFuture ??= _initializeOnce();
  }

  Future<bool> _initializeOnce() async {
    _state = SystemAsrState.initializing;
    try {
      _available = await _backend.initialize(
        onError: _handleError,
        onStatus: _handleStatus,
      );
    } catch (_) {
      if (_state != SystemAsrState.disposed) {
        _state = SystemAsrState.unavailable;
      }
      rethrow;
    }
    if (_state != SystemAsrState.disposed) {
      _state = _available ? SystemAsrState.ready : SystemAsrState.unavailable;
    }
    return _available;
  }

  Future<List<SystemAsrLocale>> get locales async {
    _ensureNotDisposed();
    if (!await initialize()) return const <SystemAsrLocale>[];
    return _backend.locales();
  }

  Future<SystemAsrLocale?> get systemLocale async {
    _ensureNotDisposed();
    if (!await initialize()) return null;
    return _backend.systemLocale();
  }

  /// Starts a recognition session. Returns false when the platform service is
  /// unavailable; an already active session is a programming error.
  Future<bool> start({
    String? localeId,
    required SystemAsrTranscriptCallback onTranscript,
    required SystemAsrSoundLevelCallback onSoundLevel,
    required SystemAsrErrorCallback onError,
    void Function()? onDone,
  }) async {
    _ensureNotDisposed();
    if (_sessionActive) {
      throw StateError('A system ASR session is already active.');
    }

    final sessionGeneration = ++_sessionGeneration;
    _sessionActive = true;
    _onTranscript = onTranscript;
    _onSoundLevel = onSoundLevel;
    _onError = onError;
    _onDone = onDone;

    try {
      final available = await initialize();
      if (!_sessionActive || _sessionGeneration != sessionGeneration) {
        return false;
      }
      if (!available) {
        _sessionActive = false;
        _clearSessionCallbacks();
        return false;
      }
      _ensureNotDisposed();

      _state = SystemAsrState.listening;
      await _backend.listen(
        localeId: localeId,
        listenFor: defaultListenFor,
        pauseFor: defaultPauseFor,
        onTranscript: _handleTranscript,
        onSoundLevel: _handleSoundLevel,
      );
    } catch (_) {
      if (_sessionGeneration == sessionGeneration) {
        _sessionActive = false;
        if (_state != SystemAsrState.disposed) {
          _state = _available
              ? SystemAsrState.ready
              : SystemAsrState.unavailable;
        }
        _clearSessionCallbacks();
      }
      rethrow;
    }
    return true;
  }

  Future<void> stop() async {
    if (!_sessionActive || _state == SystemAsrState.stopping) return;
    _state = SystemAsrState.stopping;
    try {
      await _backend.stop();
    } finally {
      if (_state != SystemAsrState.disposed && _state != SystemAsrState.ready) {
        _state = SystemAsrState.stopping;
      }
    }
  }

  Future<void> cancel() async {
    if (!_sessionActive) return;
    final canceledGeneration = ++_sessionGeneration;
    _state = SystemAsrState.stopping;
    _sessionActive = false;
    _clearSessionCallbacks();
    try {
      await _backend.cancel();
    } finally {
      if (_state != SystemAsrState.disposed &&
          _sessionGeneration == canceledGeneration) {
        _state = SystemAsrState.ready;
      }
    }
  }

  Future<void> dispose() async {
    if (_state == SystemAsrState.disposed) return;
    final shouldCancel =
        _state == SystemAsrState.listening || _state == SystemAsrState.stopping;
    _sessionGeneration += 1;
    _state = SystemAsrState.disposed;
    _sessionActive = false;
    _clearSessionCallbacks();
    if (shouldCancel) await _backend.cancel();
  }

  void _handleTranscript(String transcript, bool isFinal) {
    _onTranscript?.call(transcript, isFinal);
  }

  void _handleSoundLevel(double level) {
    _onSoundLevel?.call(level);
  }

  void _handleError(SystemAsrError error) {
    _onError?.call(error);
    if (error.isPermanent && _state == SystemAsrState.listening) {
      _state = SystemAsrState.stopping;
    }
  }

  void _handleStatus(String status) {
    if (_state == SystemAsrState.disposed) return;
    if (status == SpeechToText.listeningStatus) {
      _state = SystemAsrState.listening;
    } else if (status == SpeechToText.notListeningStatus) {
      if (_sessionActive) _state = SystemAsrState.stopping;
    } else if (status == SpeechToText.doneStatus) {
      final onDone = _onDone;
      _sessionActive = false;
      _state = _available ? SystemAsrState.ready : SystemAsrState.unavailable;
      _clearSessionCallbacks();
      onDone?.call();
    }
  }

  void _clearSessionCallbacks() {
    _onTranscript = null;
    _onSoundLevel = null;
    _onError = null;
    _onDone = null;
  }

  void _ensureNotDisposed() {
    if (_state == SystemAsrState.disposed) {
      throw StateError('SystemAsrService has been disposed.');
    }
  }
}
