import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Debug-only setup wizard shortcuts (dummy fill, reset installation).
abstract final class SetupDevWidgets {
  const SetupDevWidgets._();

  static Widget panel({
    Key? key,
    required VoidCallback onFillDummy,
    required VoidCallback onResetInstallation,
    bool isBusy = false,
  }) {
    if (!kDebugMode) return const SizedBox.shrink();

    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: SpacingTokens.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'DEV ONLY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: Colors.orange.shade800,
            ),
          ),
          const SizedBox(height: SpacingTokens.xs),
          Wrap(
            spacing: SpacingTokens.sm,
            runSpacing: SpacingTokens.sm,
            alignment: WrapAlignment.center,
            children: [
              AppButton(
                label: 'Fill dummy clinic',
                variant: AppButtonVariant.outline,
                expand: false,
                isLoading: isBusy,
                onPressed: isBusy ? null : onFillDummy,
              ),
              AppButton(
                label: 'Reset installation',
                variant: AppButtonVariant.destructive,
                expand: false,
                isLoading: isBusy,
                onPressed: isBusy ? null : onResetInstallation,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
