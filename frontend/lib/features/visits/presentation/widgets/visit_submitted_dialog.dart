import 'package:flutter/material.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/visit_submission_confirmation.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_combined_confirmation.dart';

/// Presents the post-finalize confirmation card in a modal dialog.
class VisitSubmittedDialog {
  VisitSubmittedDialog._();

  static Future<void> show(
    BuildContext context, {
    required VisitSubmissionConfirmation confirmation,
    Widget? invoiceSummary,
  }) {
    return AppDialog.show<void>(
      context,
      title: confirmation.kind.title,
      showHeader: false,
      maxWidth: 560,
      size: AppDialogSize.lg,
      barrierDismissible: true,
      footer: _VisitSubmittedDialogFooter(appointmentId: confirmation.appointmentId),
      child: VisitSubmittedCombinedConfirmation(
        confirmation: confirmation,
        invoiceSummary: invoiceSummary,
      ),
    );
  }
}

class _VisitSubmittedDialogFooter extends StatelessWidget {
  const _VisitSubmittedDialogFooter({required this.appointmentId});

  final String appointmentId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 420;
        final viewAppointment = AppButton(
          variant: AppButtonVariant.secondary,
          leadingIcon: const Icon(Icons.event_note_outlined, size: 16),
          onPressed: () {
            Navigator.of(context).pop();
            context.nav.pushAppointmentDetail(appointmentId);
          },
          child: const Text('View appointment'),
        );
        final backToCalendar = AppButton(
          trailingIcon: const Icon(Icons.calendar_month_outlined, size: 16),
          onPressed: () {
            Navigator.of(context).pop();
            context.nav.goAppointmentsCalendar();
          },
          child: const Text('Back to calendar'),
        );

        if (isWide) {
          return Row(children: [viewAppointment, const Spacer(), backToCalendar]);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            backToCalendar,
            const SizedBox(height: AppSpacing.space3),
            viewAppointment,
          ],
        );
      },
    );
  }
}
