/// Smart Add candidate tokenizer (§12.6) and LIKE escaping (§5.9).
abstract final class MemoryTokenizer {
  MemoryTokenizer._();

  /// Chinese stop characters / words that must be filtered from CJK 2-grams.
  static const Set<String> cjkStopwords = {
    '用户',
    '的',
    '了',
    '是',
    '在',
    '和',
    '与',
    '会',
    '要',
    '对',
    '这',
    '那',
    '他',
    '她',
    '它',
  };

  /// English stopwords (lowercase). Includes `user` / `users` (appendix item 8).
  static const Set<String> englishStopwords = {
    'the',
    'a',
    'an',
    'of',
    'to',
    'and',
    'or',
    'in',
    'on',
    'for',
    'with',
    'user',
    'users',
    'prefer',
    'prefers',
  };

  static final RegExp _cjkChar = RegExp(
    r'[\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff]',
  );
  static final RegExp _latinWord = RegExp(r'[a-z0-9]{2,}');

  /// Tokenize [text] for Smart Add candidate retrieval.
  ///
  /// - English/numbers: split on whitespace and punctuation; keep length ≥ 2;
  ///   drop stopwords; lowercase.
  /// - CJK: 2-grams; drop grams containing a stopword character/word; lowercase.
  /// - At most 8 tokens, in left-to-right encounter order.
  /// Tokens are deduplicated: a repeated token would be counted twice in the
  /// `hits` sum and distort candidate ranking.
  static List<String> tokenize(String text) {
    final lower = text.toLowerCase();
    final tokens = <String>{};

    var index = 0;
    while (index < lower.length && tokens.length < 8) {
      final ch = lower[index];
      if (_cjkChar.hasMatch(ch)) {
        final start = index;
        while (index < lower.length && _cjkChar.hasMatch(lower[index])) {
          index++;
        }
        final run = lower.substring(start, index);
        _addCjkBigrams(run, tokens);
      } else {
        final start = index;
        while (index < lower.length && !_cjkChar.hasMatch(lower[index])) {
          index++;
        }
        final run = lower.substring(start, index);
        _addLatinWords(run, tokens);
      }
    }

    return tokens.toList(growable: false);
  }

  static void _addCjkBigrams(String run, Set<String> tokens) {
    if (run.length < 2) return;
    for (var i = 0; i < run.length - 1 && tokens.length < 8; i++) {
      final gram = run.substring(i, i + 2);
      if (_cjkGramHasStopword(gram)) continue;
      tokens.add(gram);
    }
  }

  static bool _cjkGramHasStopword(String gram) {
    for (final stop in cjkStopwords) {
      if (gram.contains(stop)) return true;
    }
    return false;
  }

  static void _addLatinWords(String run, Set<String> tokens) {
    for (final match in _latinWord.allMatches(run)) {
      if (tokens.length >= 8) return;
      final word = match.group(0)!;
      if (englishStopwords.contains(word)) continue;
      tokens.add(word);
    }
  }

  /// Escape `%`, `_`, and `\` with `\` for SQL `LIKE ... ESCAPE '\'` (§5.9).
  static String escapeLike(String token) {
    return token
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }
}
