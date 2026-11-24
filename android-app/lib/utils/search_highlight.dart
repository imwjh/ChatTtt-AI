import 'package:flutter/painting.dart';

List<TextSpan> highlightSearchText(
  String text,
  List<String> tokens,
  TextStyle base,
  TextStyle highlight,
) {
  if (tokens.isEmpty || text.isEmpty) {
    return [TextSpan(text: text, style: base)];
  }
  final spans = <TextSpan>[];
  final lower = text.toLowerCase();
  int pos = 0;
  while (pos < text.length) {
    int earliest = -1;
    int earliestLen = 0;
    for (final t in tokens) {
      final idx = lower.indexOf(t, pos);
      if (idx >= 0 && (earliest < 0 || idx < earliest)) {
        earliest = idx;
        earliestLen = t.length;
      }
    }
    if (earliest < 0) {
      spans.add(TextSpan(text: text.substring(pos), style: base));
      break;
    }
    if (earliest > pos) {
      spans.add(TextSpan(text: text.substring(pos, earliest), style: base));
    }
    spans.add(
      TextSpan(
        text: text.substring(earliest, earliest + earliestLen),
        style: highlight,
      ),
    );
    pos = earliest + earliestLen;
  }
  return spans;
}
