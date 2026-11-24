import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

import '../network/dio_http_client.dart';
import 'search_service.dart';

class SearchServiceUsageException implements Exception {
  const SearchServiceUsageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SearchServiceUsageInfo {
  const SearchServiceUsageInfo({
    required this.remaining,
    this.used,
    this.limit,
  });

  final num remaining;
  final num? used;
  final num? limit;
}

class SearchServiceUsageService {
  const SearchServiceUsageService._();

  static bool supports(SearchServiceOptions options) =>
      options is TavilyOptions || options is LinkUpOptions;

  static Future<SearchServiceUsageInfo> fetch(
    SearchServiceOptions options, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final ownsClient = client == null;
    final baseClient = client ?? DioHttpClient(timeout: timeout);
    final effectiveClient = RetryClient.withDelays(
      baseClient,
      const <Duration>[
        Duration(milliseconds: 200),
        Duration(milliseconds: 600),
      ],
      when: (_) => false,
      whenError: _shouldRetryUsageRequest,
    );
    try {
      if (options is TavilyOptions) {
        return await _fetchTavily(options, effectiveClient);
      }
      if (options is LinkUpOptions) {
        return await _fetchLinkUp(options, effectiveClient);
      }
      throw const SearchServiceUsageException(
        'Usage query is not supported for this search provider',
      );
    } on SearchServiceUsageException {
      rethrow;
    } on FormatException {
      throw const SearchServiceUsageException(
        'The provider returned an invalid usage response',
      );
    } catch (error) {
      throw SearchServiceUsageException(error.toString());
    } finally {
      if (ownsClient) effectiveClient.close();
    }
  }

  static Future<SearchServiceUsageInfo> _fetchTavily(
    TavilyOptions options,
    http.Client client,
  ) async {
    final response = await client.get(
      _tavilyUsageUri(options),
      headers: {'Authorization': 'Bearer ${options.apiKey.trim()}'},
    );
    _ensureSuccess(response);

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected an object');
    }
    final account = decoded['account'];
    num? used;
    num? limit;

    if (account is Map &&
        account['plan_usage'] is num &&
        account['plan_limit'] is num) {
      used = account['plan_usage'] as num;
      limit = account['plan_limit'] as num;
    } else {
      final key = decoded['key'];
      if (key is Map && key['usage'] is num && key['limit'] is num) {
        used = key['usage'] as num;
        limit = key['limit'] as num;
      }
    }
    if (used == null || limit == null) {
      throw const FormatException('Missing usage totals');
    }
    final remaining = limit - used;
    return SearchServiceUsageInfo(
      remaining: remaining < 0 ? 0 : remaining,
      used: used,
      limit: limit,
    );
  }

  static Future<SearchServiceUsageInfo> _fetchLinkUp(
    LinkUpOptions options,
    http.Client client,
  ) async {
    final response = await client.get(
      Uri.parse('https://api.linkup.so/v1/credits/balance'),
      headers: {'Authorization': 'Bearer ${options.apiKey.trim()}'},
    );
    _ensureSuccess(response);

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['balance'] is! num) {
      throw const FormatException('Missing credit balance');
    }
    return SearchServiceUsageInfo(remaining: decoded['balance'] as num);
  }

  static Uri _tavilyUsageUri(TavilyOptions options) {
    final searchUri = Uri.parse(options.resolvedUrl);
    final segments = searchUri.pathSegments.where((e) => e.isNotEmpty).toList();
    if (segments.isEmpty) {
      segments.add('usage');
    } else if (segments.last == 'search') {
      segments[segments.length - 1] = 'usage';
    } else {
      segments.add('usage');
    }
    return Uri(
      scheme: searchUri.scheme,
      userInfo: searchUri.userInfo,
      host: searchUri.host,
      port: searchUri.hasPort ? searchUri.port : null,
      path: '/${segments.join('/')}',
    );
  }

  static void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SearchServiceUsageException(
        'Usage request failed (HTTP ${response.statusCode})',
      );
    }
  }

  static bool _shouldRetryUsageRequest(Object error, StackTrace _) {
    if (error is TimeoutException) return true;
    if (error is! http.ClientException) return false;
    final message = error.toString().toLowerCase();
    return message.contains('handshakeexception') ||
        message.contains('connection terminated during handshake') ||
        message.contains('connection timeout') ||
        message.contains('connection error') ||
        message.contains('socketexception') ||
        message.contains('connection reset by peer');
  }
}
