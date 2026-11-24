import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../providers/settings_provider.dart';

/// Kimi Formula official tools helper (web-search).
/// Flow: GET tools → chat function call → POST fibers → tool result.
class KimiFormulaSearch {
  static const String defaultFormulaUri = 'moonshot/web-search:latest';

  static Uri _baseUri(ProviderConfig config) {
    final raw = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;
    return Uri.parse(raw);
  }

  static Future<List<Map<String, dynamic>>> fetchTools({
    required http.Client client,
    required ProviderConfig config,
    String formulaUri = defaultFormulaUri,
  }) async {
    final base = _baseUri(config);
    final uri = base.replace(path: '${base.path}/formulas/$formulaUri/tools');
    final resp = await client.get(
      uri,
      headers: {
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type': 'application/json',
      },
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        'Kimi Formula tools failed: ${resp.statusCode} ${resp.body}',
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final tools = (data['tools'] as List?) ?? const <dynamic>[];
    return tools
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
  }

  static Future<String> executeFiber({
    required http.Client client,
    required ProviderConfig config,
    required String name,
    required String arguments,
    String formulaUri = defaultFormulaUri,
  }) async {
    final base = _baseUri(config);
    final uri = base.replace(path: '${base.path}/formulas/$formulaUri/fibers');
    final resp = await client.post(
      uri,
      headers: {
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'name': name, 'arguments': arguments}),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        'Kimi Formula fiber failed: ${resp.statusCode} ${resp.body}',
      );
    }
    final fiber = jsonDecode(resp.body) as Map<String, dynamic>;
    final context =
        (fiber['context'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final status = (fiber['status'] ?? '').toString();
    if (status == 'succeeded') {
      final output = context['output'] ?? context['encrypted_output'] ?? '';
      if (output is String) return output;
      return jsonEncode(output);
    }
    final error = fiber['error'] ?? context['error'] ?? 'Unknown tool error';
    if (error is String) return error;
    return jsonEncode(error);
  }

  /// Inserts Formula tool decls that do not collide with existing tool names.
  ///
  /// Returns the names that were actually inserted after duplicate resolution.
  /// Call sites must dispatch fibers only for these exact names.
  static Set<String> mergeTools(
    Map<String, dynamic> body,
    List<Map<String, dynamic>> formulaTools,
  ) {
    if (formulaTools.isEmpty) return const <String>{};
    final tools = <Map<String, dynamic>>[];
    final existing = body['tools'];
    if (existing is List) {
      for (final t in existing) {
        if (t is Map) tools.add(t.cast<String, dynamic>());
      }
    }
    final existingNames = <String>{
      for (final t in tools)
        if (t['function'] is Map)
          ((t['function'] as Map)['name'] ?? '').toString().trim(),
    };
    final inserted = <String>{};
    for (final t in formulaTools) {
      final fn = t['function'];
      final name = fn is Map ? (fn['name'] ?? '').toString().trim() : '';
      if (name.isEmpty || existingNames.contains(name)) continue;
      tools.add(t);
      existingNames.add(name);
      inserted.add(name);
    }
    if (tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] ??= 'auto';
    }
    return inserted;
  }
}
