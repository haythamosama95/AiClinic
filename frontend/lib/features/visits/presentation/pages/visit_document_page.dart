import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/components/app_step_panel.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_window_facade.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_summary_facade.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_documentation_save_status_badge.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_encounter_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_encounter_step_content.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_unsaved_changes_guard.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

/// Doctor visit documentation workspace (`/visits/:visitId/document`).
class VisitDocumentPage extends ConsumerWidget {
  const VisitDocumentPage({required this.visitId, this.startInEditMode = false, super.key});

  final String visitId;
  final bool startInEditMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessVisitDocumentation(auth)) {
      return const _VisitDocumentPermissionDenied();
    }

    final isDirty = ref.watch(
      visitDocumentationProvider(visitId).select((state) => state.asData?.value.hasUnsavedChanges ?? false),
    );
    final visitAsync = ref.watch(visitDetailViewProvider(visitId));

    return PopScope(
      canPop: !isDirty,
      onPopInvokedWithResult: (didPop, _) => _handlePopInvoked(context, ref, visitId, didPop),
      child: visitAsync.when(
        skipLoadingOnReload: true,
        loading: () => _VisitDocumentLoadingView(visitId: visitId, onExit: () => _requestExit(context)),
        error: (error, _) {
          if (error is RpcFailure && error.code == 'NOT_FOUND') {
            return _VisitDocumentNotFoundView(onBack: () => _requestExit(context));
          }
          return _VisitDocumentErrorView(
            message: error.toString(),
            onBack: () => _requestExit(context),
            onRetry: () => ref.invalidate(visitDetailViewProvider(visitId)),
          );
        },
        data: (view) => _VisitDocumentContentView(
          visit: view.visit,
          startInEditMode: startInEditMode,
          onBack: () => _requestExit(context),
        ),
      ),
    );
  }

  static Future<void> _requestExit(BuildContext context) async {
    final popped = await Navigator.maybePop(context);
    if (!popped && context.mounted) {
      context.nav.goAppointmentsCalendar();
    }
  }

  static Future<void> _handlePopInvoked(BuildContext context, WidgetRef ref, String visitId, bool didPop) async {
    if (didPop) {
      return;
    }

    final decision = await showVisitUnsavedChangesDialog(context);
    if (!context.mounted) {
      return;
    }

    switch (decision) {
      case VisitExitDecision.stay:
        return;
      case VisitExitDecision.discard:
        ref.read(visitDocumentationProvider(visitId).notifier).clearPendingDrafts();
        if (!context.mounted) {
          return;
        }
        await Navigator.of(context).maybePop();
      case VisitExitDecision.save:
        final saved = await ref.read(visitDocumentationProvider(visitId).notifier).saveAll();
        if (saved && context.mounted) {
          await Navigator.of(context).maybePop();
        }
    }
  }
}

class _VisitDocumentContentView extends ConsumerStatefulWidget {
  const _VisitDocumentContentView({required this.visit, required this.onBack, this.startInEditMode = false});

  final VisitDetail visit;
  final VoidCallback onBack;
  final bool startInEditMode;

  @override
  ConsumerState<_VisitDocumentContentView> createState() => _VisitDocumentContentViewState();
}

class _VisitDocumentContentViewState extends ConsumerState<_VisitDocumentContentView> {
  var _openedCompletedVisitSummary = false;
  var _appliedStartInEditMode = false;

  VisitDetail get visit => widget.visit;

  void _ensureStartInEditMode() {
    if (!widget.startInEditMode || _appliedStartInEditMode) {
      return;
    }
    if (ref.read(visitDocumentationProvider(visit.id)).value == null) {
      return;
    }
    _appliedStartInEditMode = true;
    ref.read(visitDocumentationProvider(visit.id).notifier).enterWorkspaceEditMode();
  }

  void _ensureCompletedVisitOpensOnSummary() {
    if (_openedCompletedVisitSummary || visit.status != VisitStatus.completed) {
      return;
    }
    _openedCompletedVisitSummary = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(encounterActivePhaseProvider(visit.id).notifier).setPhase(EncounterPhase.review);
    });
  }

  @override
  Widget build(BuildContext context) {
    _ensureCompletedVisitOpensOnSummary();
    _ensureStartInEditMode();

    final l10n = AppLocalizations.of(context)!;
    final patientSummaryAsync = ref.watch(patientSummaryForVisitProvider(visit.patientId));
    final appointmentWindowAsync = ref.watch(appointmentWindowProvider(visit.appointmentId));
    final activePhase = ref.watch(encounterActivePhaseProvider(visit.id));
    final docAsync = ref.watch(visitDocumentationProvider(visit.id));
    final permissions = ref.watch(permissionServiceProvider);
    final isCompletedVisit = visit.status == VisitStatus.completed;
    final loadingPhase = isCompletedVisit ? EncounterPhase.review : activePhase;

    final patientName = patientSummaryAsync.maybeWhen(
      data: (summary) => summary.fullName,
      orElse: () => l10n.patientSummaryFallbackName,
    );
    final patientAgeLabel = patientSummaryAsync.maybeWhen(data: (summary) => summary.ageLabel, orElse: () => null);
    final appointmentLabel = appointmentWindowAsync.maybeWhen(
      data: (window) => window.breadcrumbLabel,
      orElse: () => l10n.appointmentWindowFallbackLabel,
    );

    return docAsync.when(
      skipLoadingOnReload: true,
      loading: () => _VisitDocumentScaffold(
        visitId: visit.id,
        title: isCompletedVisit ? 'Review visit' : 'Visit documentation',
        description: isCompletedVisit
            ? 'Check documentation for $patientName before finalizing.'
            : 'Document the clinical encounter for this appointment.',
        patientName: l10n.loading,
        appointmentLabel: l10n.appointmentWindowFallbackLabel,
        appointmentId: visit.appointmentId,
        patientAgeLabel: patientAgeLabel,
        currentPhase: loadingPhase,
        showEncounterHeader: !isCompletedVisit,
        onExit: widget.onBack,
        stepBody: const AppSkeleton(variant: SkeletonVariant.rectangular, height: 320),
      ),
      error: (error, _) => _VisitDocumentErrorView(
        message: error.toString(),
        onBack: widget.onBack,
        onRetry: () => ref.invalidate(visitDocumentationProvider(visit.id)),
      ),
      data: (docState) {
        final canEdit = docState.canEditWorkspace(permissions.canEditVisitSoap());
        final phaseNotifier = ref.read(encounterActivePhaseProvider(visit.id).notifier);
        final isReview = activePhase == EncounterPhase.review;

        final stepContent = AppStepPanel(
          stepKey: activePhase.name,
          child: VisitEncounterStepContent(visitId: visit.id, phase: activePhase, canEdit: canEdit),
        );

        final stepBody = _VisitEncounterWorkspaceCard(
          currentPhase: activePhase,
          canGoBack: activePhase.previous != null,
          continueLabel: activePhase == EncounterPhase.plan ? 'Review visit' : 'Continue',
          onBack: () {
            final previous = activePhase.previous;
            if (previous != null) {
              phaseNotifier.setPhase(previous);
            }
          },
          onContinue: () {
            final next = activePhase.next;
            if (next != null) {
              phaseNotifier.setPhase(next);
              return;
            }
            phaseNotifier.setPhase(EncounterPhase.review);
          },
          child: stepContent,
        );

        final pageTitle = isReview ? 'Review visit' : 'Visit documentation';
        final pageDescription = isReview
            ? 'Check documentation for $patientName before finalizing.'
            : 'Document the clinical encounter for this appointment.';

        return _VisitDocumentScaffold(
          visitId: visit.id,
          title: pageTitle,
          description: pageDescription,
          patientName: patientName,
          appointmentLabel: appointmentLabel,
          appointmentId: visit.appointmentId,
          patientAgeLabel: patientAgeLabel,
          currentPhase: activePhase,
          showEncounterHeader: !isReview,
          onPhaseSelected: phaseNotifier.setPhase,
          onExit: widget.onBack,
          stepBody: stepBody,
        );
      },
    );
  }
}

class _VisitDocumentScaffold extends StatelessWidget {
  const _VisitDocumentScaffold({
    required this.visitId,
    required this.title,
    required this.description,
    required this.patientName,
    required this.appointmentLabel,
    required this.appointmentId,
    required this.currentPhase,
    required this.stepBody,
    this.patientAgeLabel,
    this.onPhaseSelected,
    this.onExit,
    this.showEncounterHeader = true,
  });

  final String visitId;
  final String title;
  final String description;
  final String patientName;
  final String? patientAgeLabel;
  final String appointmentLabel;
  final String appointmentId;
  final EncounterPhase currentPhase;
  final ValueChanged<EncounterPhase>? onPhaseSelected;
  final VoidCallback? onExit;
  final Widget stepBody;
  final bool showEncounterHeader;

  static const _headerSideBySideBreakpoint = 960.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final breadcrumb = AppBreadcrumb(
          items: [
            AppBreadcrumbItem(label: 'Calendar', onTap: onExit ?? () => Navigator.maybePop(context)),
            AppBreadcrumbItem(label: appointmentLabel, onTap: () => context.nav.pushAppointmentDetail(appointmentId)),
            AppBreadcrumbItem(label: title),
          ],
        );

        final pageHeader = AppPageHeader(
          title: title,
          description: description,
          breadcrumb: breadcrumb,
          actions: VisitDocumentationSaveStatusBadge(visitId: visitId),
        );

        final encounterSlotWidth = (constraints.maxWidth - AppSpacing.space6) * 2 / 3;

        final encounterHeader = showEncounterHeader
            ? VisitEncounterHeader(
                patientName: patientName,
                patientAgeLabel: patientAgeLabel,
                currentPhase: currentPhase,
                onPhaseSelected: onPhaseSelected,
                isCompact: encounterSlotWidth < VisitEncounterHeader.compactBreakpoint,
              )
            : null;

        final header = encounterHeader == null
            ? pageHeader
            : constraints.maxWidth >= _headerSideBySideBreakpoint
            ? Semantics(
                header: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    breadcrumb,
                    const SizedBox(height: AppSpacing.space4),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _VisitDocumentTitleBlock(
                              visitId: visitId,
                              title: title,
                              description: description,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.space6),
                          Expanded(flex: 2, child: encounterHeader),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  pageHeader,
                  const SizedBox(height: AppSpacing.space6),
                  encounterHeader,
                ],
              );

        final body = stepBody;
        final hasBoundedHeight = constraints.maxHeight.isFinite;

        if (!hasBoundedHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              header,
              const SizedBox(height: AppSpacing.space6),
              body,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: AppSpacing.space6),
            Expanded(child: SingleChildScrollView(child: body)),
          ],
        );
      },
    );
  }
}

class _VisitDocumentTitleBlock extends StatelessWidget {
  const _VisitDocumentTitleBlock({required this.visitId, required this.title, required this.description});

  final String visitId;
  final String title;
  final String description;

  static const _maxDescriptionWidth = 672.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(title, style: AppTypography.h1(context).copyWith(color: colors.textPrimary))),
            const SizedBox(width: AppSpacing.space3),
            VisitDocumentationSaveStatusBadge(visitId: visitId),
          ],
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxDescriptionWidth),
          child: Text(description, style: AppTypography.body(context).copyWith(color: colors.textSecondary)),
        ),
      ],
    );
  }
}

class _VisitEncounterWorkspaceCard extends StatelessWidget {
  const _VisitEncounterWorkspaceCard({
    required this.child,
    required this.currentPhase,
    required this.canGoBack,
    required this.continueLabel,
    required this.onBack,
    required this.onContinue,
  });

  final Widget child;
  final EncounterPhase currentPhase;
  final bool canGoBack;
  final String continueLabel;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final showFooter = currentPhase.isDocumentation;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border.all(color: colors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: elevation.shadows1,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Stack(
          children: [
            const Positioned.fill(child: _WorkspaceGridBackground()),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  child,
                  if (showFooter) ...[
                    const SizedBox(height: AppSpacing.space8),
                    const AppDivider(),
                    const SizedBox(height: AppSpacing.space6),
                    Row(
                      children: [
                        AppButton(
                          variant: AppButtonVariant.secondary,
                          leadingIcon: const Icon(Icons.arrow_back_rounded, size: 16),
                          onPressed: canGoBack ? onBack : null,
                          child: const Text('Back'),
                        ),
                        const Spacer(),
                        AppButton(
                          trailingIcon: const Icon(Icons.arrow_forward_rounded, size: 16),
                          onPressed: onContinue,
                          child: Text(continueLabel),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceGridBackground extends StatelessWidget {
  const _WorkspaceGridBackground();

  @override
  Widget build(BuildContext context) {
    final gridColor = context.appColors.borderSubtle.withValues(alpha: 0.25);

    return IgnorePointer(
      child: ShaderMask(
        shaderCallback: (bounds) => const RadialGradient(
          center: Alignment(-0.4, -1),
          radius: 0.9,
          colors: [Colors.black, Colors.transparent],
          stops: [0.15, 0.65],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: CustomPaint(painter: _WorkspaceGridPainter(color: gridColor)),
      ),
    );
  }
}

class _WorkspaceGridPainter extends CustomPainter {
  const _WorkspaceGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 20.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    for (var x = 0.0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WorkspaceGridPainter oldDelegate) => oldDelegate.color != color;
}

class _VisitDocumentLoadingView extends StatelessWidget {
  const _VisitDocumentLoadingView({required this.visitId, required this.onExit});

  final String visitId;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return _VisitDocumentScaffold(
      visitId: visitId,
      title: 'Visit documentation',
      description: 'Document the clinical encounter for this appointment.',
      patientName: l10n.loading,
      appointmentLabel: l10n.appointmentWindowFallbackLabel,
      appointmentId: visitId,
      currentPhase: EncounterPhase.subjective,
      onExit: onExit,
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
              AppBreadcrumbItem(label: 'Calendar', onTap: onBack),
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
              AppBreadcrumbItem(label: 'Calendar', onTap: onBack),
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
