import 'package:flutter/material.dart';

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
const kAiAffordanceKey = Key('ai_affordance');

/// Normal-state UI for degraded modes — not error dialogs (A11; FR-011).
class AiDegradedView extends StatelessWidget {
  const AiDegradedView({
    super.key,
    required this.mode,
    this.child,
    this.onRetry,
  });

  final AiDegradedMode mode;
  final Widget? child;
  final VoidCallback? onRetry;

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
    final message = _messageForMode(mode);

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

  static String _messageForMode(AiDegradedMode mode) => switch (mode) {
        AiDegradedMode.nonEnrolled => '',
        AiDegradedMode.unreachable => 'AI platform is currently unreachable.',
        AiDegradedMode.quotaExhausted => 'AI quota exhausted. Contact your administrator.',
        AiDegradedMode.aiUnavailable => 'AI is temporarily unavailable.',
        AiDegradedMode.appUpdate => 'Please update the app to use this AI feature.',
        AiDegradedMode.providerUnavailable =>
          'AI provider is unavailable. You can retry.',
        AiDegradedMode.installationSuspended =>
          'AI features are suspended for this installation.',
        AiDegradedMode.forbiddenCapability =>
          'You do not have permission to use this AI capability.',
        AiDegradedMode.ready => '',
      };

  static Key _keyForMode(AiDegradedMode mode) => switch (mode) {
        AiDegradedMode.nonEnrolled => kAiDegradedNonEnrolledKey,
        AiDegradedMode.unreachable => kAiDegradedUnreachableKey,
        AiDegradedMode.quotaExhausted => kAiDegradedQuotaKey,
        AiDegradedMode.aiUnavailable => kAiDegradedAiUnavailableKey,
        AiDegradedMode.appUpdate => kAiDegradedAppUpdateKey,
        AiDegradedMode.providerUnavailable => kAiDegradedProviderUnavailableKey,
        AiDegradedMode.installationSuspended => kAiDegradedInstallationSuspendedKey,
        AiDegradedMode.forbiddenCapability => kAiDegradedForbiddenCapabilityKey,
        AiDegradedMode.ready => kAiAffordanceKey,
      };
}
