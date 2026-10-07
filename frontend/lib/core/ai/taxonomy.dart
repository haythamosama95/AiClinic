/// Dart mirror of the §5.4 closed taxonomy code set (Consumes A2 via A6).
enum TaxonomyCode {
  unauthenticated,
  installationSuspended,
  forbiddenCapability,
  rateLimited,
  quotaExhausted,
  requestTooLarge,
  contextRequired,
  contextInvalid,
  conversationBudgetExhausted,
  capabilityUnknown,
  capabilityRetired,
  capabilityDisabled,
  providerUnavailable,
  providerRejected,
  validationFailed,
  cancelled,
  timeout,
  internalError,
  // 04 §4.2 pre-stream denial codes (P6.2).
  allowanceExhausted,
  coverageLapsed,
  coverageUnknown,
  suspended,
  concurrencyLimited,
  contractVersionUnsupported,
  statusStale,
}

const _wireToCode = <String, TaxonomyCode>{
  'unauthenticated': TaxonomyCode.unauthenticated,
  'installation_suspended': TaxonomyCode.installationSuspended,
  'forbidden_capability': TaxonomyCode.forbiddenCapability,
  'rate_limited': TaxonomyCode.rateLimited,
  'quota_exhausted': TaxonomyCode.quotaExhausted,
  'request_too_large': TaxonomyCode.requestTooLarge,
  'context_required': TaxonomyCode.contextRequired,
  'context_invalid': TaxonomyCode.contextInvalid,
  'conversation_budget_exhausted': TaxonomyCode.conversationBudgetExhausted,
  'capability_unknown': TaxonomyCode.capabilityUnknown,
  'capability_retired': TaxonomyCode.capabilityRetired,
  'capability_disabled': TaxonomyCode.capabilityDisabled,
  'provider_unavailable': TaxonomyCode.providerUnavailable,
  'provider_rejected': TaxonomyCode.providerRejected,
  'validation_failed': TaxonomyCode.validationFailed,
  'cancelled': TaxonomyCode.cancelled,
  'timeout': TaxonomyCode.timeout,
  'internal_error': TaxonomyCode.internalError,
  'allowance_exhausted': TaxonomyCode.allowanceExhausted,
  'coverage_lapsed': TaxonomyCode.coverageLapsed,
  'coverage_unknown': TaxonomyCode.coverageUnknown,
  'suspended': TaxonomyCode.suspended,
  'concurrency_limited': TaxonomyCode.concurrencyLimited,
  'contract_version_unsupported': TaxonomyCode.contractVersionUnsupported,
  'status_stale': TaxonomyCode.statusStale,
};

const _codeToWire = <TaxonomyCode, String>{
  TaxonomyCode.unauthenticated: 'unauthenticated',
  TaxonomyCode.installationSuspended: 'installation_suspended',
  TaxonomyCode.forbiddenCapability: 'forbidden_capability',
  TaxonomyCode.rateLimited: 'rate_limited',
  TaxonomyCode.quotaExhausted: 'quota_exhausted',
  TaxonomyCode.requestTooLarge: 'request_too_large',
  TaxonomyCode.contextRequired: 'context_required',
  TaxonomyCode.contextInvalid: 'context_invalid',
  TaxonomyCode.conversationBudgetExhausted: 'conversation_budget_exhausted',
  TaxonomyCode.capabilityUnknown: 'capability_unknown',
  TaxonomyCode.capabilityRetired: 'capability_retired',
  TaxonomyCode.capabilityDisabled: 'capability_disabled',
  TaxonomyCode.providerUnavailable: 'provider_unavailable',
  TaxonomyCode.providerRejected: 'provider_rejected',
  TaxonomyCode.validationFailed: 'validation_failed',
  TaxonomyCode.cancelled: 'cancelled',
  TaxonomyCode.timeout: 'timeout',
  TaxonomyCode.internalError: 'internal_error',
  TaxonomyCode.allowanceExhausted: 'allowance_exhausted',
  TaxonomyCode.coverageLapsed: 'coverage_lapsed',
  TaxonomyCode.coverageUnknown: 'coverage_unknown',
  TaxonomyCode.suspended: 'suspended',
  TaxonomyCode.concurrencyLimited: 'concurrency_limited',
  TaxonomyCode.contractVersionUnsupported: 'contract_version_unsupported',
  TaxonomyCode.statusStale: 'status_stale',
};

/// Every terminal §5.4 code other than the [unauthenticated] remint path.
const terminalNoRetryCodes = <TaxonomyCode>[
  TaxonomyCode.installationSuspended,
  TaxonomyCode.forbiddenCapability,
  TaxonomyCode.rateLimited,
  TaxonomyCode.quotaExhausted,
  TaxonomyCode.requestTooLarge,
  TaxonomyCode.contextRequired,
  TaxonomyCode.contextInvalid,
  TaxonomyCode.conversationBudgetExhausted,
  TaxonomyCode.capabilityUnknown,
  TaxonomyCode.capabilityRetired,
  TaxonomyCode.capabilityDisabled,
  TaxonomyCode.providerUnavailable,
  TaxonomyCode.providerRejected,
  TaxonomyCode.validationFailed,
  TaxonomyCode.cancelled,
  TaxonomyCode.timeout,
  TaxonomyCode.internalError,
  TaxonomyCode.allowanceExhausted,
  TaxonomyCode.coverageLapsed,
  TaxonomyCode.coverageUnknown,
  TaxonomyCode.suspended,
  TaxonomyCode.concurrencyLimited,
  TaxonomyCode.contractVersionUnsupported,
  TaxonomyCode.statusStale,
];

bool isTaxonomyCode(String code) => _wireToCode.containsKey(code);

TaxonomyCode classifyTaxonomyCode(String code) =>
    _wireToCode[code] ?? TaxonomyCode.internalError;

String taxonomyCodeToWire(TaxonomyCode code) => _codeToWire[code]!;

/// Classified pre-stream denial from a platform HTTP error body (04 §4.2).
class PreStreamDenial {
  const PreStreamDenial({
    required this.wireCode,
    required this.code,
    this.retryAfter,
    this.coverageReason,
    this.acceptedVersions,
  });

  final String wireCode;
  final TaxonomyCode code;
  final String? retryAfter;
  final String? coverageReason;
  final List<String>? acceptedVersions;
}

/// Returns a [PreStreamDenial] only when [httpStatus] matches the 04 §4.2 row.
PreStreamDenial? classifyPreStreamDenial({
  required int httpStatus,
  required Map<String, dynamic> body,
}) {
  final wireCode = body['code']?.toString() ?? '';
  if (wireCode.isEmpty) {
    return null;
  }

  switch (wireCode) {
    case 'allowance_exhausted':
      if (httpStatus != 403) {
        return null;
      }
      return PreStreamDenial(wireCode: wireCode, code: TaxonomyCode.allowanceExhausted);
    case 'coverage_lapsed':
      if (httpStatus != 403) {
        return null;
      }
      return PreStreamDenial(
        wireCode: wireCode,
        code: TaxonomyCode.coverageLapsed,
        coverageReason: body['coverage_reason']?.toString(),
      );
    case 'coverage_unknown':
      if (httpStatus != 503) {
        return null;
      }
      return PreStreamDenial(
        wireCode: wireCode,
        code: TaxonomyCode.coverageUnknown,
        retryAfter: body['retry_after']?.toString(),
      );
    case 'suspended':
      if (httpStatus != 403) {
        return null;
      }
      return PreStreamDenial(wireCode: wireCode, code: TaxonomyCode.suspended);
    case 'concurrency_limited':
      if (httpStatus != 429) {
        return null;
      }
      return PreStreamDenial(
        wireCode: wireCode,
        code: TaxonomyCode.concurrencyLimited,
        retryAfter: body['retry_after']?.toString(),
      );
    case 'rate_limited':
      if (httpStatus != 429) {
        return null;
      }
      return PreStreamDenial(
        wireCode: wireCode,
        code: TaxonomyCode.rateLimited,
        retryAfter: body['retry_after']?.toString(),
      );
    case 'contract_version_unsupported':
      if (httpStatus != 400) {
        return null;
      }
      final rawVersions = body['accepted_versions'];
      final acceptedVersions = rawVersions is List
          ? rawVersions.map((entry) => entry.toString()).toList(growable: false)
          : null;
      return PreStreamDenial(
        wireCode: wireCode,
        code: TaxonomyCode.contractVersionUnsupported,
        acceptedVersions: acceptedVersions,
      );
    default:
      return null;
  }
}
