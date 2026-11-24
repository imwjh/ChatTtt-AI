import 'package:http/http.dart' as http;

http.Client createMcpOAuthDiscoveryHttpClient() => http.Client();

Future<void> validateMcpOAuthPublicUri(Uri uri) => Future<void>.value();
