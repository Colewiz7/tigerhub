/// Where the app's data comes from.
///
/// This is the seam that made going client side tractable. `ApiClient` used to
/// issue an HTTP GET against the FastAPI server; it now asks a [Backend] for a
/// path and gets the same JSON envelope back. Every model in `api_models.dart`
/// and every screen is untouched by the change, because the shape they parse is
/// the contract, not the transport.
///
/// Two implementations exist on purpose:
///
///   [LocalBackend]   scrapes RIT from the device. The default, and the reason
///                    the app no longer depends on a homelab being up.
///   [RemoteBackend]  talks to the old FastAPI server. Kept while the port is
///                    verified, so both can be run against the same paths and
///                    diffed for parity rather than the translation being
///                    assumed faithful.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

export 'local_backend.dart' show LocalBackend;

/// The JSON envelope every list endpoint returns, mirroring what the server
/// sent: `{data, stale, last_updated}`. Kept as the contract so the client's
/// staleness handling did not have to be rewritten alongside everything else.
abstract class Backend {
  /// Fetch one path. List shaped responses are wrapped as `{'items': [...]}`
  /// so both of `ApiClient`'s helpers see a single shape.
  Future<Map<String, dynamic>> fetch(String path, [Map<String, String>? query]);

  void close();
}

/// The original HTTP transport, pointed at a running FastAPI instance.
class RemoteBackend implements Backend {
  RemoteBackend({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 8);

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path')
          .replace(queryParameters: query == null || query.isEmpty ? null : query);

  @override
  Future<Map<String, dynamic>> fetch(
    String path, [
    Map<String, String>? query,
  ]) async {
    final uri = _uri(path, query);
    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', uri);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is List) return {'items': decoded};
    return decoded as Map<String, dynamic>;
  }

  @override
  void close() => _client.close();
}
