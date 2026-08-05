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
  ready,
}

AiDegradedMode resolveDegradedMode({
  required AiAvailability availability,
  required bool platformReachable,
  TaxonomyCode? terminalFailureCode,
}) {
  if (!availability.enrolled) {
    return AiDegradedMode.nonEnrolled;
  }

  if (terminalFailureCode == TaxonomyCode.installationSuspended) {
    return AiDegradedMode.installationSuspended;
  }
  if (terminalFailureCode == TaxonomyCode.forbiddenCapability) {
    return AiDegradedMode.forbiddenCapability;
  }
  if (terminalFailureCode == TaxonomyCode.quotaExhausted) {
    return AiDegradedMode.quotaExhausted;
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
