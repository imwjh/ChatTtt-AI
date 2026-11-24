/// One parsed SSE event block.
final class SseEvent {
  final String? event;
  final String? data;
  final String? id;
  final bool hasId;
  final Duration? retry;

  const SseEvent({
    this.event,
    this.data,
    this.id,
    this.hasId = false,
    this.retry,
  });
}

/// Incremental WHATWG event-stream parser shared by every transport.
final class SseParser {
  String _buffer = '';
  String? _event;
  final List<String> _data = [];
  String? _id;
  bool _hasId = false;
  Duration? _retry;
  bool _firstLine = true;

  List<SseEvent> add(String chunk) {
    _buffer += chunk;
    return _drain(finalChunk: false);
  }

  List<SseEvent> close() => _drain(finalChunk: true);

  List<SseEvent> _drain({required bool finalChunk}) {
    final events = <SseEvent>[];
    while (_buffer.isNotEmpty) {
      var end = -1;
      for (var index = 0; index < _buffer.length; index++) {
        final unit = _buffer.codeUnitAt(index);
        if (unit == 0x0a || unit == 0x0d) {
          end = index;
          break;
        }
      }
      if (end < 0) {
        if (finalChunk) {
          _processLine(_buffer, events);
          _buffer = '';
        }
        break;
      }
      if (!finalChunk &&
          _buffer.codeUnitAt(end) == 0x0d &&
          end + 1 == _buffer.length) {
        break;
      }

      final line = _buffer.substring(0, end);
      var delimiterLength = 1;
      if (_buffer.codeUnitAt(end) == 0x0d &&
          end + 1 < _buffer.length &&
          _buffer.codeUnitAt(end + 1) == 0x0a) {
        delimiterLength = 2;
      }
      _buffer = _buffer.substring(end + delimiterLength);
      _processLine(line, events);
    }
    return events;
  }

  void _processLine(String rawLine, List<SseEvent> events) {
    var line = rawLine;
    if (_firstLine) {
      _firstLine = false;
      if (line.startsWith('\ufeff')) line = line.substring(1);
    }
    if (line.isEmpty) {
      if (_event != null || _data.isNotEmpty || _hasId || _retry != null) {
        events.add(
          SseEvent(
            event: _event == null || _event!.isEmpty ? null : _event,
            data: _data.isEmpty ? null : _data.join('\n'),
            id: _id,
            hasId: _hasId,
            retry: _retry,
          ),
        );
      }
      _event = null;
      _data.clear();
      _id = null;
      _hasId = false;
      _retry = null;
      return;
    }
    if (line.startsWith(':')) return;

    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'event':
        _event = value;
      case 'data':
        _data.add(value);
      case 'id':
        if (!value.contains('\u0000')) {
          _id = value;
          _hasId = true;
        }
      case 'retry':
        if (value.isNotEmpty && RegExp(r'^[0-9]+$').hasMatch(value)) {
          final milliseconds = int.tryParse(value);
          if (milliseconds != null) {
            _retry = Duration(milliseconds: milliseconds);
          }
        }
    }
  }
}
