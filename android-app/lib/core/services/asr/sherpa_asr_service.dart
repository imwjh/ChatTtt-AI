import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'sherpa_model_manager.dart';

/// Runs local sherpa-onnx recognition without retaining native recognizers
/// between recordings. Keeping the complete native lifecycle inside the
/// worker isolate also keeps model loading and decoding off the UI isolate.
final class SherpaAsrService {
  SherpaAsrService({SherpaModelManager? modelManager, this.numThreads = 2})
    : modelManager = modelManager ?? SherpaModelManager() {
    if (numThreads <= 0) {
      throw ArgumentError.value(numThreads, 'numThreads', 'Must be positive');
    }
  }

  final SherpaModelManager modelManager;
  final int numThreads;

  Future<String> transcribePcm16({
    required String modelId,
    required Uint8List pcm16,
    required int sampleRate,
    String language = 'auto',
    Directory? modelDirectory,
    String? modelDirectoryPath,
  }) async {
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'Must be positive');
    }
    if (pcm16.length.isOdd) {
      throw const FormatException('PCM16 data must contain complete samples');
    }
    if (pcm16.isEmpty) return '';
    final speechPcm16 = preparePcm16ForRecognition(
      pcm16,
      sampleRate: sampleRate,
    );
    // Offline recognizers can hallucinate short phrases from silence or a
    // brief burst of room noise. Do not load the model unless there is enough
    // sustained speech-like energy to decode.
    if (speechPcm16 == null) return '';
    final configuredDirectoryPath = modelDirectoryPath?.trim();
    final hasConfiguredDirectoryPath =
        configuredDirectoryPath != null && configuredDirectoryPath.isNotEmpty;
    if (modelDirectory != null && hasConfiguredDirectoryPath) {
      throw ArgumentError(
        'Provide either modelDirectory or modelDirectoryPath, not both',
      );
    }

    final model = modelManager.modelById(modelId);
    final directory =
        modelDirectory ??
        (!hasConfiguredDirectoryPath
            ? await modelManager.modelDirectory(modelId)
            : Directory(configuredDirectoryPath));
    if (!await modelManager.validateModelDirectory(model, directory)) {
      throw StateError('Sherpa-onnx model is not installed: $modelId');
    }

    final request = _SherpaRecognitionRequest(
      architecture: model.architecture,
      directoryPath: directory.path,
      pcm16: speechPcm16,
      sampleRate: sampleRate,
      language: language.trim().isEmpty ? 'auto' : language.trim(),
      numThreads: numThreads,
      modelFile: model.modelFile,
      tokensFile: model.tokensFile,
      encoderFile: model.encoderFile,
      decoderFile: model.decoderFile,
      joinerFile: model.joinerFile,
    );
    return Isolate.run(() => _recognize(request));
  }

  static Float32List pcm16ToFloat32(Uint8List pcm16) {
    if (pcm16.length.isOdd) {
      throw const FormatException('PCM16 data must contain complete samples');
    }
    final data = ByteData.sublistView(pcm16);
    final samples = Float32List(pcm16.length ~/ 2);
    for (var index = 0; index < samples.length; index++) {
      samples[index] =
          data.getInt16(index * 2, Endian.little).toDouble() / 32768.0;
    }
    return samples;
  }

  /// Rejects silence/very short captures and trims quiet edges before native
  /// decoding. The detector intentionally uses a conservative energy gate,
  /// not a language-specific VAD, so it works for every bundled model.
  static Uint8List? preparePcm16ForRecognition(
    Uint8List pcm16, {
    required int sampleRate,
  }) {
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'Must be positive');
    }
    if (pcm16.length.isOdd) {
      throw const FormatException('PCM16 data must contain complete samples');
    }

    final sampleCount = pcm16.length ~/ 2;
    final minimumSamples = (sampleRate * 0.30).round();
    if (sampleCount < minimumSamples) return null;

    final data = ByteData.sublistView(pcm16);
    final frameSamples = math.max(1, sampleRate ~/ 50); // 20 ms
    final frameRms = <double>[];
    for (var start = 0; start < sampleCount; start += frameSamples) {
      final end = math.min(start + frameSamples, sampleCount);
      var sumSquares = 0.0;
      for (var index = start; index < end; index++) {
        final value = data.getInt16(index * 2, Endian.little) / 32768.0;
        sumSquares += value * value;
      }
      frameRms.add(math.sqrt(sumSquares / (end - start)));
    }

    final sortedRms = List<double>.of(frameRms)..sort();
    final noiseFloor = sortedRms[(sortedRms.length * 0.2).floor()];
    final activeThreshold = math.min(math.max(noiseFloor * 2.5, 0.004), 0.025);
    final peakRms = sortedRms.last;
    if (peakRms < math.max(0.006, noiseFloor * 1.35)) return null;

    var activeFrames = 0;
    var consecutiveActiveFrames = 0;
    var longestActiveRun = 0;
    var firstActive = -1;
    var lastActive = -1;
    for (var index = 0; index < frameRms.length; index++) {
      if (frameRms[index] < activeThreshold) {
        consecutiveActiveFrames = 0;
        continue;
      }
      activeFrames++;
      consecutiveActiveFrames++;
      longestActiveRun = math.max(longestActiveRun, consecutiveActiveFrames);
      firstActive = firstActive < 0 ? index : firstActive;
      lastActive = index;
    }
    // Total energy plus a short continuous run reject taps and scattered
    // keyboard noise while preserving ordinary short words.
    if (activeFrames < 8 || longestActiveRun < 5 || firstActive < 0) {
      return null;
    }

    final paddingSamples = (sampleRate * 0.20).round();
    final startSample = math.max(
      0,
      firstActive * frameSamples - paddingSamples,
    );
    final endSample = math.min(
      sampleCount,
      (lastActive + 1) * frameSamples + paddingSamples,
    );
    return Uint8List.fromList(
      Uint8List.sublistView(pcm16, startSample * 2, endSample * 2),
    );
  }
}

typedef SherpaOnnxAsrService = SherpaAsrService;

final class _SherpaRecognitionRequest {
  const _SherpaRecognitionRequest({
    required this.architecture,
    required this.directoryPath,
    required this.pcm16,
    required this.sampleRate,
    required this.language,
    required this.numThreads,
    required this.modelFile,
    required this.tokensFile,
    required this.encoderFile,
    required this.decoderFile,
    required this.joinerFile,
  });

  final SherpaModelArchitecture architecture;
  final String directoryPath;
  final Uint8List pcm16;
  final int sampleRate;
  final String language;
  final int numThreads;
  final String? modelFile;
  final String tokensFile;
  final String? encoderFile;
  final String? decoderFile;
  final String? joinerFile;
}

String _recognize(_SherpaRecognitionRequest request) {
  sherpa.initBindings();
  final samples = SherpaAsrService.pcm16ToFloat32(request.pcm16);
  return switch (request.architecture) {
    SherpaModelArchitecture.paraformer => _recognizeParaformer(
      request,
      samples,
    ),
    SherpaModelArchitecture.senseVoice => _recognizeSenseVoice(
      request,
      samples,
    ),
    SherpaModelArchitecture.streamingZipformer => _recognizeZipformer(
      request,
      samples,
    ),
  };
}

String _recognizeParaformer(
  _SherpaRecognitionRequest request,
  Float32List samples,
) {
  final modelPath = _requiredModelPath(
    request.directoryPath,
    request.modelFile,
    'Paraformer model',
  );
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        paraformer: sherpa.OfflineParaformerModelConfig(model: modelPath),
        tokens: p.join(request.directoryPath, request.tokensFile),
        numThreads: request.numThreads,
        debug: false,
        modelType: 'paraformer',
      ),
    ),
  );
  sherpa.OfflineStream? stream;
  try {
    stream = recognizer.createStream();
    stream.acceptWaveform(samples: samples, sampleRate: request.sampleRate);
    recognizer.decode(stream);
    return recognizer.getResult(stream).text.trim();
  } finally {
    stream?.free();
    recognizer.free();
  }
}

String _recognizeSenseVoice(
  _SherpaRecognitionRequest request,
  Float32List samples,
) {
  final modelPath = _requiredModelPath(
    request.directoryPath,
    request.modelFile,
    'SenseVoice model',
  );
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        senseVoice: sherpa.OfflineSenseVoiceModelConfig(
          model: modelPath,
          language: request.language,
          useInverseTextNormalization: true,
        ),
        tokens: p.join(request.directoryPath, request.tokensFile),
        numThreads: request.numThreads,
        debug: false,
      ),
    ),
  );
  sherpa.OfflineStream? stream;
  try {
    stream = recognizer.createStream();
    stream.acceptWaveform(samples: samples, sampleRate: request.sampleRate);
    recognizer.decode(stream);
    return recognizer.getResult(stream).text.trim();
  } finally {
    stream?.free();
    recognizer.free();
  }
}

String _recognizeZipformer(
  _SherpaRecognitionRequest request,
  Float32List samples,
) {
  final recognizer = sherpa.OnlineRecognizer(
    sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: _requiredModelPath(
            request.directoryPath,
            request.encoderFile,
            'Zipformer encoder',
          ),
          decoder: _requiredModelPath(
            request.directoryPath,
            request.decoderFile,
            'Zipformer decoder',
          ),
          joiner: _requiredModelPath(
            request.directoryPath,
            request.joinerFile,
            'Zipformer joiner',
          ),
        ),
        tokens: p.join(request.directoryPath, request.tokensFile),
        numThreads: request.numThreads,
        debug: false,
      ),
      enableEndpoint: false,
    ),
  );
  sherpa.OnlineStream? stream;
  try {
    stream = recognizer.createStream();
    final chunkSize = (request.sampleRate ~/ 10).clamp(1, samples.length);
    for (var offset = 0; offset < samples.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, samples.length);
      stream.acceptWaveform(
        samples: Float32List.sublistView(samples, offset, end),
        sampleRate: request.sampleRate,
      );
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
    }

    // Streaming transducers need trailing silence to emit their last tokens.
    stream.acceptWaveform(
      samples: Float32List(request.sampleRate ~/ 2),
      sampleRate: request.sampleRate,
    );
    stream.inputFinished();
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
    }
    return recognizer.getResult(stream).text.trim();
  } finally {
    stream?.free();
    recognizer.free();
  }
}

String _requiredModelPath(
  String directoryPath,
  String? relativePath,
  String label,
) {
  if (relativePath == null || relativePath.isEmpty) {
    throw StateError('$label file is not configured');
  }
  return p.join(directoryPath, relativePath);
}
