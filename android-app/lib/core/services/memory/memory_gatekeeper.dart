import 'memory_prompts.dart';

/// Gatekeeper parse outcome (§12.4 / §12.8).
///
/// A successfully parsed `false` completes the run and advances the watermark.
/// [malformed] / request failure must **not** advance (§12.8).
enum MemoryGateParseResult { worthRemembering, skip, malformed }

/// Pure Gatekeeper helpers (§12.4).
abstract final class MemoryGatekeeper {
  MemoryGatekeeper._();

  static final RegExp _userMemoryRe = RegExp(
    r'<user_memory>\s*(true|false)',
    caseSensitive: false,
  );

  /// Resolve the prompt template: user override if non-empty, else built-in.
  static String resolveTemplate({
    required MemoryPromptLang lang,
    String? overrideZh,
    String? overrideEn,
  }) {
    if (lang == MemoryPromptLang.zh) {
      final o = overrideZh?.trim();
      if (o != null && o.isNotEmpty) return o;
      return MemoryPrompts.gateZh;
    }
    final o = overrideEn?.trim();
    if (o != null && o.isNotEmpty) return o;
    return MemoryPrompts.gateEn;
  }

  static String buildPrompt({
    required MemoryPromptLang lang,
    required String conversation,
    String? overrideZh,
    String? overrideEn,
  }) {
    return resolveTemplate(
      lang: lang,
      overrideZh: overrideZh,
      overrideEn: overrideEn,
    ).replaceAll('{{conversation}}', conversation);
  }

  /// Parse Gatekeeper XML. Tolerates surrounding prose; unmatched → [malformed].
  static MemoryGateParseResult parse(String response) {
    final match = _userMemoryRe.firstMatch(response);
    if (match == null) return MemoryGateParseResult.malformed;
    final value = match.group(1)!.toLowerCase();
    if (value == 'true') return MemoryGateParseResult.worthRemembering;
    if (value == 'false') return MemoryGateParseResult.skip;
    return MemoryGateParseResult.malformed;
  }
}
