import 'dart:convert';
import 'dart:io';

import 'package:ai_clinic/core/contract_versions.dart';
import 'package:meta/meta.dart';
import 'package:ai_clinic/features/ai/billing/billing_token_client.dart';
import 'package:http/http.dart' as http;

const _contractVersionOverrideKey = 'ABO_CONTRACT_VERSION_OVERRIDE';
const _billingHostOverrideKey = 'ABO_BILLING_HOST';
const _localBillingHost = 'billing.vendor.test';

/// Test hook for E2E-P6.3-07; [Platform.environment] is not mutable in Dart tests.
@visibleForTesting
int? debugAboContractVersionOverride;

/// Localized marketing copy for one offer locale.
class BillingOfferCopyLocale {
  const BillingOfferCopyLocale({required this.name, required this.summary});

  final String name;
  final String summary;

  factory BillingOfferCopyLocale.fromJson(Map<String, dynamic> json) {
    return BillingOfferCopyLocale(
      name: json['name']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
    );
  }
}

/// Localized `copy` object from `GET /v1/offers`.
class BillingOfferCopy {
  const BillingOfferCopy({required this.locales});

  final Map<String, BillingOfferCopyLocale> locales;

  factory BillingOfferCopy.fromJson(Map<String, dynamic> json) {
    final locales = <String, BillingOfferCopyLocale>{};
    for (final entry in json.entries) {
      if (entry.value is Map) {
        locales[entry.key] = BillingOfferCopyLocale.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
    }
    return BillingOfferCopy(locales: locales);
  }

  BillingOfferCopyLocale? locale(String code) => locales[code];
}

/// Terms attached to a sellable offer.
class BillingOfferTerms {
  const BillingOfferTerms({required this.version, required this.text});

  final int version;
  final String text;

  factory BillingOfferTerms.fromJson(Map<String, dynamic> json) {
    return BillingOfferTerms(
      version: _readInt(json['version']),
      text: json['text']?.toString() ?? '',
    );
  }
}

/// One sellable offer from `GET /v1/offers`.
class BillingOffer {
  const BillingOffer({
    required this.offerId,
    required this.version,
    required this.planDisplayName,
    required this.termUnit,
    required this.termCount,
    required this.priceMinor,
    required this.currency,
    required this.allowanceCredits,
    required this.graceDays,
    required this.copy,
    required this.terms,
  });

  final String offerId;
  final int version;
  final String planDisplayName;
  final String termUnit;
  final int termCount;
  final int priceMinor;
  final String currency;
  final int allowanceCredits;
  final int graceDays;
  final BillingOfferCopy copy;
  final BillingOfferTerms terms;

  factory BillingOffer.fromJson(Map<String, dynamic> json) {
    return BillingOffer(
      offerId: json['offer_id']?.toString() ?? '',
      version: _readInt(json['version']),
      planDisplayName: json['plan_display_name']?.toString() ?? '',
      termUnit: json['term_unit']?.toString() ?? '',
      termCount: _readInt(json['term_count']),
      priceMinor: _readInt(json['price_minor']),
      currency: json['currency']?.toString() ?? '',
      allowanceCredits: _readInt(json['allowance_credits']),
      graceDays: _readInt(json['grace_days']),
      copy: BillingOfferCopy.fromJson(
        Map<String, dynamic>.from(json['copy'] as Map? ?? const {}),
      ),
      terms: BillingOfferTerms.fromJson(
        Map<String, dynamic>.from(json['terms'] as Map? ?? const {}),
      ),
    );
  }
}

/// `GET /v1/offers` payload.
class BillingOffersResponse {
  const BillingOffersResponse({required this.contractVersion, required this.offers});

  final int contractVersion;
  final List<BillingOffer> offers;

  factory BillingOffersResponse.fromJson(Map<String, dynamic> json) {
    final offersRaw = json['offers'];
    final offers = offersRaw is List
        ? offersRaw
            .map((entry) => BillingOffer.fromJson(Map<String, dynamic>.from(entry as Map)))
            .toList(growable: false)
        : const <BillingOffer>[];
    return BillingOffersResponse(
      contractVersion: _readInt(json['contract_version']),
      offers: offers,
    );
  }
}

/// Saved billing contact from `GET` or `PUT /v1/billing-contact`.
class BillingContact {
  const BillingContact({
    required this.contractVersion,
    required this.version,
    required this.name,
    required this.email,
    required this.phone,
  });

  final int contractVersion;
  final int version;
  final String name;
  final String email;
  final String phone;

  factory BillingContact.fromJson(Map<String, dynamic> json) {
    return BillingContact(
      contractVersion: _readInt(json['contract_version']),
      version: _readInt(json['version']),
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
    );
  }
}

/// `GET /v1/billing-contact` result.
sealed class BillingContactReadResult {
  const BillingContactReadResult();
}

final class BillingContactFound extends BillingContactReadResult {
  const BillingContactFound(this.contact);

  final BillingContact contact;
}

final class BillingContactMissing extends BillingContactReadResult {
  const BillingContactMissing();
}

/// Checkout term start decision from `POST /v1/checkouts`.
enum CheckoutStarts {
  now,
  afterCurrent;

  static CheckoutStarts parse(String? raw) {
    return raw == 'after_current' ? CheckoutStarts.afterCurrent : CheckoutStarts.now;
  }
}

/// Successful `POST /v1/checkouts` payload.
class CheckoutCreateResponse {
  const CheckoutCreateResponse({
    required this.contractVersion,
    required this.checkoutId,
    required this.reference,
    required this.redirectUrl,
    required this.expiresAt,
    required this.starts,
    this.projectedStart,
  });

  final int contractVersion;
  final String checkoutId;
  final String reference;
  final String redirectUrl;
  final DateTime expiresAt;
  final CheckoutStarts starts;
  final String? projectedStart;

  factory CheckoutCreateResponse.fromJson(Map<String, dynamic> json) {
    final starts = CheckoutStarts.parse(json['starts']?.toString());
    return CheckoutCreateResponse(
      contractVersion: _readInt(json['contract_version']),
      checkoutId: json['checkout_id']?.toString() ?? '',
      reference: json['reference']?.toString() ?? '',
      redirectUrl: json['redirect_url']?.toString() ?? '',
      expiresAt: _parseDateTime(json['expires_at']),
      starts: starts,
      projectedStart: starts == CheckoutStarts.afterCurrent
          ? json['projected_start']?.toString()
          : null,
    );
  }
}

/// Derived checkout progress from `GET /v1/checkouts/{id}`.
enum CheckoutShownState {
  waiting,
  failed,
  paid,
  active,
  abandoned;

  static CheckoutShownState? parse(String? raw) {
    return switch (raw) {
      'Waiting' => CheckoutShownState.waiting,
      'Failed' => CheckoutShownState.failed,
      'Paid' => CheckoutShownState.paid,
      'Active' => CheckoutShownState.active,
      'Abandoned' => CheckoutShownState.abandoned,
      _ => null,
    };
  }

  String get wireValue => switch (this) {
        CheckoutShownState.waiting => 'Waiting',
        CheckoutShownState.failed => 'Failed',
        CheckoutShownState.paid => 'Paid',
        CheckoutShownState.active => 'Active',
        CheckoutShownState.abandoned => 'Abandoned',
      };
}

/// Offer summary on a checkout read.
class CheckoutOfferSummary {
  const CheckoutOfferSummary({
    required this.offerId,
    required this.version,
    required this.termUnit,
    required this.termCount,
    required this.chargedPriceMinor,
    required this.currency,
  });

  final String offerId;
  final int version;
  final String termUnit;
  final int termCount;
  final int chargedPriceMinor;
  final String currency;

  factory CheckoutOfferSummary.fromJson(Map<String, dynamic> json) {
    return CheckoutOfferSummary(
      offerId: json['offer_id']?.toString() ?? '',
      version: _readInt(json['version']),
      termUnit: json['term_unit']?.toString() ?? '',
      termCount: _readInt(json['term_count']),
      chargedPriceMinor: _readInt(json['charged_price_minor']),
      currency: json['currency']?.toString() ?? '',
    );
  }
}

/// `GET /v1/checkouts/{id}` payload.
class CheckoutRead {
  const CheckoutRead({
    required this.contractVersion,
    required this.reference,
    required this.shownState,
    required this.offer,
    required this.updatedAt,
  });

  final int contractVersion;
  final String reference;
  final CheckoutShownState shownState;
  final CheckoutOfferSummary offer;
  final DateTime updatedAt;

  factory CheckoutRead.fromJson(Map<String, dynamic> json) {
    final shownState = CheckoutShownState.parse(json['shown_state']?.toString());
    if (shownState == null) {
      throw FormatException('checkout shown_state is invalid: ${json['shown_state']}');
    }
    return CheckoutRead(
      contractVersion: _readInt(json['contract_version']),
      reference: json['reference']?.toString() ?? '',
      shownState: shownState,
      offer: CheckoutOfferSummary.fromJson(
        Map<String, dynamic>.from(json['offer'] as Map? ?? const {}),
      ),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }
}

/// `GET /v1/checkouts?open=1` payload.
class OpenCheckoutsResponse {
  const OpenCheckoutsResponse({required this.contractVersion, required this.checkouts});

  final int contractVersion;
  final List<CheckoutRead> checkouts;

  factory OpenCheckoutsResponse.fromJson(Map<String, dynamic> json) {
    final checkoutsRaw = json['checkouts'];
    final checkouts = checkoutsRaw is List
        ? checkoutsRaw
            .map((entry) => CheckoutRead.fromJson(Map<String, dynamic>.from(entry as Map)))
            .toList(growable: false)
        : const <CheckoutRead>[];
    return OpenCheckoutsResponse(
      contractVersion: _readInt(json['contract_version']),
      checkouts: checkouts,
    );
  }
}

/// Payment classification from `GET /v1/payments`.
enum PaymentClassification {
  normal,
  likelyDuplicate,
  late;

  static PaymentClassification parse(String? raw) {
    return switch (raw) {
      'likely_duplicate' => PaymentClassification.likelyDuplicate,
      'late' => PaymentClassification.late,
      'normal' => PaymentClassification.normal,
      _ => throw FormatException('payment classification is invalid: $raw'),
    };
  }

  String get wireValue => switch (this) {
        PaymentClassification.normal => 'normal',
        PaymentClassification.likelyDuplicate => 'likely_duplicate',
        PaymentClassification.late => 'late',
      };
}

/// Reversal kind from `GET /v1/payments`.
enum ReversalKind {
  refund,
  void_,
  chargeback,
  unknown;

  static ReversalKind parse(String? raw) {
    return switch (raw) {
      'refund' => ReversalKind.refund,
      'void' => ReversalKind.void_,
      'chargeback' => ReversalKind.chargeback,
      'unknown' => ReversalKind.unknown,
      _ => throw FormatException('reversal kind is invalid: $raw'),
    };
  }

  String get wireValue => switch (this) {
        ReversalKind.refund => 'refund',
        ReversalKind.void_ => 'void',
        ReversalKind.chargeback => 'chargeback',
        ReversalKind.unknown => 'unknown',
      };
}

/// One reversal on a payment from `GET /v1/payments`.
class PaymentReversal {
  const PaymentReversal({
    required this.reference,
    required this.amountMinor,
    required this.kind,
    required this.isFull,
  });

  final String reference;
  final int amountMinor;
  final ReversalKind kind;
  final bool isFull;

  factory PaymentReversal.fromJson(Map<String, dynamic> json) {
    return PaymentReversal(
      reference: json['reference']?.toString() ?? '',
      amountMinor: _readInt(json['amount_minor']),
      kind: ReversalKind.parse(json['kind']?.toString()),
      isFull: json['is_full'] == true,
    );
  }
}

/// One payment from `GET /v1/payments`.
class PaymentRecord {
  const PaymentRecord({
    required this.reference,
    required this.paidAt,
    required this.amountMinor,
    required this.currency,
    required this.planDisplayName,
    required this.offerVersion,
    required this.termUnit,
    required this.termCount,
    required this.classification,
    required this.reversals,
  });

  final String reference;
  final DateTime paidAt;
  final int amountMinor;
  final String currency;
  final String planDisplayName;
  final int offerVersion;
  final String termUnit;
  final int termCount;
  final PaymentClassification classification;
  final List<PaymentReversal> reversals;

  factory PaymentRecord.fromJson(Map<String, dynamic> json) {
    final reversalsRaw = json['reversals'];
    final reversals = reversalsRaw is List
        ? reversalsRaw
            .map((entry) => PaymentReversal.fromJson(Map<String, dynamic>.from(entry as Map)))
            .toList(growable: false)
        : const <PaymentReversal>[];
    return PaymentRecord(
      reference: json['reference']?.toString() ?? '',
      paidAt: _parseDateTime(json['paid_at']),
      amountMinor: _readInt(json['amount_minor']),
      currency: json['currency']?.toString() ?? '',
      planDisplayName: json['plan_display_name']?.toString() ?? '',
      offerVersion: _readInt(json['offer_version']),
      termUnit: json['term_unit']?.toString() ?? '',
      termCount: _readInt(json['term_count']),
      classification: PaymentClassification.parse(json['classification']?.toString()),
      reversals: reversals,
    );
  }
}

/// `GET /v1/payments` payload.
class PaymentsResponse {
  const PaymentsResponse({
    required this.contractVersion,
    required this.payments,
    required this.nextCursor,
    required this.hasMore,
  });

  final int contractVersion;
  final List<PaymentRecord> payments;
  final String nextCursor;
  final bool hasMore;

  factory PaymentsResponse.fromJson(Map<String, dynamic> json) {
    final paymentsRaw = json['payments'];
    final payments = paymentsRaw is List
        ? paymentsRaw
            .map((entry) => PaymentRecord.fromJson(Map<String, dynamic>.from(entry as Map)))
            .toList(growable: false)
        : const <PaymentRecord>[];
    return PaymentsResponse(
      contractVersion: _readInt(json['contract_version']),
      payments: payments,
      nextCursor: json['next_cursor']?.toString() ?? '',
      hasMore: json['has_more'] == true,
    );
  }
}

/// `GET /v1/subscription` payload.
class SubscriptionResponse {
  const SubscriptionResponse({
    required this.contractVersion,
    required this.subscriptionRef,
    this.snapshot,
    required this.notices,
  });

  final int contractVersion;
  final String subscriptionRef;
  final Map<String, dynamic>? snapshot;
  final List<String> notices;

  factory SubscriptionResponse.fromJson(Map<String, dynamic> json) {
    final snapshotRaw = json['snapshot'];
    final noticesRaw = json['notices'];
    final notices = noticesRaw is List
        ? noticesRaw.map((entry) => entry.toString()).toList(growable: false)
        : const <String>[];
    return SubscriptionResponse(
      contractVersion: _readInt(json['contract_version']),
      subscriptionRef: json['subscription_ref']?.toString() ?? '',
      snapshot: snapshotRaw is Map ? Map<String, dynamic>.from(snapshotRaw) : null,
      notices: notices,
    );
  }
}

/// Base for ABO error responses mapped from §2.3.
abstract class AboApiException implements Exception {
  const AboApiException({required this.code, required this.contractVersion});

  final String code;
  final int contractVersion;

  @override
  String toString() => 'AboApiException($code, contractVersion: $contractVersion)';
}

final class AboUnknownException extends AboApiException {
  const AboUnknownException({required super.code, required super.contractVersion});
}

final class AboOfferUnavailableException extends AboApiException {
  const AboOfferUnavailableException({
    required super.contractVersion,
    this.currentVersion,
  }) : super(code: 'offer_unavailable');

  final int? currentVersion;
}

final class AboBillingContactRequiredException extends AboApiException {
  const AboBillingContactRequiredException({required super.contractVersion})
      : super(code: 'billing_contact_required');
}

final class AboTermsNotAcceptedException extends AboApiException {
  const AboTermsNotAcceptedException({required super.contractVersion})
      : super(code: 'terms_not_accepted');
}

final class AboProviderUnavailableException extends AboApiException {
  const AboProviderUnavailableException({
    required super.contractVersion,
    this.checkoutId,
  }) : super(code: 'provider_unavailable');

  final String? checkoutId;
}

final class AboRateLimitedException extends AboApiException {
  const AboRateLimitedException({required super.contractVersion}) : super(code: 'rate_limited');
}

final class AboContractVersionUnsupportedException extends AboApiException {
  const AboContractVersionUnsupportedException({
    required super.contractVersion,
    required this.acceptedVersions,
  }) : super(code: 'contract_version_unsupported');

  final List<int> acceptedVersions;
}

final class AboInvalidRequestException extends AboApiException {
  const AboInvalidRequestException({required super.contractVersion})
      : super(code: 'invalid_request');
}

/// ABO clinic API client over the billing token session.
class AboClient {
  AboClient({
    required BillingTokenClient tokenClient,
    http.Client? httpClient,
  })  : _tokenClient = tokenClient,
        _httpClient = httpClient ?? http.Client();

  final BillingTokenClient _tokenClient;
  final http.Client _httpClient;

  Future<BillingOffersResponse> getOffers() async {
    final response = await _request('GET', '/v1/offers');
    _throwOnError(response);
    return BillingOffersResponse.fromJson(_decodeObject(response.body));
  }

  Future<BillingContactReadResult> getBillingContact() async {
    final response = await _request('GET', '/v1/billing-contact');
    if (response.statusCode == 404) {
      final body = _tryDecodeObject(response.body);
      if (body['code']?.toString() == 'not_found') {
        return const BillingContactMissing();
      }
    }
    _throwOnError(response);
    return BillingContactFound(BillingContact.fromJson(_decodeObject(response.body)));
  }

  Future<BillingContact> putBillingContact({
    required String clientRequestId,
    required String name,
    required String email,
    required String phone,
  }) async {
    final response = await _request(
      'PUT',
      '/v1/billing-contact',
      body: {
        'client_request_id': clientRequestId,
        'name': name,
        'email': email,
        'phone': phone,
      },
    );
    _throwOnError(response);
    return BillingContact.fromJson(_decodeObject(response.body));
  }

  Future<CheckoutCreateResponse> createCheckout({
    required String clientRequestId,
    required String offerId,
    required int offerVersion,
    required int termsVersion,
  }) async {
    final response = await _request(
      'POST',
      '/v1/checkouts',
      body: {
        'client_request_id': clientRequestId,
        'offer_id': offerId,
        'offer_version': offerVersion,
        'terms_version': termsVersion,
      },
    );
    _throwOnError(response);
    return CheckoutCreateResponse.fromJson(_decodeObject(response.body));
  }

  Future<CheckoutRead> getCheckout(String checkoutId) async {
    final response = await _request('GET', '/v1/checkouts/$checkoutId');
    _throwOnError(response);
    return CheckoutRead.fromJson(_decodeObject(response.body));
  }

  Future<OpenCheckoutsResponse> listOpenCheckouts() async {
    final response = await _request('GET', '/v1/checkouts?open=1');
    _throwOnError(response);
    return OpenCheckoutsResponse.fromJson(_decodeObject(response.body));
  }

  Future<SubscriptionResponse> getSubscription() async {
    final response = await _request('GET', '/v1/subscription');
    _throwOnError(response);
    return SubscriptionResponse.fromJson(_decodeObject(response.body));
  }

  Future<PaymentsResponse> getPayments({String? cursor}) async {
    final path = cursor == null || cursor.isEmpty
        ? '/v1/payments'
        : '/v1/payments?cursor=${Uri.encodeComponent(cursor)}';
    final response = await _request('GET', path);
    _throwOnError(response);
    return PaymentsResponse.fromJson(_decodeObject(response.body));
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final session = await _tokenClient.ensureToken();
    final base = _normalizeBaseUrl(session.aboBaseUrl);
    final uri = Uri.parse('$base$path');
    final headers = _headers(session.token, session.aboBaseUrl);
    switch (method) {
      case 'GET':
        return _httpClient.get(uri, headers: headers);
      case 'PUT':
      case 'POST':
        headers['content-type'] = 'application/json';
        return _httpClient.send(
          http.Request(method, uri)
            ..headers.addAll(headers)
            ..body = jsonEncode(body ?? const {}),
        ).then(http.Response.fromStream);
      default:
        throw ArgumentError.value(method, 'method', 'unsupported HTTP method');
    }
  }

  Map<String, String> _headers(String token, String aboBaseUrl) {
    return {
      'Authorization': 'Bearer $token',
      'accept': 'application/json',
      'Abo-Contract-Version': '${_contractVersionHeaderValue()}',
      'Host': _billingHost(aboBaseUrl),
    };
  }

  int _contractVersionHeaderValue() {
    if (debugAboContractVersionOverride != null) {
      return debugAboContractVersionOverride!;
    }
    final override = Platform.environment[_contractVersionOverrideKey];
    if (override != null && override.isNotEmpty) {
      return int.parse(override);
    }
    return aboClinic;
  }

  String _billingHost(String aboBaseUrl) {
    final override = Platform.environment[_billingHostOverrideKey];
    if (override != null && override.isNotEmpty) {
      return override;
    }
    final host = Uri.parse(aboBaseUrl).host;
    if (host == '127.0.0.1' || host == 'localhost') {
      return _localBillingHost;
    }
    return host;
  }

  String _normalizeBaseUrl(String aboBaseUrl) {
    return aboBaseUrl.endsWith('/')
        ? aboBaseUrl.substring(0, aboBaseUrl.length - 1)
        : aboBaseUrl;
  }

  void _throwOnError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final body = _tryDecodeObject(response.body);
    final code = body['code']?.toString();
    final contractVersion = _readInt(body['contract_version']);
    switch (code) {
      case 'offer_unavailable':
        throw AboOfferUnavailableException(
          contractVersion: contractVersion,
          currentVersion: _optionalInt(body['current_version']),
        );
      case 'billing_contact_required':
        throw AboBillingContactRequiredException(contractVersion: contractVersion);
      case 'terms_not_accepted':
        throw AboTermsNotAcceptedException(contractVersion: contractVersion);
      case 'provider_unavailable':
        throw AboProviderUnavailableException(
          contractVersion: contractVersion,
          checkoutId: body['checkout_id']?.toString(),
        );
      case 'rate_limited':
        throw AboRateLimitedException(contractVersion: contractVersion);
      case 'contract_version_unsupported':
        throw AboContractVersionUnsupportedException(
          contractVersion: contractVersion,
          acceptedVersions: _readAcceptedVersions(body['accepted_versions']),
        );
      case 'invalid_request':
        throw AboInvalidRequestException(contractVersion: contractVersion);
      default:
        throw AboUnknownException(code: code ?? 'abo_error', contractVersion: contractVersion);
    }
  }
}

Map<String, dynamic> _decodeObject(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  if (decoded is Map) {
    return Map<String, dynamic>.from(decoded);
  }
  throw FormatException('ABO response body is not an object');
}

Map<String, dynamic> _tryDecodeObject(String body) {
  try {
    return _decodeObject(body);
  } on FormatException {
    return {};
  }
}

int _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.parse(value?.toString() ?? '0');
}

int? _optionalInt(Object? value) {
  if (value == null) {
    return null;
  }
  return _readInt(value);
}

DateTime _parseDateTime(Object? raw) {
  if (raw is DateTime) {
    return raw.toUtc();
  }
  if (raw is String && raw.isNotEmpty) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return parsed.toUtc();
    }
  }
  throw FormatException('ABO datetime is invalid: $raw');
}

List<int> _readAcceptedVersions(Object? raw) {
  if (raw is List) {
    return raw.map(_readInt).toList(growable: false);
  }
  return const [];
}
