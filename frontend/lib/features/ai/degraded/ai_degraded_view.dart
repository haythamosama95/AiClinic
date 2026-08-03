import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

import 'ai_degraded_mode.dart';

const kAiDegradedUnreachableKey = Key('ai_degraded_unreachable');
const kAiDegradedQuotaKey = Key('ai_degraded_quota');
const kAiDegradedAiUnavailableKey = Key('ai_degraded_ai_unavailable');
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
  });

  final AiDegradedMode mode;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (mode == AiDegradedMode.ready) {
      return KeyedSubtree(
        key: kAiAffordanceKey,
        child: child ?? const SizedBox.shrink(),
      );
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
        if (child != null) ...[
          const SizedBox(height: 16),
          child!,
        ],
      ],
    );
  }

  static String _messageForMode(AiDegradedMode mode) => switch (mode) {
        AiDegradedMode.nonEnrolled => 'AI is not enabled for this clinic.',
        AiDegradedMode.unreachable => 'AI platform is currently unreachable.',
        AiDegradedMode.quotaExhausted => 'AI quota exhausted. Contact your administrator.',
        AiDegradedMode.aiUnavailable => 'AI is temporarily unavailable.',
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
        AiDegradedMode.installationSuspended => kAiDegradedInstallationSuspendedKey,
        AiDegradedMode.forbiddenCapability => kAiDegradedForbiddenCapabilityKey,
        AiDegradedMode.ready => kAiAffordanceKey,
      };
}
