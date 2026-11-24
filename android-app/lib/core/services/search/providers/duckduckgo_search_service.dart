import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;

import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';

class DuckDuckGoSearchService extends SearchService<DuckDuckGoOptions> {
  DuckDuckGoSearchService({super.client});

  @override
  String get name => 'DuckDuckGo';

  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(
      l10n.searchProviderDuckDuckGoDescription,
      style: const TextStyle(fontSize: 12),
    );
  }

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required DuckDuckGoOptions serviceOptions,
  }) async {
    final region = serviceOptions.region.trim().isNotEmpty
        ? serviceOptions.region.trim()
        : 'us-en';

    try {
      final uri = Uri.https('duckduckgo.com', '/html/', {
        'q': query,
        'kl': region,
      });
      final response = await withHttpClient(
        (client) => client
            .get(
              uri,
              headers: const {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36',
              },
            )
            .timeout(Duration(milliseconds: commonOptions.timeout)),
      );
      if (response.statusCode != 200) {
        throw Exception('API request failed: ${response.statusCode}');
      }

      final document = parser.parse(response.body);
      final items = <SearchResultItem>[];
      for (final result
          in document
              .querySelectorAll('.result')
              .take(commonOptions.resultSize)) {
        final titleElement = result.querySelector('.result__a');
        final urlElement = result.querySelector('.result__url');
        final snippetElement = result.querySelector('.result__snippet');
        final title = titleElement?.text.trim() ?? '';
        final rawUrl =
            titleElement?.attributes['href']?.trim() ??
            urlElement?.text.trim() ??
            '';
        final url = _resolveResultUrl(rawUrl);
        final snippet = snippetElement?.text.trim() ?? '';
        if (title.isEmpty && url.isEmpty && snippet.isEmpty) continue;
        items.add(SearchResultItem(title: title, url: url, text: snippet));
      }

      return SearchResult(items: items);
    } catch (e) {
      throw Exception('DuckDuckGo search failed: $e');
    }
  }

  static String _resolveResultUrl(String raw) {
    if (raw.isEmpty) return raw;
    final normalized = raw.startsWith('//') ? 'https:$raw' : raw;
    final uri = Uri.tryParse(normalized);
    return uri?.queryParameters['uddg'] ?? normalized;
  }
}
