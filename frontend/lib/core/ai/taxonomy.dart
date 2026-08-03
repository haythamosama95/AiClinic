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
];

bool isTaxonomyCode(String code) => _wireToCode.containsKey(code);

TaxonomyCode classifyTaxonomyCode(String code) =>
    _wireToCode[code] ?? TaxonomyCode.internalError;

String taxonomyCodeToWire(TaxonomyCode code) => _codeToWire[code]!;
