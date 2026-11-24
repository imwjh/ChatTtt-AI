import 'package:http/http.dart' as http;

import 'mcp_oauth_http_client_stub.dart'
    if (dart.library.io) 'mcp_oauth_http_client_io.dart'
    as implementation;

http.Client createMcpOAuthDiscoveryHttpClient() =>
    implementation.createMcpOAuthDiscoveryHttpClient();

Future<void> validateMcpOAuthPublicUri(Uri uri) =>
    implementation.validateMcpOAuthPublicUri(uri);
