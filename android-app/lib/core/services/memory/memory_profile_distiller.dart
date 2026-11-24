import 'dart:convert';

import '../../database/chat_database_repository.dart';
import '../../models/memory_entry.dart';
import '../../models/user_profile_field.dart';
import 'memory_block_builder.dart';
import 'memory_prompts.dart';
import 'memory_repository.dart';
import 'memory_trace.dart';

/// One distilled profile field from Distiller JSON (§12.7).
class MemoryDistilledField {
  const MemoryDistilledField({required this.key, required this.value});

  final String key;
  final String value;
}

/// Distiller parse outcome. [ok] false means unparseable JSON.
class MemoryDistillParseResult {
  const MemoryDistillParseResult._({required this.ok, required this.fields});

  factory MemoryDistillParseResult.ok(List<MemoryDistilledField> fields) =>
      MemoryDistillParseResult._(ok: true, fields: fields);

  factory MemoryDistillParseResult.malformed() =>
      const MemoryDistillParseResult._(
        ok: false,
        fields: <MemoryDistilledField>[],
      );

  final bool ok;
  final List<MemoryDistilledField> fields;
}

/// Profile Distiller (§12.7).
class MemoryProfileDistiller {
  MemoryProfileDistiller({
    required this.repository,
    required this.chatRepository,
  });

  final MemoryRepository repository;
  final ChatDatabaseRepository chatRepository;

  static String resolveTemplate({
    required MemoryPromptLang lang,
    String? overrideZh,
    String? overrideEn,
  }) {
    if (lang == MemoryPromptLang.zh) {
      final o = overrideZh?.trim();
      if (o != null && o.isNotEmpty) return o;
      return MemoryPrompts.profileDistillZh;
    }
    final o = overrideEn?.trim();
    if (o != null && o.isNotEmpty) return o;
    return MemoryPrompts.profileDistillEn;
  }

  static String buildPrompt({
    required MemoryPromptLang lang,
    required String profileBlock,
    required String identityEntries,
    String? overrideZh,
    String? overrideEn,
  }) {
    return resolveTemplate(
          lang: lang,
          overrideZh: overrideZh,
          overrideEn: overrideEn,
        )
        .replaceAll('{{profileBlock}}', profileBlock)
        .replaceAll('{{identityEntries}}', identityEntries);
  }

  /// Format identity memories for `{{identityEntries}}`.
  static String formatIdentityEntries(List<MemoryEntry> entries) {
    if (entries.isEmpty) return '';
    final buf = StringBuffer();
    for (final e in entries) {
      buf.writeln('${e.id} ${e.content}');
    }
    return buf.toString().trimRight();
  }

  /// Extract a JSON object from model output (prose / fences tolerated).
  static Object? extractJsonObject(String response) {
    var text = response.trim();
    final fence = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(text);
    if (fence != null) {
      text = fence.group(1)!.trim();
    }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      return jsonDecode(text.substring(start, end + 1));
    } catch (_) {
      return null;
    }
  }

  static MemoryDistillParseResult parse(String response) {
    final decoded = extractJsonObject(response);
    if (decoded is! Map) return MemoryDistillParseResult.malformed();
    final rawFields = decoded['fields'];
    if (rawFields is! List) return MemoryDistillParseResult.malformed();

    final fields = <MemoryDistilledField>[];
    for (final item in rawFields) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final key = (map['key'] ?? '').toString().trim();
      final value = (map['value'] ?? '').toString().trim();
      if (key.isEmpty || value.isEmpty) continue;
      if (!UserProfileField.isValidKey(key)) continue;
      // Distiller never clears (§12.7); empty already skipped.
      fields.add(MemoryDistilledField(key: key, value: value));
    }
    return MemoryDistillParseResult.ok(fields);
  }

  /// Run Distiller after identity NEW/MERGE/CONFLICT. Returns false on LLM/parse
  /// failure (caller still advances watermark per §12.8).
  Future<bool> run({
    required MemoryPromptLang lang,
    required String? assistantId,
    required Future<String> Function(String prompt) llmCall,
    String? overrideZh,
    String? overrideEn,
    MemoryTraceStep? traceStep,
  }) async {
    final identity = await chatRepository.queryVisibleMemories(
      assistantId: assistantId,
      type: MemoryType.identity,
    );
    if (identity.isEmpty) {
      traceStep?.parsedResult = 'no_identity_entries';
      return true;
    }

    final profile = await chatRepository.readProfileFields();
    final profileBlock = MemoryBlockBuilder.buildProfileBlock(
      fields: profile,
      lang: lang,
    );
    final prompt = buildPrompt(
      lang: lang,
      profileBlock: profileBlock,
      identityEntries: formatIdentityEntries(identity),
      overrideZh: overrideZh,
      overrideEn: overrideEn,
    );

    traceStep?.appendPrompt(prompt);
    final String raw;
    try {
      raw = await llmCall(prompt);
    } catch (e) {
      traceStep?.appendResponse('<request failed> $e');
      return false;
    }
    traceStep?.appendResponse(raw);

    final parsed = parse(raw);
    if (!parsed.ok) {
      traceStep?.parsedResult = 'malformed';
      return false;
    }
    traceStep?.setParsedJson({
      'fields': [
        for (final f in parsed.fields) {'key': f.key, 'value': f.value},
      ],
    });

    for (final field in parsed.fields) {
      try {
        String? before;
        for (final existing in profile) {
          if (existing.key == field.key) {
            before = existing.value;
            break;
          }
        }
        await repository.putProfileField(
          field.key,
          field.value,
          MemorySource.distilled,
        );
        traceStep?.addMutation(
          MemoryTraceMutation(
            kind: MemoryTraceMutationKind.profileFieldWritten,
            targetId: field.key,
            before: before,
            after: field.value,
          ),
        );
      } catch (_) {
        // Illegal keys already filtered; ignore write races.
      }
    }
    return true;
  }
}
