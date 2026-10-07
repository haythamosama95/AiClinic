import 'package:ai_clinic/core/ai/taxonomy.dart';

import '../availability/ai_availability.dart';

/// First-class degraded states for AI affordances (A11; §5.4).
enum AiDegradedMode {
  nonEnrolled,
  unreachable,
  quotaExhausted,
  aiUnavailable,
  appUpdate,
  providerUnavailable,
  installationSuspended,
  forbiddenCapability,
  safetyLimited,
  ready,
}

AiDegradedMode resolveDegradedMode({
  required AiAvailability availability,
  required bool platformReachable,
  TaxonomyCode? terminalFailureCode,
  bool networkFailure = false,
}) {
  if (!availability.enrolled) {
    return AiDegradedMode.nonEnrolled;
  }

  if (networkFailure) {
    return AiDegradedMode.unreachable;
  }

  if (terminalFailureCode == TaxonomyCode.installationSuspended ||
      terminalFailureCode == TaxonomyCode.suspended) {
    return AiDegradedMode.installationSuspended;
  }
  if (terminalFailureCode == TaxonomyCode.forbiddenCapability) {
    return AiDegradedMode.forbiddenCapability;
  }
  if (terminalFailureCode == TaxonomyCode.quotaExhausted ||
      terminalFailureCode == TaxonomyCode.allowanceExhausted ||
      terminalFailureCode == TaxonomyCode.coverageLapsed) {
    return AiDegradedMode.quotaExhausted;
  }
  if (terminalFailureCode == TaxonomyCode.coverageUnknown ||
      terminalFailureCode == TaxonomyCode.statusStale) {
    return AiDegradedMode.unreachable;
  }
  if (terminalFailureCode == TaxonomyCode.concurrencyLimited ||
      terminalFailureCode == TaxonomyCode.rateLimited) {
    return AiDegradedMode.safetyLimited;
  }
  if (terminalFailureCode == TaxonomyCode.contractVersionUnsupported) {
    return AiDegradedMode.appUpdate;
  }
  if (terminalFailureCode == TaxonomyCode.capabilityUnknown ||
      terminalFailureCode == TaxonomyCode.capabilityRetired) {
    return AiDegradedMode.appUpdate;
  }
  if (terminalFailureCode == TaxonomyCode.providerUnavailable) {
    return AiDegradedMode.providerUnavailable;
  }
  if (terminalFailureCode == TaxonomyCode.capabilityDisabled) {
    return AiDegradedMode.aiUnavailable;
  }

  if (!platformReachable) {
    return AiDegradedMode.unreachable;
  }

  return AiDegradedMode.ready;
}
