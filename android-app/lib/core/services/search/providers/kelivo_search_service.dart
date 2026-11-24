import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../search_service.dart';

class KelivoSearchService extends SearchService<KelivoOptions> {
  KelivoSearchService({super.client});

  static const _mask = 'kelivo';
  static const _payload = <int>[
    13,
    9,
    13,
    14,
    13,
    4,
    88,
    9,
    5,
    31,
    70,
    48,
    52,
    80,
    95,
    8,
    4,
    12,
    3,
    58,
    51,
    15,
    4,
    92,
    88,
    24,
  ];

  static String get _token {
    final mask = _mask.codeUnits;
    return String.fromCharCodes([
      for (var i = 0; i < _payload.length; i++)
        _payload[i] ^ mask[i % mask.length],
    ]);
  }

  @override
  String get name => 'Kelivo';

  @override
  Widget description(BuildContext context) => const SizedBox.shrink();

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required KelivoOptions serviceOptions,
  }) async {
    final ownsClient = client == null;
    // Keep this off DioHttpClient so the built-in token is not written to request logs.
    final httpClient = client ?? http.Client();
    try {
      final language = _languageQueryValue(PlatformDispatcher.instance.locale);
      final uri = Uri.https('search.psycheas.top', '/v1/search', {
        'q': query,
        'count': '${commonOptions.resultSize}',
        if (language != null) 'language': language,
      });
      final response = await httpClient
          .get(uri, headers: {'Authorization': 'Bearer $_token'})
          .timeout(Duration(milliseconds: commonOptions.timeout));
      if (response.statusCode != 200) {
        throw Exception('API request failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final results = (data['results'] as List? ?? const []).map((item) {
        return SearchResultItem(
          title: item['title'] ?? '',
          url: item['url'] ?? '',
          text: item['content'] ?? '',
        );
      }).toList();

      return SearchResult(items: results);
    } catch (e) {
      throw Exception('Kelivo search failed: $e');
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  static String? _languageQueryValue(Locale locale) {
    final language = locale.languageCode.trim();
    if (language.isEmpty) return null;
    final country = locale.countryCode?.trim();
    if (country != null && country.isNotEmpty) {
      return '$language-$country';
    }
    if (language == 'zh') return 'zh-CN';
    if (language == 'en') return 'en-US';
    return language;
  }
}
