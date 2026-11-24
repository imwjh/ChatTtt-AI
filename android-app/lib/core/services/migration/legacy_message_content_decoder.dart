import '../../models/message_part.dart';
import '../../utils/multimodal_input_utils.dart';
import '../../../utils/sandbox_path_resolver.dart';

class LegacyDecodeResult {
  final List<MessagePart> parts;
  final int converted;
  final int malformed;
  final int missingFiles;

  const LegacyDecodeResult({
    required this.parts,
    required this.converted,
    required this.malformed,
    required this.missingFiles,
  });
}

/// Decode legacy marker-bearing content into structured [MessagePart]s.
///
/// This is the only runtime-adjacent place allowed to recognize
/// `[image:…]` / `[file:…]` markers. Production send/render paths must not
/// reintroduce marker parsing.
///
/// When [existingParts] already contains image/file parts, the input is
/// returned unchanged (message-level idempotency).
Future<LegacyDecodeResult> decodeLegacyContent(
  String content, {
  List<MessagePart>? existingParts,
  bool Function(String path)? fileExists,
}) async {
  if (existingParts != null &&
      existingParts.any((part) => part is ImagePart || part is FilePart)) {
    return LegacyDecodeResult(
      parts: existingParts,
      converted: 0,
      malformed: 0,
      missingFiles: 0,
    );
  }

  if (content.isEmpty) {
    return const LegacyDecodeResult(
      parts: <MessagePart>[],
      converted: 0,
      malformed: 0,
      missingFiles: 0,
    );
  }

  final exists = fileExists ?? _defaultFileExists;
  final parts = <MessagePart>[];
  final textLines = <_ContentLine>[];
  var converted = 0;
  var malformed = 0;
  var missingFiles = 0;
  _FenceState? fence;
  // When a convertible marker is removed between text runs, keep one newline so
  // joining TextPart payloads (no separator) yields `a\nb` rather than `ab`.
  // The separator is the original ending that followed the preceding text line.
  String? pendingEnding;
  String lastFlushedEol = '\n';

  void flushText() {
    if (textLines.isEmpty) return;
    lastFlushedEol = textLines.last.eol.isNotEmpty ? textLines.last.eol : '\n';
    parts.add(TextPart(_joinContentLines(textLines)));
    textLines.clear();
  }

  void addTextLine(_ContentLine line) {
    if (pendingEnding != null && textLines.isEmpty) {
      textLines.add(_ContentLine(text: '', eol: pendingEnding!));
    }
    pendingEnding = null;
    textLines.add(line);
  }

  void markAttachmentBoundary() {
    flushText();
    if (parts.any((part) => part is TextPart)) {
      pendingEnding ??= lastFlushedEol;
    } else {
      pendingEnding = null;
    }
  }

  for (final line in _splitKeepingEndings(content)) {
    if (fence != null) {
      addTextLine(line);
      if (_isClosingFence(line.text, fence)) {
        fence = null;
      }
      continue;
    }

    final opened = _matchOpeningFence(line.text);
    if (opened != null) {
      fence = opened;
      addTextLine(line);
      continue;
    }

    final imageUri = _matchExclusiveImageMarker(line.text);
    if (imageUri != null) {
      if (imageUri.isEmpty) {
        malformed += 1;
        addTextLine(line);
        continue;
      }
      markAttachmentBoundary();
      final local = _isLocalPath(imageUri);
      final missing = local && !exists(imageUri);
      if (missing) missingFiles += 1;
      final mime = await inferAttachmentMime(uri: imageUri);
      parts.add(
        ImagePart(
          uri: SandboxPathResolver.canonicalize(imageUri),
          mime: mime,
          unavailable: missing,
        ),
      );
      converted += 1;
      continue;
    }

    final fileMarker = _matchExclusiveFileMarker(line.text);
    if (fileMarker != null) {
      final parsed = _parseFileMarker(fileMarker);
      if (parsed == null) {
        malformed += 1;
        addTextLine(line);
        continue;
      }
      markAttachmentBoundary();
      final local = _isLocalPath(parsed.uri);
      final missing = local && !exists(parsed.uri);
      if (missing) missingFiles += 1;
      final mime = await inferAttachmentMime(
        uri: parsed.uri,
        explicitMime: parsed.mime,
        fileName: parsed.name,
      );
      parts.add(
        FilePart(
          uri: SandboxPathResolver.canonicalize(parsed.uri),
          name: parsed.name,
          mime: mime,
          unavailable: missing,
        ),
      );
      converted += 1;
      continue;
    }

    addTextLine(line);
  }

  flushText();

  return LegacyDecodeResult(
    parts: List<MessagePart>.unmodifiable(parts),
    converted: converted,
    malformed: malformed,
    missingFiles: missingFiles,
  );
}

/// Independently strip convertible exclusive markers from legacy content and
/// return the remaining text segments (with newlines preserved across removed
/// markers). Used for migration digest expectations so validation does not
/// merely echo decoder [TextPart] objects.
///
/// Joining the returned segments with an empty separator matches
/// [ChatMessage.content] after a successful decode of the same input.
List<String> stripLegacyContentTextSegments(String content) {
  if (content.isEmpty) return const [''];

  final segments = <String>[];
  final textLines = <_ContentLine>[];
  _FenceState? fence;
  String? pendingEnding;
  String lastFlushedEol = '\n';

  void flushText() {
    if (textLines.isEmpty) return;
    lastFlushedEol = textLines.last.eol.isNotEmpty ? textLines.last.eol : '\n';
    segments.add(_joinContentLines(textLines));
    textLines.clear();
  }

  void addTextLine(_ContentLine line) {
    if (pendingEnding != null && textLines.isEmpty) {
      textLines.add(_ContentLine(text: '', eol: pendingEnding!));
    }
    pendingEnding = null;
    textLines.add(line);
  }

  void markAttachmentBoundary() {
    flushText();
    if (segments.isNotEmpty) {
      pendingEnding ??= lastFlushedEol;
    } else {
      pendingEnding = null;
    }
  }

  for (final line in _splitKeepingEndings(content)) {
    if (fence != null) {
      addTextLine(line);
      if (_isClosingFence(line.text, fence)) {
        fence = null;
      }
      continue;
    }

    final opened = _matchOpeningFence(line.text);
    if (opened != null) {
      fence = opened;
      addTextLine(line);
      continue;
    }

    final imageUri = _matchExclusiveImageMarker(line.text);
    if (imageUri != null) {
      if (imageUri.isEmpty) {
        addTextLine(line);
        continue;
      }
      markAttachmentBoundary();
      continue;
    }

    final fileMarker = _matchExclusiveFileMarker(line.text);
    if (fileMarker != null) {
      final parsed = _parseFileMarker(fileMarker);
      if (parsed == null) {
        addTextLine(line);
        continue;
      }
      markAttachmentBoundary();
      continue;
    }

    addTextLine(line);
  }

  flushText();
  // Reaching here with no segments means every line was a convertible marker
  // (empty content already returned [''] above). The decoder emits no TextPart
  // for such attachment-only content and the migration service only
  // substitutes TextPart('') when the part list is entirely empty, so the
  // digest expectation must also be empty.
  if (segments.isEmpty) return const <String>[];
  return List<String>.unmodifiable(segments);
}

final RegExp _exclusiveImage = RegExp(r'^\[image:(.*)\]$');
final RegExp _exclusiveFile = RegExp(r'^\[file:(.*)\]$');
final RegExp _validFileSegments = RegExp(
  r'^\[file:([^|\]]+)\|([^|\]]+)\|([^|\]]*)\]$',
);
final RegExp _openingFence = RegExp(r'^( {0,3})(`{3,}|~{3,})(.*)$');

class _ContentLine {
  final String text;
  final String eol;
  const _ContentLine({required this.text, required this.eol});
}

class _FenceState {
  final String char;
  final int length;
  const _FenceState({required this.char, required this.length});
}

/// Split [content] while preserving each original `\r\n` / `\n` / `\r`
/// separator. Mirrors `split` on line breaks by keeping a trailing empty line
/// when [content] ends with a newline.
List<_ContentLine> _splitKeepingEndings(String content) {
  if (content.isEmpty) return const <_ContentLine>[];

  final out = <_ContentLine>[];
  final re = RegExp(r'\r\n|\n|\r');
  var start = 0;
  for (final match in re.allMatches(content)) {
    out.add(
      _ContentLine(
        text: content.substring(start, match.start),
        eol: match.group(0)!,
      ),
    );
    start = match.end;
  }
  if (start < content.length) {
    out.add(_ContentLine(text: content.substring(start), eol: ''));
  } else {
    // Trailing newline → empty final line, matching String.split behavior.
    out.add(const _ContentLine(text: '', eol: ''));
  }
  return out;
}

String _joinContentLines(List<_ContentLine> lines) {
  if (lines.isEmpty) return '';
  final buffer = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    buffer.write(lines[i].text);
    if (i < lines.length - 1) {
      buffer.write(lines[i].eol);
    }
  }
  return buffer.toString();
}

/// CommonMark opening fence: optional 0–3 spaces + run of 3+ ` or ~.
/// Info string is allowed only on the opening fence; backtick fences reject
/// info strings that themselves contain backticks.
_FenceState? _matchOpeningFence(String line) {
  final match = _openingFence.firstMatch(line);
  if (match == null) return null;
  final run = match.group(2)!;
  final char = run[0];
  final info = match.group(3) ?? '';
  if (char == '`' && info.contains('`')) return null;
  return _FenceState(char: char, length: run.length);
}

/// CommonMark closing fence: optional 0–3 spaces + run of the same character
/// with length >= opening length, then optional spaces to EOL only.
bool _isClosingFence(String line, _FenceState fence) {
  final escaped = RegExp.escape(fence.char);
  final closing = RegExp('^( {0,3})($escaped{${fence.length},}) *\$');
  return closing.hasMatch(line);
}

String? _matchExclusiveImageMarker(String line) {
  final match = _exclusiveImage.firstMatch(line);
  if (match == null) return null;
  return (match.group(1) ?? '').trim();
}

String? _matchExclusiveFileMarker(String line) {
  final match = _exclusiveFile.firstMatch(line);
  return match?.group(1);
}

({String uri, String name, String mime})? _parseFileMarker(String inner) {
  // Re-validate against the strict 3-segment form on the reconstructed line.
  final match = _validFileSegments.firstMatch('[file:$inner]');
  if (match == null) return null;
  final uri = match.group(1)!.trim();
  final name = match.group(2)!.trim();
  final mime = match.group(3)!.trim();
  if (uri.isEmpty || name.isEmpty) return null;
  return (uri: uri, name: name, mime: mime);
}

bool _isLocalPath(String uri) => !isRemoteOrDataUri(uri);

bool _defaultFileExists(String path) {
  // Do not use fix(): its generic `/images/`·basename probe can mark a
  // missing external path available when a same-named managed file exists.
  return SandboxPathResolver.localFileExists(path);
}
