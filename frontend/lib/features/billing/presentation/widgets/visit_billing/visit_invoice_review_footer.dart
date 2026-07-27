import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Action bar for the visit-billing invoice review step.
class VisitInvoiceReviewFooter extends StatelessWidget {
  const VisitInvoiceReviewFooter({
    required this.onBack,
    required this.onFinalize,
    required this.isSubmitting,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback? onFinalize;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 640;
        final backButton = AppButton(
          variant: AppButtonVariant.secondary,
          leadingIcon: const Icon(Icons.arrow_back_rounded, size: 16),
          onPressed: onBack,
          child: const Text('Edit services'),
        );
        final finalizeButton = AppButton(
          loading: isSubmitting,
          trailingIcon: const Icon(
            Icons.check_circle_outline_rounded,
            size: 16,
          ),
          onPressed: onFinalize,
          child: const Text('Finalize visit & invoice'),
        );

        if (isWide) {
          return Row(children: [backButton, const Spacer(), finalizeButton]);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            finalizeButton,
            const SizedBox(height: AppSpacing.space3),
            backButton,
          ],
        );
      },
    );
  }
}
