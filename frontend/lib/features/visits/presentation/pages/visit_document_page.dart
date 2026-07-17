import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/components/app_step_panel.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_encounter_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_encounter_step_placeholder.dart';

/// Doctor visit documentation workspace (`/visits/:visitId/document`).
class VisitDocumentPage extends ConsumerWidget {
  const VisitDocumentPage({required this.visitId, super.key});

  final String visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessVisitDocumentation(auth)) {
      return const _VisitDocumentPermissionDenied();
    }

    final visitAsync = ref.watch(visitDetailViewProvider(visitId));

    return visitAsync.when(
      skipLoadingOnReload: true,
      loading: () => _VisitDocumentLoadingView(visitId: visitId),
      error: (error, _) {
        if (error is RpcFailure && error.code == 'NOT_FOUND') {
          return _VisitDocumentNotFoundView(onBack: () => _goBack(context));
        }
        return _VisitDocumentErrorView(
          message: error.toString(),
          onBack: () => _goBack(context),
          onRetry: () => ref.invalidate(visitDetailViewProvider(visitId)),
        );
      },
      data: (view) => _VisitDocumentContentView(visit: view.visit, onBack: () => _goBack(context)),
    );
  }

  static void _goBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.nav.goAppointmentsCalendar();
  }
}

class _VisitDocumentContentView extends ConsumerWidget {
  const _VisitDocumentContentView({required this.visit, required this.onBack});

  final VisitDetail visit;
  final VoidCallback onBack;

  static final _appointmentDateFormat = DateFormat('MMM d, yyyy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientAsync = ref.watch(patientDetailProvider(visit.patientId));
    final appointmentAsync = ref.watch(appointmentDetailProvider(visit.appointmentId));
    final activePhase = ref.watch(encounterActivePhaseProvider(visit.id));

    final patientName = patientAsync.maybeWhen(data: (patient) => patient.fullName, orElse: () => 'Patient');
    final patientAgeLabel = patientAsync.maybeWhen(data: _patientAgeLabel, orElse: () => null);
    final appointmentLabel = appointmentAsync.maybeWhen(
      data: (appointment) => _appointmentBreadcrumbLabel(appointment),
      orElse: () => 'Appointment',
    );

    return _VisitDocumentScaffold(
      patientName: patientName,
      appointmentLabel: appointmentLabel,
      appointmentId: visit.appointmentId,
      patientAgeLabel: patientAgeLabel,
      currentPhase: activePhase,
      onPhaseSelected: (phase) => ref.read(encounterActivePhaseProvider(visit.id).notifier).setPhase(phase),
      stepBody: AppStepPanel(
        stepKey: activePhase.name,
        child: VisitEncounterStepPlaceholder(phase: activePhase),
      ),
    );
  }

  static String? _patientAgeLabel(PatientDetail patient) {
    final age = PatientPresentationFormatting.ageYears(patient.dateOfBirth);
    if (age == null) {
      return null;
    }
    return '$age years old';
  }

  static String _appointmentBreadcrumbLabel(AppointmentDetail appointment) {
    final date = _appointmentDateFormat.format(appointment.startTime.toLocal());
    return '${appointment.patientName} · $date';
  }
}

class _VisitDocumentScaffold extends StatelessWidget {
  const _VisitDocumentScaffold({
    required this.patientName,
    required this.appointmentLabel,
    required this.appointmentId,
    required this.currentPhase,
    required this.stepBody,
    this.patientAgeLabel,
    this.onPhaseSelected,
  });

  final String patientName;
  final String? patientAgeLabel;
  final String appointmentLabel;
  final String appointmentId;
  final EncounterPhase currentPhase;
  final ValueChanged<EncounterPhase>? onPhaseSelected;
  final Widget stepBody;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppPageHeader(
              title: 'Visit documentation',
              description: 'Document the clinical encounter for this appointment.',
              breadcrumb: AppBreadcrumb(
                items: [
                  AppBreadcrumbItem(label: 'Calendar', onTap: () => context.nav.goAppointmentsCalendar()),
                  AppBreadcrumbItem(
                    label: appointmentLabel,
                    onTap: () => context.nav.pushAppointmentDetail(appointmentId),
                  ),
                  const AppBreadcrumbItem(label: 'Visit documentation'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space6),
            VisitEncounterHeader(
              patientName: patientName,
              patientAgeLabel: patientAgeLabel,
              currentPhase: currentPhase,
              onPhaseSelected: onPhaseSelected,
            ),
            const SizedBox(height: AppSpacing.space6),
          ],
        );

        final body = stepBody;
        final hasBoundedHeight = constraints.maxHeight.isFinite;

        if (!hasBoundedHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [header, body],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(child: SingleChildScrollView(child: body)),
          ],
        );
      },
    );
  }
}

class _VisitDocumentLoadingView extends StatelessWidget {
  const _VisitDocumentLoadingView({required this.visitId});

  final String visitId;

  @override
  Widget build(BuildContext context) {
    return _VisitDocumentScaffold(
      patientName: 'Loading…',
      appointmentLabel: 'Appointment',
      appointmentId: visitId,
      currentPhase: EncounterPhase.subjective,
      stepBody: const AppSkeleton(variant: SkeletonVariant.rectangular, height: 240),
    );
  }
}

class _VisitDocumentErrorView extends StatelessWidget {
  const _VisitDocumentErrorView({required this.message, required this.onBack, required this.onRetry});

  final String message;
  final VoidCallback onBack;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPageHeader(
          title: 'Visit documentation',
          breadcrumb: AppBreadcrumb(
            items: [
              AppBreadcrumbItem(label: 'Calendar', onTap: () => context.nav.goAppointmentsCalendar()),
              const AppBreadcrumbItem(label: 'Visit documentation'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space8),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 40, color: colors.actionDanger),
                  const SizedBox(height: AppSpacing.space4),
                  Text('Could not load visit', style: AppTypography.h3(context)),
                  const SizedBox(height: AppSpacing.space2),
                  Text(
                    message,
                    style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.space6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppButton(variant: AppButtonVariant.secondary, onPressed: onBack, child: const Text('Go back')),
                      const SizedBox(width: AppSpacing.space3),
                      AppButton(onPressed: onRetry, child: const Text('Retry')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VisitDocumentNotFoundView extends StatelessWidget {
  const _VisitDocumentNotFoundView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPageHeader(
          title: 'Visit not found',
          breadcrumb: AppBreadcrumb(
            items: [
              AppBreadcrumbItem(label: 'Calendar', onTap: () => context.nav.goAppointmentsCalendar()),
              const AppBreadcrumbItem(label: 'Visit documentation'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space8),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Visit not found', style: AppTypography.h3(context)),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  'This visit may have been removed or you may not have access.',
                  style: AppTypography.body(context).copyWith(color: context.appColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.space6),
                AppButton(variant: AppButtonVariant.secondary, onPressed: onBack, child: const Text('Go back')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VisitDocumentPermissionDenied extends StatelessWidget {
  const _VisitDocumentPermissionDenied();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppPageHeader(title: 'Visit documentation'),
        const SizedBox(height: AppSpacing.space8),
        Expanded(
          child: Center(
            child: Text(
              'You do not have permission to document visits.',
              style: AppTypography.body(context).copyWith(color: context.appColors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}
