import '../../models/chat_message.dart';
import '../../models/conversation.dart';

/// Field-level repair for dirty legacy (1.1.17 / Hive-era) records so they
/// satisfy the SQLite CHECK constraints. Shared by the Hive-to-SQLite
/// migration and the chats.json import boundary: both read data written by
/// the old runtime, which tolerated shapes the new schema rejects (device
/// clock rollback could persist negative durations, corrupted records could
/// carry empty roles or out-of-range counters).
///
/// Returns the input object unchanged (identical) when nothing needed repair,
/// so callers can count repairs via `identical(...)`.
ChatMessage sanitizeLegacyMessageFields(ChatMessage message) {
  var changed = false;
  int? nonNegativeOrNull(int? value) {
    if (value != null && value < 0) {
      changed = true;
      return null;
    }
    return value;
  }

  // message_rows enforces CHECK (role != ''). An empty role can only come
  // from a corrupted legacy record; default it to 'user' rather than losing
  // the message.
  var role = message.role;
  if (role.isEmpty) {
    changed = true;
    role = 'user';
  }
  final totalTokens = nonNegativeOrNull(message.totalTokens);
  final promptTokens = nonNegativeOrNull(message.promptTokens);
  final completionTokens = nonNegativeOrNull(message.completionTokens);
  final cachedTokens = nonNegativeOrNull(message.cachedTokens);
  final durationMs = nonNegativeOrNull(message.durationMs);
  // Clamp instead of null: version is non-nullable and feeds the
  // (conversationId, groupId, version) uniqueness repair that both callers
  // run after this, which resolves any collision introduced by clamping.
  var version = message.version;
  if (version < 0) {
    changed = true;
    version = 0;
  }
  var reasoningFinishedAt = message.reasoningFinishedAt;
  final reasoningStartAt = message.reasoningStartAt;
  if (reasoningFinishedAt != null &&
      reasoningStartAt != null &&
      reasoningFinishedAt.isBefore(reasoningStartAt)) {
    changed = true;
    reasoningFinishedAt = null;
  }
  if (!changed) return message;

  // copyWith cannot clear fields to null, so rebuild explicitly.
  return ChatMessage(
    id: message.id,
    role: role,
    parts: message.parts,
    timestamp: message.timestamp,
    modelId: message.modelId,
    providerId: message.providerId,
    totalTokens: totalTokens,
    conversationId: message.conversationId,
    isStreaming: message.isStreaming,
    reasoningText: message.reasoningText,
    reasoningStartAt: reasoningStartAt,
    reasoningFinishedAt: reasoningFinishedAt,
    translation: message.translation,
    reasoningSegmentsJson: message.reasoningSegmentsJson,
    groupId: message.groupId,
    version: version,
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    cachedTokens: cachedTokens,
    durationMs: durationMs,
  );
}

/// Clamps legacy conversation counters so they satisfy the conversation_rows
/// CHECK constraints (truncateIndex >= -1, lastSummarizedMessageCount >= 0,
/// lastMemoryExtractedOrder >= -1). Returns the input unchanged (identical)
/// when nothing needed repair.
Conversation sanitizeLegacyConversationFields(Conversation conversation) {
  final truncateIndex = conversation.truncateIndex < -1
      ? -1
      : conversation.truncateIndex;
  final lastSummarizedMessageCount = conversation.lastSummarizedMessageCount < 0
      ? 0
      : conversation.lastSummarizedMessageCount;
  final lastMemoryExtractedOrder = conversation.lastMemoryExtractedOrder < -1
      ? -1
      : conversation.lastMemoryExtractedOrder;
  if (truncateIndex == conversation.truncateIndex &&
      lastSummarizedMessageCount == conversation.lastSummarizedMessageCount &&
      lastMemoryExtractedOrder == conversation.lastMemoryExtractedOrder) {
    return conversation;
  }
  return conversation.copyWith(
    truncateIndex: truncateIndex,
    lastSummarizedMessageCount: lastSummarizedMessageCount,
    lastMemoryExtractedOrder: lastMemoryExtractedOrder,
  );
}
