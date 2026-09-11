import 'dart:convert';

import 'package:http/http.dart' as http;

import 'taxonomy.dart';

/// Auth failure from `GET /v1/usage` — taxonomy body only, no usage payload.
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

/// Successful usage-summary fetch (G3 wire).
class UsageSummaryFetchResult {
  const UsageSummaryFetchResult({
    required this.creditsUsed,
    required this.creditBudget,
    required this.period,
  });

  final int creditsUsed;
  final int creditBudget;
  final String period;
}

/// `GET /v1/usage` client — occasional Bearer AAT read (G3).
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
      Uri.parse('$base/v1/usage'),
      headers: <String, String>{
        'authorization': 'Bearer $aat',
        'accept': 'application/json',
      },
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Usage summary body is not an object');
      }
      final current = decoded['current_period'];
      if (current is! Map<String, dynamic>) {
        throw const FormatException('Usage summary missing current_period');
      }
      final creditsUsed = current['credits_used'];
      final creditBudget = current['credit_budget'];
      final period = current['period'];
      if (creditsUsed is! num || creditBudget is! num || period is! String) {
        throw const FormatException('Usage summary current_period fields invalid');
      }
      return UsageSummaryFetchResult(
        creditsUsed: creditsUsed.toInt(),
        creditBudget: creditBudget.toInt(),
        period: period,
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
