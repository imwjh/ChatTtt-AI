import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';

class StepFunSearchService extends SearchService<StepFunOptions> {
  StepFunSearchService({super.client});

  @override
  String get name => 'StepFun';

  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(
      l10n.searchProviderStepFunDescription,
      style: const TextStyle(fontSize: 12),
    );
  }

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required StepFunOptions serviceOptions,
  }) async {
    try {
      final apiKey = serviceOptions
          .effectiveApiKey(serviceOptions.apiKey)
          .trim();
      if (apiKey.isEmpty) {
        throw Exception('StepFun API key is required');
      }

      final body = <String, dynamic>{
        'query': query,
        'n': commonOptions.resultSize.clamp(1, 20),
        if (serviceOptions.category.trim().isNotEmpty)
          'category': serviceOptions.category.trim(),
      };

      final response = await withHttpClient(
        (client) => client
            .post(
              Uri.parse(serviceOptions.resolvedUrl),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json; charset=utf-8',
              },
              body: jsonEncode(body),
            )
            .timeout(Duration(milliseconds: commonOptions.timeout)),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'API request failed: ${response.statusCode} ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (data['results'] as List?) ?? const <dynamic>[];
      final items = results.take(commonOptions.resultSize).map((item) {
        final m = (item as Map).cast<String, dynamic>();
        final snippet = (m['snippet'] ?? m['content'] ?? '').toString();
        return SearchResultItem(
          title: (m['title'] ?? '').toString(),
          url: (m['url'] ?? '').toString(),
          text: snippet,
        );
      }).toList();

      return SearchResult(items: items);
    } catch (e) {
      throw Exception('StepFun search failed: $e');
    }
  }
}
