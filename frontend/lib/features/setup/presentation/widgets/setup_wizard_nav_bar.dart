import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

const _defaultNextDisabledTooltip = 'One or more mandatory fields are empty';

/// Top-right Back / Next controls for the setup wizard.
class SetupWizardNavBar extends StatelessWidget {
  const SetupWizardNavBar({
    this.onBack,
    this.onNext,
    this.showBack = false,
    this.showNext = false,
    this.nextLabel = 'Next',
    this.nextEnabled = false,
    this.nextDisabledTooltip = _defaultNextDisabledTooltip,
    this.isBusy = false,
    this.embedded = false,
    super.key,
  });

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final bool showBack;
  final bool showNext;
  final String nextLabel;
  final bool nextEnabled;
  final String nextDisabledTooltip;
  final bool isBusy;

  /// When true, omits the leading [Spacer] so the bar can sit on the same row as branding.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    if (!showBack && !showNext) {
      return const SizedBox.shrink();
    }

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showBack) ...[
          AppButton(label: 'Back', expand: false, onPressed: isBusy ? null : onBack),
          if (showNext) const SizedBox(width: SpacingTokens.sm),
        ],
        if (showNext) _buildNextButton(),
      ],
    );

    if (embedded) {
      return controls;
    }

    return Row(children: [const Spacer(), controls]);
  }

  Widget _buildNextButton() {
    if (isBusy) {
      return AppButton(label: nextLabel, expand: false, isLoading: true, onPressed: null);
    }

    if (nextEnabled) {
      return AppButton(label: nextLabel, expand: false, onPressed: onNext);
    }

    return Tooltip(
      message: nextDisabledTooltip,
      child: AbsorbPointer(child: AppButton(label: nextLabel, expand: false, onPressed: null)),
    );
  }
}
