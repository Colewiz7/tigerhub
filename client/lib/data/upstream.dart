/// The single outbound HTTP client.
///
/// Every upstream call goes through here. This is the only place that sets the
/// User-Agent, timeouts, and retry policy, so scraping etiquette (docs/notes.md 6)
/// is enforced by construction rather than by convention.
///
/// Ported from `backend/app/http.py`. The app used to scrape from a server; now
/// it scrapes from the device, so this file carries the obligation that used to
/// live in the backend. It matters more here, not less: there is one of these
/// per install rather than one in total.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Bumped with the app, so an upstream can tell versions apart in its logs.
const String appVersion = '0.1.0';

/// Honest, identifiable, with a way to reach a human. Required on every call.
const String contact = 'colewiz72@gmail.com';
const String userAgent = 'RITTimes/$appVersion (personal non-commercial campus '
    'info app; not affiliated with RIT; contact $contact)';

const Duration httpTimeout = Duration(seconds: 20);
const int httpMaxRetries = 3;

/// Retry only on transport errors and these transient statuses. A 404 or a 400
/// is a real answer, so retrying it just adds load upstream for no benefit.
const Set<int> retryStatuses = {429, 500, 502, 503, 504};

class UpstreamError implements Exception {
  UpstreamError(this.message);
  final String message;
  @override
  String toString() => 'UpstreamError: $message';
}

class Upstream {
  Upstream({http.Client? client, int? maxRetries})
      : _client = client ?? http.Client(),
        _maxRetries = maxRetries ?? httpMaxRetries;

  final http.Client _client;

  /// Overridable so tests do not sit through the real backoff. Production
  /// always uses [httpMaxRetries].
  final int _maxRetries;

  void close() => _client.close();

  /// One upstream request with retry and backoff. Throws [UpstreamError].
  Future<http.Response> request(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    Object? last;

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final request = http.Request(method, Uri.parse(url))
          ..followRedirects = true
          ..headers.addAll({'User-Agent': userAgent, ...?headers});
        if (body != null) request.body = body as String;

        final response = await http.Response.fromStream(
          await _client.send(request),
        ).timeout(httpTimeout);

        if (!retryStatuses.contains(response.statusCode)) {
          if (response.statusCode >= 400) {
            // A real answer, even if a bad one. Do not retry it.
            throw UpstreamError('${response.statusCode} from $url');
          }
          return response;
        }
        last = UpstreamError('${response.statusCode} from $url');
      } on UpstreamError {
        rethrow;
      } catch (error) {
        last = error;
      }

      if (attempt < _maxRetries - 1) {
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }

    throw UpstreamError(
      '$method $url failed after $_maxRetries attempts: $last',
    );
  }

  Future<dynamic> getJson(String url, {Map<String, String>? headers}) async =>
      jsonDecode((await request('GET', url, headers: headers)).body);

  Future<String> getText(String url, {Map<String, String>? headers}) async =>
      (await request('GET', url, headers: headers)).body;

  Future<dynamic> postJson(
    String url,
    Map<String, dynamic> payload, {
    Map<String, String>? headers,
  }) async {
    final response = await request(
      'POST',
      url,
      headers: {'Content-Type': 'application/json', ...?headers},
      body: jsonEncode(payload),
    );
    return jsonDecode(response.body);
  }
}
