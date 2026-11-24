import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/assistant.dart';

/// What caused a background memory run to start.
enum MemoryTraceTrigger {
  /// Automatic organize after the assistant's turn threshold was reached.
  autoTurns,

  /// User pressed "organize now".
  manual,

  /// A model tool call (`memory_*` / `chat_search`).
  toolCall,

  /// Background conversation summary generation (feeds past-conversation recall).
  conversationSummary,
}

/// Whether the run wrote into assistant-scoped or global memory.
enum MemoryTraceScope { assistant, global }

/// Map an assistant write policy onto the scope label shown in a trace.
MemoryTraceScope memoryTraceScopeOf(MemoryWriteScope scope) {
  switch (scope) {
    case MemoryWriteScope.alwaysGlobal:
    case MemoryWriteScope.toolDefaultGlobal:
      return MemoryTraceScope.global;
    case MemoryWriteScope.alwaysAssistant:
    case MemoryWriteScope.toolDefaultAssistant:
      return MemoryTraceScope.assistant;
  }
}

/// One stage of background memory work.
enum MemoryTraceStepKind {
  gatekeeper,
  extract,
  smartAdd,
  profileDistiller,
  conversationSummary,
  chatSearch,
  memoryTool,
}

enum MemoryTraceStepStatus { running, skipped, success, failed }

/// A concrete change the run applied to stored state.
enum MemoryTraceMutationKind {
  memoryCreated,
  memoryMerged,
  memoryEdited,
  memoryArchived,
  memoryLinked,
  profileFieldWritten,
  profileFieldCleared,
  conversationSummaryWritten,
}

class MemoryTraceMutation {
  const MemoryTraceMutation({
    required this.kind,
    this.targetId,
    this.label,
    this.before,
    this.after,
  });

  final MemoryTraceMutationKind kind;

  /// Memory entry id / profile field key / conversation id.
  final String? targetId;

  /// Extra qualifier such as the memory type or the scope.
  final String? label;

  final String? before;
  final String? after;
}

/// One recorded pipeline stage, with everything needed to debug it.
class MemoryTraceStep {
  MemoryTraceStep({required this.kind, required this.startedAt, this.label});

  final MemoryTraceStepKind kind;

  /// Free-form qualifier, e.g. the tool name for [MemoryTraceStepKind.memoryTool].
  final String? label;

  final DateTime startedAt;
  DateTime? endedAt;

  MemoryTraceStepStatus status = MemoryTraceStepStatus.running;

  /// Exact prompt(s) sent to the model. Multiple calls are appended in order.
  String get prompt => _prompt.toString();

  /// Raw model response(s), in the same order as [prompt].
  String get rawResponse => _rawResponse.toString();

  /// Human-readable parsed result (JSON when structured).
  String? parsedResult;

  String? error;

  final List<MemoryTraceMutation> mutations = <MemoryTraceMutation>[];

  final StringBuffer _prompt = StringBuffer();
  final StringBuffer _rawResponse = StringBuffer();
  int _promptParts = 0;
  int _responseParts = 0;

  Duration? get duration => endedAt?.difference(startedAt);

  void appendPrompt(String text) {
    _promptParts++;
    if (_promptParts > 1) {
      _prompt.write('\n\n─── #$_promptParts ───\n\n');
    }
    _prompt.write(text);
  }

  void appendResponse(String text) {
    _responseParts++;
    if (_responseParts > 1) {
      _rawResponse.write('\n\n─── #$_responseParts ───\n\n');
    }
    _rawResponse.write(text);
  }

  void addMutation(MemoryTraceMutation mutation) => mutations.add(mutation);

  void setParsedJson(Object? value) {
    try {
      parsedResult = const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      parsedResult = value?.toString();
    }
  }

  void finish(MemoryTraceStepStatus status, {String? error, DateTime? at}) {
    this.status = status;
    this.error = error ?? this.error;
    endedAt = at ?? DateTime.now();
  }
}

/// Everything that happened for one background memory trigger.
class MemoryTrace {
  MemoryTrace({
    required this.id,
    required this.startedAt,
    required this.trigger,
    required this.scope,
    this.conversationId,
    this.conversationTitle,
    this.assistantId,
    this.assistantName,
    this.watermark,
    this.windowStartOrder,
    this.windowEndOrder,
    this.windowSize = 0,
  });

  final String id;
  final DateTime startedAt;
  DateTime? endedAt;

  final MemoryTraceTrigger trigger;
  final MemoryTraceScope scope;

  final String? conversationId;
  final String? conversationTitle;

  /// Null for runs that are not bound to an assistant.
  final String? assistantId;
  final String? assistantName;

  /// Watermark (message order) the run started from.
  int? watermark;
  int? windowStartOrder;
  int? windowEndOrder;
  int windowSize;

  final List<MemoryTraceStep> steps = <MemoryTraceStep>[];

  bool advanced = false;
  bool forcedAdvance = false;

  /// Pipeline error / skip reason code, e.g. `below_threshold`.
  String? error;

  /// How many identical consecutive no-op triggers this entry stands for.
  int repeatCount = 1;

  Duration? get duration => endedAt?.difference(startedAt);

  bool get hasError => (error ?? '').isNotEmpty;

  /// A trigger that never reached the model (gating / threshold checks).
  bool get isNoOp => steps.isEmpty;

  int get mutationCount {
    var total = 0;
    for (final step in steps) {
      total += step.mutations.length;
    }
    return total;
  }
}

/// Live handle used by the pipeline to fill in a trace.
///
/// Every method swallows its own failures: observability must never break the
/// pipeline.
class MemoryTraceHandle {
  MemoryTraceHandle(this._recorder, this.trace);

  final MemoryTraceRecorder _recorder;
  final MemoryTrace trace;
  bool _committed = false;

  MemoryTraceStep? beginStep(MemoryTraceStepKind kind, {String? label}) {
    try {
      final step = MemoryTraceStep(
        kind: kind,
        startedAt: DateTime.now(),
        label: label,
      );
      trace.steps.add(step);
      return step;
    } catch (_) {
      return null;
    }
  }

  void setWindow({int? watermark, int? startOrder, int? endOrder, int? size}) {
    try {
      trace.watermark = watermark ?? trace.watermark;
      trace.windowStartOrder = startOrder ?? trace.windowStartOrder;
      trace.windowEndOrder = endOrder ?? trace.windowEndOrder;
      trace.windowSize = size ?? trace.windowSize;
    } catch (_) {}
  }

  /// Finalize the outcome and publish the trace.
  void commit({
    bool advanced = false,
    bool forcedAdvance = false,
    String? error,
  }) {
    if (_committed) return;
    _committed = true;
    try {
      trace.advanced = advanced;
      trace.forcedAdvance = forcedAdvance;
      trace.error = error;
      trace.endedAt = DateTime.now();
      for (final step in trace.steps) {
        if (step.status == MemoryTraceStepStatus.running) {
          step.finish(MemoryTraceStepStatus.failed, error: error);
        }
      }
      _recorder.publish(trace);
    } catch (_) {}
  }
}

/// In-memory ring buffer of recent background memory traces.
///
/// Traces hold full prompts and raw responses, so they are large: a single
/// organize run can carry ~5 prompts built from a 12 KB conversation window
/// plus their responses (~100 KB worst case). [maxTraces] is therefore kept at
/// 24 — roughly a working session's worth of runs, bounded at a couple of MB —
/// and nothing is ever persisted.
class MemoryTraceRecorder extends ChangeNotifier {
  /// [_enabled] mirrors the user preference; pass false to start suppressed.
  MemoryTraceRecorder([this._enabled = true]);

  /// Process-wide recorder used by the pipeline and the viewer page.
  static final MemoryTraceRecorder instance = MemoryTraceRecorder();

  static const int maxTraces = 24;

  final Queue<MemoryTrace> _traces = Queue<MemoryTrace>();
  bool _enabled;
  int _seq = 0;

  bool get enabled => _enabled;

  /// Newest first.
  List<MemoryTrace> get traces =>
      List<MemoryTrace>.unmodifiable(_traces.toList().reversed);

  int get length => _traces.length;

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) {
      _traces.clear();
    }
    notifyListeners();
  }

  void clear() {
    if (_traces.isEmpty) return;
    _traces.clear();
    notifyListeners();
  }

  /// Start a trace, or return null when recording is off.
  MemoryTraceHandle? begin({
    required MemoryTraceTrigger trigger,
    required MemoryTraceScope scope,
    String? conversationId,
    String? conversationTitle,
    String? assistantId,
    String? assistantName,
  }) {
    if (!_enabled) return null;
    _seq++;
    final trace = MemoryTrace(
      id: 'trace_${DateTime.now().microsecondsSinceEpoch}_$_seq',
      startedAt: DateTime.now(),
      trigger: trigger,
      scope: scope,
      conversationId: conversationId,
      conversationTitle: conversationTitle,
      assistantId: assistantId,
      assistantName: assistantName,
    );
    return MemoryTraceHandle(this, trace);
  }

  /// Store a finished trace. Called by [MemoryTraceHandle.commit].
  @visibleForTesting
  void publish(MemoryTrace trace) {
    if (!_enabled) return;
    // Coalesce repeated no-op triggers (e.g. "below_threshold" after every
    // turn) so they cannot push real runs out of the buffer.
    final newest = _traces.isEmpty ? null : _traces.last;
    if (newest != null &&
        trace.isNoOp &&
        newest.isNoOp &&
        newest.trigger == trace.trigger &&
        newest.conversationId == trace.conversationId &&
        newest.error == trace.error) {
      newest.repeatCount++;
      newest.endedAt = trace.endedAt;
      notifyListeners();
      return;
    }
    _traces.addLast(trace);
    while (_traces.length > maxTraces) {
      _traces.removeFirst();
    }
    notifyListeners();
  }
}
