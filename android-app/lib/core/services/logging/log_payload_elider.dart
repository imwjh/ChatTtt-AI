/// A large binary payload that was replaced by a placeholder in a log.
class LogPayloadRef {
  const LogPayloadRef({required this.mime, required this.base64Chars});

  final String mime;

  /// Length of the elided base64 text, in characters.
  final int base64Chars;

  /// Approximate size of the decoded payload.
  int get byteLength => (base64Chars * 3) ~/ 4;

  @override
  bool operator ==(Object other) =>
      other is LogPayloadRef &&
      other.mime == mime &&
      other.base64Chars == base64Chars;

  @override
  int get hashCode => Object.hash(mime, base64Chars);

  @override
  String toString() => 'LogPayloadRef($mime, $base64Chars chars)';
}

/// Result of a single elision pass.
class LogPayloadElision {
  const LogPayloadElision({required this.text, required this.refs});

  final String text;
  final List<LogPayloadRef> refs;
}

/// Replaces inline base64 payloads (images, files, audio) with short
/// placeholders so logs stay small enough to write, parse and render.
///
/// Covers the three shapes providers use:
/// * OpenAI-compatible — `"url": "data:image/png;base64,<payload>"`
/// * Claude — `{"type":"base64","media_type":"image/png","data":"<payload>"}`
/// * Gemini — `{"inline_data":{"mime_type":"image/png","data":"<payload>"}}`
///
/// Scanning is done by hand rather than with a `RegExp`. Dart's regex engine
/// backtracks, and a quantifier over a multi-megabyte payload overflows the
/// native stack — which is precisely the input this class exists to handle.
class LogPayloadElider {
  LogPayloadElider._();

  /// Bare base64 runs shorter than this are kept verbatim.
  static const int bareBase64Threshold = 4096;

  static const String fallbackMime = 'application/octet-stream';

  static const String _b64Marker = ';base64,';

  /// How far back a `data:` prefix may sit from its `;base64,` marker.
  /// Bounds the work spent rejecting a non-match.
  static const int _mimeLookback = 128;

  /// How far back to look for the `mime_type` field beside a bare payload.
  static const int _mimeHintWindow = 200;

  static const int _quote = 0x22; // "
  static const int _comma = 0x2C; // ,
  static const int _colon = 0x3A; // :
  static const int _semi = 0x3B; // ;
  static const int _equals = 0x3D; // =

  static final RegExp _mimeHintRe = RegExp(
    r'"(?:mime_type|mimeType|media_type|mediaType)"\s*:\s*"([^"]{1,120})"',
  );

  /// Both passes. Placeholders never contain `"` or `\`, so a JSON body stays
  /// decodable afterwards.
  static String elide(String text) =>
      _bareBase64Pass(elideDataUris(text), null);

  /// Replaces inlined `data:...;base64,...` payloads with a short placeholder.
  static String elideDataUris(String text) => _dataUriPass(text, null);

  /// Replaces long unbroken base64 JSON string values with a placeholder.
  static String elideBareBase64(String text) => _bareBase64Pass(text, null);

  static String placeholder(int chars) => '<omitted $chars chars>';

  /// Elides and reports in one walk — cheaper than calling [elide] and
  /// [describe] separately.
  ///
  /// Set [rewrite] to false to report payloads without replacing them. Refs
  /// are collected either way, and cover payloads that were already replaced
  /// by a placeholder on the way into the log.
  static LogPayloadElision process(String text, {bool rewrite = true}) {
    final refs = <LogPayloadRef>[];
    final afterUris = _dataUriPass(text, refs, rewrite: rewrite);
    final out = _bareBase64Pass(afterUris, refs, rewrite: rewrite);
    return LogPayloadElision(text: out, refs: refs);
  }

  /// Describes the payloads [elide] would remove, for the log viewer's
  /// attachment chips.
  static List<LogPayloadRef> describe(String text) => process(text).refs;

  // ---------------------------------------------------------------- passes

  static String _dataUriPass(
    String text,
    List<LogPayloadRef>? refs, {
    bool rewrite = true,
  }) {
    final len = text.length;
    StringBuffer? out;
    var last = 0;
    var from = 0;

    while (from < len) {
      final marker = text.indexOf(_b64Marker, from);
      if (marker < 0) break;

      final uriStart = _dataUriStart(text, marker);
      if (uriStart < 0) {
        from = marker + _b64Marker.length;
        continue;
      }

      final payloadStart = marker + _b64Marker.length;
      final mime = text.substring(uriStart + 5, marker);

      // Already elided on the way into the log — report it, leave it be.
      final existing = _readPlaceholder(text, payloadStart);
      if (existing != null) {
        refs?.add(LogPayloadRef(mime: mime, base64Chars: existing.chars));
        from = existing.end;
        continue;
      }

      final payloadEnd = _payloadEnd(text, payloadStart);
      if (payloadEnd <= payloadStart) {
        from = payloadStart;
        continue;
      }

      final chars = payloadEnd - payloadStart;
      refs?.add(LogPayloadRef(mime: mime, base64Chars: chars));
      from = payloadEnd;

      if (!rewrite) continue;
      out ??= StringBuffer();
      out.write(text.substring(last, payloadStart));
      out.write(placeholder(chars));
      last = payloadEnd;
    }

    if (out == null) return text;
    out.write(text.substring(last));
    return out.toString();
  }

  static String _bareBase64Pass(
    String text,
    List<LogPayloadRef>? refs, {
    bool rewrite = true,
  }) {
    final len = text.length;

    StringBuffer? out;
    var last = 0;
    var i = 0;

    while (i < len) {
      if (text.codeUnitAt(i) != _quote) {
        i++;
        continue;
      }

      // A payload already replaced on the way into the log.
      final existing = _readPlaceholder(text, i + 1);
      if (existing != null &&
          existing.end < len &&
          text.codeUnitAt(existing.end) == _quote) {
        refs?.add(
          LogPayloadRef(
            mime: _mimeBefore(text, i + 1),
            base64Chars: existing.chars,
          ),
        );
        i = existing.end + 1;
        continue;
      }

      if (len <= bareBase64Threshold) {
        i++;
        continue;
      }

      final start = i + 1;
      var end = start;
      while (end < len && _isBase64Unit(text.codeUnitAt(end))) {
        end++;
      }

      var close = end;
      var pad = 0;
      while (close < len && pad < 2 && text.codeUnitAt(close) == _equals) {
        close++;
        pad++;
      }

      final isPayload =
          close < len &&
          text.codeUnitAt(close) == _quote &&
          (end - start) >= bareBase64Threshold;

      if (isPayload) {
        final chars = close - start;
        refs?.add(
          // Look back from the opening quote — the mime field precedes it.
          LogPayloadRef(mime: _mimeBefore(text, start), base64Chars: chars),
        );
        i = close + 1;
        if (rewrite) {
          out ??= StringBuffer();
          out.write(text.substring(last, start));
          out.write(placeholder(chars));
          last = close;
        }
        continue;
      }

      // Skip the run we just measured; it cannot contain an opening quote.
      i = close > start ? close : i + 1;
    }

    if (out == null) return text;
    out.write(text.substring(last));
    return out.toString();
  }

  // --------------------------------------------------------------- helpers

  /// Index of the `data:` that opens the URI whose marker sits at [marker],
  /// or -1 when the marker is not part of a data URI.
  static int _dataUriStart(String text, int marker) {
    final lo = marker - _mimeLookback < 0 ? 0 : marker - _mimeLookback;

    // The mime type is `[^;,\s]+`, so walk back only over those characters.
    var i = marker;
    while (i > lo) {
      final c = text.codeUnitAt(i - 1);
      if (c == _semi || c == _comma || _isSpace(c)) break;
      i--;
    }

    // Leftmost `data:` that still leaves a non-empty mime type.
    for (var p = i; p + 5 < marker; p++) {
      if (_isDataPrefix(text, p)) return p;
    }
    return -1;
  }

  /// End of the base64 run starting at [start]. Whitespace and `=` are part
  /// of the run, matching how these payloads are written across providers.
  static int _payloadEnd(String text, int start) {
    final len = text.length;
    var end = start;
    while (end < len) {
      final c = text.codeUnitAt(end);
      if (_isBase64Unit(c) || c == _equals || _isSpace(c)) {
        end++;
        continue;
      }
      break;
    }
    return end;
  }

  /// Reads a `<omitted N chars>` placeholder at [start], so a payload the
  /// writer already elided is still reported as an attachment.
  static ({int chars, int end})? _readPlaceholder(String text, int start) {
    const head = '<omitted ';
    const tail = ' chars>';
    if (!text.startsWith(head, start)) return null;

    var p = start + head.length;
    final digitsFrom = p;
    while (p < text.length) {
      final c = text.codeUnitAt(p);
      if (c < 0x30 || c > 0x39) break;
      p++;
    }
    if (p == digitsFrom) return null;
    if (!text.startsWith(tail, p)) return null;

    final chars = int.tryParse(text.substring(digitsFrom, p));
    if (chars == null) return null;
    return (chars: chars, end: p + tail.length);
  }

  /// Looks back a short window for the mime field beside a bare payload.
  static String _mimeBefore(String text, int start) {
    final from = start - _mimeHintWindow < 0 ? 0 : start - _mimeHintWindow;
    final slice = text.substring(from, start);
    String? last;
    for (final m in _mimeHintRe.allMatches(slice)) {
      last = m[1];
    }
    return last ?? fallbackMime;
  }

  static bool _isDataPrefix(String t, int p) {
    return _lower(t.codeUnitAt(p)) == 0x64 && // d
        _lower(t.codeUnitAt(p + 1)) == 0x61 && // a
        _lower(t.codeUnitAt(p + 2)) == 0x74 && // t
        _lower(t.codeUnitAt(p + 3)) == 0x61 && // a
        t.codeUnitAt(p + 4) == _colon;
  }

  static int _lower(int c) => (c >= 0x41 && c <= 0x5A) ? c + 32 : c;

  static bool _isBase64Unit(int c) =>
      (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A) || // a-z
      (c >= 0x30 && c <= 0x39) || // 0-9
      c == 0x2B || // +
      c == 0x2F; // /

  static bool _isSpace(int c) =>
      c == 0x20 ||
      c == 0x09 ||
      c == 0x0A ||
      c == 0x0D ||
      c == 0x0B ||
      c == 0x0C;
}
