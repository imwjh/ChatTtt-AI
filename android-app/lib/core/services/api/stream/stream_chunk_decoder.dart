import 'package:flutter/foundation.dart';

import '../../logging/flutter_logger.dart';
import 'sse_event.dart';
import 'stream_chunk.dart';

/// Stateful, transport-agnostic decoder for one provider response stream.
///
/// Create a fresh instance per response stream. Do not reuse across streams.
abstract class StreamChunkDecoder {
  /// Convert a single raw SSE event into generic stream events.
  ///
  /// A malformed payload must not throw. Return any chunks already parsed
  /// from this frame and leave the stream open so later events can decode.
  /// Upstream in-band errors are thrown before [accept] runs; do not
  /// swallow those.
  DecodeResult accept(SseEvent event);

  /// Flush remaining open series when the SSE connection closes.
  ///
  /// Idempotent: a second call returns an empty list. Do not emit [Finish]
  /// here — the provider emits [Finish] after [onClosed]. A second call
  /// after an explicit terminal event must also be empty.
  List<StreamChunk> onClosed();
}

class DecodeResult {
  const DecodeResult({
    this.chunks = const <StreamChunk>[],
    this.completed = false,
  });

  final List<StreamChunk> chunks;

  /// The provider protocol has ended; the transport may close the connection.
  final bool completed;
}

void logDecoderParseError({
  required String provider,
  required String eventType,
  required Object error,
}) {
  final message = 'provider=$provider eventType=$eventType error=$error';
  debugPrint('[DecoderParseError] $message');
  FlutterLogger.log(message, tag: 'DecoderParseError');
}
