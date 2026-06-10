import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

const _nextDisabledTooltip = 'One or more mandatory fields are empty';

/// Top-right Back / Next controls for the setup wizard.
class SetupWizardNavBar extends StatelessWidget {
  const SetupWizardNavBar({
    this.onBack,
    this.onNext,
    this.showBack = false,
    this.showNext = false,
    this.nextEnabled = false,
    this.isBusy = false,
    super.key,
  });

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final bool showBack;
  final bool showNext;
  final bool nextEnabled;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    if (!showBack && !showNext) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        const Spacer(),
        if (showBack) ...[
          AppButton(label: 'Back', expand: false, onPressed: isBusy ? null : onBack),
          if (showNext) const SizedBox(width: SpacingTokens.sm),
        ],
        if (showNext) _buildNextButton(),
      ],
    );
  }

  Widget _buildNextButton() {
    if (isBusy) {
      return AppButton(label: 'Next', expand: false, isLoading: true, onPressed: null);
    }

    if (nextEnabled) {
      return AppButton(label: 'Next', expand: false, onPressed: onNext);
    }

    return Tooltip(
      message: _nextDisabledTooltip,
      child: AbsorbPointer(child: AppButton(label: 'Next', expand: false, onPressed: null)),
    );
  }
}
