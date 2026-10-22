import 'package:flutter/foundation.dart';

import 'ai_availability.dart';

/// R7-T1: the staff/organization/role a shell status read belongs to.
@immutable
class AiStatusIdentity {
  const AiStatusIdentity({
    required this.userId,
    required this.organizationId,
    required this.role,
  });

  final String userId;
  final String organizationId;
  final String role;

  String get key => '$userId|$organizationId|$role';

  @override
  bool operator ==(Object other) => other is AiStatusIdentity && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// R7-T1: what open AI hosts receive from the app-shell status source.
///
/// [availability] is the latest valid status. It is retained across transient read
/// failures; [refreshFailed] marks that it may be stale. [updateRequired] is the explicit
/// outcome for `CONTRACT_VERSION_UNSUPPORTED`.
@immutable
class AiStatusSnapshot {
  const AiStatusSnapshot({
    this.identity,
    this.availability,
    this.updateRequired = false,
    this.refreshFailed = false,
  });

  static const empty = AiStatusSnapshot();

  final AiStatusIdentity? identity;
  final AiAvailability? availability;
  final bool updateRequired;
  final bool refreshFailed;
}

/// Readiness/context key: a change means the host must re-derive mode and recompose.
/// Notice-only changes keep the same key, so they never restart the resolver.
String aiStatusContextKey(AiStatusSnapshot status) {
  if (status.updateRequired) {
    return 'update-required';
  }
  final availability = status.availability;
  if (availability == null) {
    return 'unknown';
  }
  if (!availability.available) {
    return 'unavailable';
  }
  return 'ready|${availability.platformBaseUrl ?? ''}';
}

/// What an open host does with a newly applied status (R7-T1).
enum AiStatusApplyPlan {
  /// No valid status yet; keep the current state.
  awaitStatus,

  /// Explicit update-required outcome: AI hidden, clinical navigation unaffected.
  updateRequired,

  /// Same readiness, no retained denial: update notices only, never restart work.
  noticesOnly,

  /// Coverage denial is still reported: keep the denial visible.
  retainDenial,

  /// Readiness/context changed or a denial recovered: re-derive mode and recompose
  /// the resolver once. Recomposed surfaces never auto-invoke.
  recomposeHost,
}

AiStatusApplyPlan planAiStatusApply({
  required String? currentContextKey,
  required bool denialRetained,
  required AiStatusSnapshot status,
}) {
  if (status.updateRequired) {
    return AiStatusApplyPlan.updateRequired;
  }
  final availability = status.availability;
  if (availability == null) {
    return AiStatusApplyPlan.awaitStatus;
  }
  if (denialRetained && availability.available && isCoverageDenialWireCode(availability.reason)) {
    return AiStatusApplyPlan.retainDenial;
  }
  if (denialRetained || aiStatusContextKey(status) != currentContextKey) {
    return AiStatusApplyPlan.recomposeHost;
  }
  return AiStatusApplyPlan.noticesOnly;
}

/// Orders shell status reads. A read publishes only while its identity and generation
/// are still current, so a late read from an earlier identity or an overlapped older
/// refresh cannot overwrite newer state (R7-T1).
class AiStatusFetchGate {
  AiStatusIdentity? _identity;
  int _generation = 0;

  AiStatusIdentity? get identity => _identity;

  /// Starts a read for [identity]. A different identity first invalidates older reads.
  int begin(AiStatusIdentity identity) {
    if (_identity != identity) {
      _identity = identity;
      _generation++;
    }
    return ++_generation;
  }

  bool isCurrent(AiStatusIdentity identity, int generation) {
    return _identity == identity && _generation == generation;
  }

  /// Sign-out or identity loss: every in-flight read becomes stale.
  void invalidate() {
    _identity = null;
    _generation++;
  }
}
