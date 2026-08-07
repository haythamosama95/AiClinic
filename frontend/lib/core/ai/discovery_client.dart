import 'dart:convert';

import 'package:http/http.dart' as http;

import 'taxonomy.dart';

/// Auth failure from `GET /v1/capabilities` — taxonomy body only, no manifests payload.
class DiscoveryAuthFailure implements Exception {
  const DiscoveryAuthFailure({
    required this.code,
    required this.responseBody,
  });

  final TaxonomyCode code;
  final Map<String, Object?> responseBody;

  @override
  String toString() => 'DiscoveryAuthFailure(code: $code)';
}

/// Successful discovery fetch (I2 wire).
class DiscoveryFetchResult {
  const DiscoveryFetchResult({
    required this.manifests,
    required this.etag,
    required this.notModified,
  });

  final List<Map<String, Object?>> manifests;
  final String? etag;
  final bool notModified;
}

/// `GET /v1/capabilities` client per I2 discovery-http contract.
class DiscoveryClient {
  DiscoveryClient({http.Client? httpClient}) : _client = httpClient ?? http.Client();

  final http.Client _client;
  String? _cachedEtag;

  /// Bearer AAT discovery with optional `If-None-Match` revalidation.
  Future<DiscoveryFetchResult> fetchCapabilities({
    required String platformBaseUrl,
    required String aat,
    String? ifNoneMatch,
  }) async {
    final base = platformBaseUrl.endsWith('/')
        ? platformBaseUrl.substring(0, platformBaseUrl.length - 1)
        : platformBaseUrl;
    final headers = <String, String>{
      'authorization': 'Bearer $aat',
      'accept': 'application/json',
    };
    final etag = ifNoneMatch ?? _cachedEtag;
    if (etag != null && etag.isNotEmpty) {
      headers['if-none-match'] = etag;
    }

    final response = await _client.get(Uri.parse('$base/v1/capabilities'), headers: headers);
    if (response.statusCode == 304) {
      return DiscoveryFetchResult(manifests: const [], etag: etag, notModified: true);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Discovery body is not an object');
      }
      final manifestsRaw = decoded['manifests'];
      final manifests = manifestsRaw is List
          ? manifestsRaw
              .map((entry) => Map<String, Object?>.from(entry as Map))
              .toList(growable: false)
          : <Map<String, Object?>>[];
      final responseEtag = response.headers['etag'];
      _cachedEtag = responseEtag;
      return DiscoveryFetchResult(manifests: manifests, etag: responseEtag, notModified: false);
    }

    throw _mapAuthFailure(response);
  }

  DiscoveryAuthFailure _mapAuthFailure(http.Response response) {
    Map<String, Object?> body = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        body = Map<String, Object?>.from(decoded);
      } else if (decoded is Map) {
        body = Map<String, Object?>.from(decoded);
      }
    } on FormatException {
      body = {};
    }
    final code = classifyTaxonomyCode(body['code']?.toString() ?? 'unauthenticated');
    return DiscoveryAuthFailure(code: code, responseBody: body);
  }
}

/// Extract required context keys for [capabilityId] from discovery manifests.
List<String> requiredContextKeysFromManifests(
  List<Map<String, Object?>> manifests,
  String capabilityId,
) {
  for (final manifest in manifests) {
    final identity = manifest['Identity'];
    if (identity is Map) {
      final id = identity['capabilityId'] ?? identity['capability_id'];
      if (id == capabilityId) {
        final requirements = manifest['Context requirements'] ?? manifest['context_requirements'];
        if (requirements is List) {
          final keys = <String>[];
          for (final entry in requirements) {
            if (entry is Map) {
              final key = entry['key'];
              if (key is String && entry['required'] != false) {
                keys.add(key);
              }
            }
          }
          if (keys.isNotEmpty) {
            return keys;
          }
        }
      }
    }
  }
  return const [];
}
