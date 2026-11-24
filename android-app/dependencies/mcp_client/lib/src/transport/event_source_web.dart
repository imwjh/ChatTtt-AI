import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../logger.dart';
import '../models/models.dart';
import 'event_source_stub.dart' as stub;
import 'sse_parser.dart';

final Logger _logger = Logger('mcp_client.event_source_web');

/// Web platform EventSource implementation using package:http
class EventSource implements stub.EventSource {
  http.Client? _client;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  http.StreamedResponse? _response;
  final SseParser _parser = SseParser();

  EventSource();

  @override
  bool get isConnected => _isConnected;

  @override
  dynamic get response => _response;

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
    _logger.debug('EventSource connecting (web)');
    if (_isConnected) {
      throw McpError('EventSource is already connected');
    }

    try {
      // Create headers map with SSE-specific headers
      final sseHeaders = <String, String>{
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        ...?headers,
      };

      // Create HTTP client
      _client = http.Client();

      // Create streaming request
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(sseHeaders);

      // Send request and get streamed response
      _response = await _client!.send(request);

      if (_response!.statusCode != 200) {
        final body = await _response!.stream.transform(utf8.decoder).join();
        throw McpHttpError(
          statusCode: _response!.statusCode,
          message:
              'Failed to connect to SSE endpoint: '
              '${_response!.statusCode} - $body',
          retryAfter: McpHttpError.parseRetryAfter(
            _response!.headers['retry-after'],
          ),
          body: body,
          wwwAuthenticate:
              _response!.headers['www-authenticate'] == null
                  ? const []
                  : [_response!.headers['www-authenticate']!],
          isBackgroundRequest: true,
        );
      }

      _isConnected = true;
      _logger.debug('EventSource connection established (web)');
      if (onOpen != null) {
        onOpen(null);
      }

      // Listen to the stream
      _subscription = _response!.stream
          .transform(utf8.decoder)
          .listen(
            (String chunk) {
              try {
                _logger.debug('Received SSE chunk: $chunk');
                _dispatchEvents(
                  _parser.add(chunk),
                  onOpen: onOpen,
                  onMessage: onMessage,
                  onError: onError,
                  onEndpoint: onEndpoint,
                  onEvent: onEvent,
                );
              } catch (e) {
                _logger.error('Error processing SSE chunk: $e');
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
    _logger.debug('Closing EventSource (web)');
    _isConnected = false;
    _subscription?.cancel();
    _client?.close();
  }
}
