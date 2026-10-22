import 'dart:convert';

import 'package:ai_clinic/core/contract_versions.dart';
import 'package:http/http.dart' as http;

import 'taxonomy.dart';

/// Auth failure from `GET /v1/coverage` — taxonomy body only, no coverage payload.
class UsageSummaryAuthFailure implements Exception {
  const UsageSummaryAuthFailure({
    required this.code,
    required this.responseBody,
  });

  final TaxonomyCode code;
  final Map<String, Object?> responseBody;

  @override
  String toString() => 'UsageSummaryAuthFailure(code: $code)';
}

/// Successful coverage fetch (04 §4.2 wire).
///
/// `creditsUsed` and `creditBudget` are null when the valid snapshot has no current term;
/// the subscription reference is preserved in that case so the host can still show it.
class UsageSummaryFetchResult {
  const UsageSummaryFetchResult({
    this.creditsUsed,
    this.creditBudget,
    this.subscriptionRef,
    this.planDisplayName,
  });

  final int? creditsUsed;
  final int? creditBudget;
  final String? subscriptionRef;
  final String? planDisplayName;
}

/// `GET /v1/coverage` client — occasional Bearer AAT read (administrator only).
class UsageSummaryClient {
  UsageSummaryClient({http.Client? httpClient}) : _client = httpClient ?? http.Client();

  final http.Client _client;

  Future<UsageSummaryFetchResult> fetchUsage({
    required String platformBaseUrl,
    required String aat,
  }) async {
    final base = platformBaseUrl.endsWith('/')
        ? platformBaseUrl.substring(0, platformBaseUrl.length - 1)
        : platformBaseUrl;

    final response = await _client.get(
      Uri.parse('$base/v1/coverage'),
      headers: <String, String>{
        'authorization': 'Bearer $aat',
        'accept': 'application/json',
        'Aip-Contract-Version': '$platformClinic',
      },
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Seam: R2-C3 response-version guard (RM37, blocked)
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Coverage body is not an object');
      }
      final subscriptionRef = decoded['subscription_ref']?.toString();
      // Producer wire: `{subscription_ref, snapshot: {term, ...}, queued_terms, recent_terms}`.
      final snapshot = decoded['snapshot'];
      if (snapshot is! Map<String, dynamic>) {
        throw const FormatException('Coverage snapshot missing or not an object');
      }
      final term = snapshot['term'];
      if (term == null) {
        // Valid snapshot with no current term: keep the reference, no commercial figures.
        return UsageSummaryFetchResult(subscriptionRef: subscriptionRef);
      }
      if (term is! Map<String, dynamic>) {
        throw const FormatException('Coverage snapshot.term is not an object');
      }
      final creditsUsed = term['used'];
      final creditBudget = term['allowance'];
      final planDisplayName = term['plan_display_name']?.toString();
      if (creditsUsed is! num || creditBudget is! num) {
        throw const FormatException('Coverage term.used or term.allowance invalid');
      }
      return UsageSummaryFetchResult(
        creditsUsed: creditsUsed.toInt(),
        creditBudget: creditBudget.toInt(),
        subscriptionRef: subscriptionRef,
        planDisplayName: planDisplayName,
      );
    }

    throw _mapAuthFailure(response);
  }

  UsageSummaryAuthFailure _mapAuthFailure(http.Response response) {
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
    return UsageSummaryAuthFailure(code: code, responseBody: body);
  }
}
