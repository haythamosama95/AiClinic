import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

import 'ai_degraded_mode.dart';

const kAiDegradedUnreachableKey = Key('ai_degraded_unreachable');
const kAiDegradedQuotaKey = Key('ai_degraded_quota');
const kAiDegradedAiUnavailableKey = Key('ai_degraded_ai_unavailable');
const kAiDegradedAppUpdateKey = Key('ai_degraded_app_update');
const kAiDegradedProviderUnavailableKey = Key('ai_degraded_provider_unavailable');
const kAiDegradedRetryKey = Key('ai_degraded_retry');
const kAiDegradedNonEnrolledKey = Key('ai_degraded_non_enrolled');
const kAiDegradedInstallationSuspendedKey = Key('ai_degraded_installation_suspended');
const kAiDegradedForbiddenCapabilityKey = Key('ai_degraded_forbidden_capability');
const kAiDegradedSafetyLimitedKey = Key('ai_degraded_safety_limited');
const kAiDegradedRenewOrBuyKey = Key('ai_degraded_renew_or_buy');
const kAiAffordanceKey = Key('ai_affordance');

/// Normal-state UI for degraded modes — not error dialogs (A11; FR-011).
class AiDegradedView extends StatelessWidget {
  const AiDegradedView({
    super.key,
    required this.mode,
    this.child,
    this.onRetry,
    this.staffIsAdministrator = false,
    this.wireCode,
    this.retryAfter,
    this.subscriptionRef,
    this.planDisplayName,
  });

  final AiDegradedMode mode;
  final Widget? child;
  final VoidCallback? onRetry;
  final bool staffIsAdministrator;
  final String? wireCode;
  final String? retryAfter;
  final String? subscriptionRef;
  final String? planDisplayName;

  @override
  Widget build(BuildContext context) {
    if (mode == AiDegradedMode.ready) {
      return KeyedSubtree(
        key: kAiAffordanceKey,
        child: child ?? const SizedBox.shrink(),
      );
    }

    // Non-enrolled: no AI chrome (§4.2) — host normally short-circuits before this.
    if (mode == AiDegradedMode.nonEnrolled) {
      return child ?? const SizedBox.shrink();
    }

    final colors = context.appColors;
    final message = _messageForMode(
      mode,
      wireCode: wireCode,
      staffIsAdministrator: staffIsAdministrator,
      retryAfter: retryAfter,
    );
    final showRenewOrBuy = staffIsAdministrator &&
        (wireCode == 'allowance_exhausted' || wireCode == 'coverage_lapsed');
    final showContactSupport = staffIsAdministrator && wireCode == 'suspended';
    final showPlanName = staffIsAdministrator && wireCode == 'forbidden_capability' && planDisplayName != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: message,
          child: Container(
            key: _keyForMode(mode),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Text(
              message,
              style: AppTypography.body(context).copyWith(color: colors.textSecondary),
            ),
          ),
        ),
        if (showRenewOrBuy) ...[
          const SizedBox(height: 12),
          AppButton(
            key: kAiDegradedRenewOrBuyKey,
            onPressed: () => context.push(AppRoutes.aiAdministratorBilling),
            child: const Text('Renew or buy'),
          ),
        ],
        if (showContactSupport) ...[
          const SizedBox(height: 12),
          Text(
            'Contact support',
            style: AppTypography.body(context).copyWith(color: colors.textSecondary),
          ),
          if (subscriptionRef != null) ...[
            const SizedBox(height: 4),
            Text(
              subscriptionRef!,
              style: AppTypography.body(context).copyWith(color: colors.textSecondary),
            ),
          ],
        ],
        if (showPlanName) ...[
          const SizedBox(height: 12),
          Text(
            planDisplayName!,
            style: AppTypography.body(context).copyWith(color: colors.textSecondary),
          ),
        ],
        if (mode == AiDegradedMode.providerUnavailable && onRetry != null) ...[
          const SizedBox(height: 12),
          AppButton(
            key: kAiDegradedRetryKey,
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
        if (child != null) ...[
          const SizedBox(height: 16),
          child!,
        ],
      ],
    );
  }

  static String _messageForMode(
    AiDegradedMode mode, {
    String? wireCode,
    required bool staffIsAdministrator,
    String? retryAfter,
  }) {
    switch (mode) {
      case AiDegradedMode.nonEnrolled:
        return '';
      case AiDegradedMode.unreachable:
        return 'AI service unreachable';
      case AiDegradedMode.quotaExhausted:
        if (wireCode == 'allowance_exhausted' || wireCode == 'coverage_lapsed') {
          return 'AI not available, contact your administrator';
        }
        return 'AI quota exhausted. Contact your administrator.';
      case AiDegradedMode.aiUnavailable:
        return 'AI temporarily unavailable';
      case AiDegradedMode.appUpdate:
        return 'Update the app to use AI';
      case AiDegradedMode.providerUnavailable:
        return 'AI temporarily unavailable';
      case AiDegradedMode.installationSuspended:
        if (wireCode == 'suspended') {
          return 'AI not available, contact your administrator';
        }
        return 'AI features are suspended for this installation.';
      case AiDegradedMode.forbiddenCapability:
        return "Not included in your clinic's AI plan";
      case AiDegradedMode.safetyLimited:
        final retrySuffix = retryAfter != null ? ' $retryAfter' : '';
        return 'AI busy, try again shortly$retrySuffix';
      case AiDegradedMode.ready:
        return '';
    }
  }

  static Key _keyForMode(AiDegradedMode mode) => switch (mode) {
        AiDegradedMode.nonEnrolled => kAiDegradedNonEnrolledKey,
        AiDegradedMode.unreachable => kAiDegradedUnreachableKey,
        AiDegradedMode.quotaExhausted => kAiDegradedQuotaKey,
        AiDegradedMode.aiUnavailable => kAiDegradedAiUnavailableKey,
        AiDegradedMode.appUpdate => kAiDegradedAppUpdateKey,
        AiDegradedMode.providerUnavailable => kAiDegradedProviderUnavailableKey,
        AiDegradedMode.installationSuspended => kAiDegradedInstallationSuspendedKey,
        AiDegradedMode.forbiddenCapability => kAiDegradedForbiddenCapabilityKey,
        AiDegradedMode.safetyLimited => kAiDegradedSafetyLimitedKey,
        AiDegradedMode.ready => kAiAffordanceKey,
      };
}
