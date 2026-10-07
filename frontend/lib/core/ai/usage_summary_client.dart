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
class UsageSummaryFetchResult {
  const UsageSummaryFetchResult({
    required this.creditsUsed,
    required this.creditBudget,
    this.subscriptionRef,
    this.planDisplayName,
  });

  final int creditsUsed;
  final int creditBudget;
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
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Coverage body is not an object');
      }
      final subscriptionRef = decoded['subscription_ref']?.toString();
      final term = decoded['term'];
      if (term is! Map<String, dynamic>) {
        throw const FormatException('Coverage missing term');
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
