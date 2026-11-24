import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../logger.dart';
import '../models/models.dart';
import 'event_source_stub.dart' as stub;
import 'sse_parser.dart';

final Logger _logger = Logger('mcp_client.event_source_io');

/// Native platform EventSource implementation using HttpClient
class EventSource implements stub.EventSource {
  HttpClient? _client;
  HttpClientRequest? _request;
  HttpClientResponse? _response;
  StreamSubscription? _subscription;
  final SseParser _parser = SseParser();
  bool _isConnected = false;

  EventSource();

  @override
  bool get isConnected => _isConnected;

  @override
  HttpClientResponse? get response => _response;

  @override
  Future<void> connect(
    String url, {
    Map<String, String>? headers,
    Function(String?)? onOpen,
    Function(dynamic)? onMessage,
    Function(dynamic)? onError,
    Function(String?)? onEndpoint,
    Function(SseEvent)? onEvent,
    Function()? onDone,
  }) async {
    _logger.debug('EventSource connecting');
    if (_isConnected) {
      throw McpError('EventSource is already connected');
    }

    try {
      // Initialize connection
      _client = HttpClient();
      _request = await _client!.getUrl(Uri.parse(url));

      // Set up MCP standard SSE headers
      _request!.headers.set('Accept', 'text/event-stream');
      _request!.headers.set('Cache-Control', 'no-cache');
      _request!.headers.set(
        'Accept-Encoding',
        'identity',
      ); // Disable compression
      if (headers != null) {
        headers.forEach((key, value) {
          _request!.headers.set(key, value);
        });
      }

      _response = await _request!.close();

      if (_response!.statusCode != 200) {
        final body = await _response!.transform(utf8.decoder).join();
        throw McpHttpError(
          statusCode: _response!.statusCode,
          message:
              'Failed to connect to SSE endpoint: '
              '${_response!.statusCode} - $body',
          retryAfter: McpHttpError.parseRetryAfter(
            _response!.headers.value('Retry-After'),
          ),
          body: body,
          wwwAuthenticate: _response!.headers['WWW-Authenticate'] ?? const [],
          isBackgroundRequest: true,
        );
      }

      _isConnected = true;
      _logger.debug('EventSource connection established');

      // Set up subscription to process events with proper UTF-8 handling
      final decodedResponse = _response!.transform(utf8.decoder);
      _subscription = decodedResponse.listen(
        (String chunk) {
          try {
            // Log raw data for debugging
            _logger.debug('Raw SSE data: [$chunk]');
            _dispatchEvents(
              _parser.add(chunk),
              onOpen: onOpen,
              onMessage: onMessage,
              onError: onError,
              onEndpoint: onEndpoint,
              onEvent: onEvent,
            );
          } catch (e) {
            _logger.error('Error processing SSE data: $e');
            if (onError != null) {
              onError(e);
            }
          }
        },
        onError: (error) {
          _logger.error('EventSource stream error: $error');
          _isConnected = false;
          if (onError != null) {
            onError(error);
          }
        },
        onDone: () {
          _logger.debug('EventSource stream closed');
          _isConnected = false;
          _dispatchEvents(
            _parser.close(),
            onOpen: onOpen,
            onMessage: onMessage,
            onError: onError,
            onEndpoint: onEndpoint,
            onEvent: onEvent,
          );
          onDone?.call();
        },
      );
    } catch (e) {
      _logger.error('Failed to connect EventSource: $e');
      _isConnected = false;
      if (onError != null) {
        onError(e);
      }
      rethrow;
    }
  }

  void _dispatchEvents(
    List<SseEvent> events, {
    required Function(String?)? onOpen,
    required Function(dynamic)? onMessage,
    required Function(dynamic)? onError,
    required Function(String?)? onEndpoint,
    required Function(SseEvent)? onEvent,
  }) {
    for (final event in events) {
      onEvent?.call(event);
      final data = event.data;
      if (event.event == 'endpoint' && data != null) {
        onEndpoint?.call(data);
      } else if (event.event == 'open') {
        onOpen?.call(data);
      } else if (event.event == 'error' && data != null) {
        onError?.call(data);
      } else if (data != null) {
        if (event.event == null &&
            (data.startsWith('http://') || data.startsWith('https://'))) {
          onEndpoint?.call(data);
          continue;
        }
        try {
          onMessage?.call(jsonDecode(data));
        } catch (_) {
          onMessage?.call(data);
        }
      }
    }
  }

  @override
  void close() {
    _logger.debug('Closing EventSource');
    _isConnected = false;
    _subscription?.cancel();
    _client?.close(force: true);
  }
}
