import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_combined_confirmation.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_confirmation_data.dart';

/// Presents the post-finalize confirmation card in a modal dialog.
class VisitSubmittedDialog {
  VisitSubmittedDialog._();

  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required VisitDetail visit,
    VisitConfirmationKind kind = VisitConfirmationKind.completed,
    DateTime? actionAt,
  }) {
    return AppDialog.show<void>(
      context,
      title: kind.title,
      showHeader: false,
      maxWidth: 560,
      size: AppDialogSize.lg,
      barrierDismissible: true,
      footer: _VisitSubmittedDialogFooter(visit: visit),
      child: _VisitSubmittedDialogBody(visit: visit, kind: kind, actionAt: actionAt),
    );
  }
}

class _VisitSubmittedDialogBody extends ConsumerWidget {
  const _VisitSubmittedDialogBody({required this.visit, required this.kind, this.actionAt});

  final VisitDetail visit;
  final VisitConfirmationKind kind;
  final DateTime? actionAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientAsync = ref.watch(patientDetailProvider(visit.patientId));
    final appointmentAsync = ref.watch(appointmentDetailProvider(visit.appointmentId));
    final branchesAsync = ref.watch(staffAssignableBranchesProvider);

    final patientName = patientAsync.maybeWhen(data: (patient) => patient.fullName, orElse: () => 'Patient');
    final branchName = branchesAsync.maybeWhen(
      data: (branches) =>
          branches.where((branch) => branch.id == visit.branchId).map((branch) => branch.name).firstOrNull ?? 'Branch',
      orElse: () => 'Branch',
    );

    return appointmentAsync.when(
      loading: () => const AppSkeleton(variant: SkeletonVariant.rectangular, height: 340),
      error: (_, _) {
        final fallbackEnd = visit.visitDate.add(const Duration(minutes: 30));
        return VisitSubmittedCombinedConfirmation(
          data: VisitSubmittedConfirmationData.fromVisit(
            visit: visit,
            patientName: patientName,
            branchName: branchName,
            appointmentStart: visit.visitDate,
            appointmentEnd: fallbackEnd,
            kind: kind,
            actionAt: actionAt,
          ),
        );
      },
      data: (appointment) => VisitSubmittedCombinedConfirmation(
        data: VisitSubmittedConfirmationData.fromVisit(
          visit: visit,
          patientName: patientName,
          branchName: branchName,
          appointmentStart: appointment.startTime,
          appointmentEnd: appointment.endTime,
          kind: kind,
          actionAt: actionAt,
        ),
      ),
    );
  }
}

class _VisitSubmittedDialogFooter extends StatelessWidget {
  const _VisitSubmittedDialogFooter({required this.visit});

  final VisitDetail visit;

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
            context.nav.pushAppointmentDetail(visit.appointmentId);
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
