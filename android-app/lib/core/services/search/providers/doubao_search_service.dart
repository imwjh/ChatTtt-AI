import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';

class DoubaoSearchService extends SearchService<DoubaoOptions> {
  DoubaoSearchService({super.client});

  static const String endpoint =
      'https://open.feedcoopapi.com/search_api/web_search';

  @override
  String get name => 'Doubao';

  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(
      l10n.searchProviderDoubaoDescription,
      style: const TextStyle(fontSize: 12),
    );
  }

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required DoubaoOptions serviceOptions,
  }) async {
    try {
      final apiKey = serviceOptions
          .effectiveApiKey(serviceOptions.apiKey)
          .trim();
      if (apiKey.isEmpty) {
        throw Exception('Doubao API key is required');
      }

      final count = commonOptions.resultSize.clamp(1, 50);
      final response = await withHttpClient(
        (client) => client
            .post(
              Uri.parse(endpoint),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json; charset=utf-8',
              },
              body: jsonEncode({
                'Query': query,
                'SearchType': 'web',
                'Count': count,
                'Filter': {'NeedUrl': true},
              }),
            )
            .timeout(Duration(milliseconds: commonOptions.timeout)),
      );

      if (response.statusCode != 200) {
        throw Exception('API request failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final metadata = data['ResponseMetadata'];
      final error = metadata is Map ? metadata['Error'] : null;
      if (error is Map) {
        throw Exception(error['Message'] ?? error['Code'] ?? 'API error');
      }

      final result = data['Result'];
      if (result is! Map) {
        throw Exception('API response missing Result');
      }
      final webResults = (result['WebResults'] as List?) ?? const <dynamic>[];
      final items = <SearchResultItem>[];
      for (final item in webResults) {
        if (item is! Map) continue;
        final url = (item['Url'] ?? '').toString().trim();
        if (url.isEmpty) continue;
        final summary = (item['Summary'] ?? '').toString();
        final content = (item['Content'] ?? '').toString();
        items.add(
          SearchResultItem(
            title: (item['Title'] ?? '').toString(),
            url: url,
            text: summary.trim().isNotEmpty
                ? summary
                : content.trim().isNotEmpty
                ? content
                : (item['Snippet'] ?? '').toString(),
          ),
        );
      }

      return SearchResult(items: items);
    } catch (e) {
      throw Exception('Doubao search failed: $e');
    }
  }
}
