import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/utils/visit_presentation_formatting.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_review_panel.dart';

/// Visit detail — read-only clinical record with optional edit entry (013 US6).
class VisitDetailPage extends ConsumerWidget {
  const VisitDetailPage({
    required this.visitId,
    super.key,
  });

  final String visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessVisitDetail(auth)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Visit detail',
        description: 'You do not have permission to view this visit.',
      );
    }

    final id = visitId.trim();
    if (id.isEmpty) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.error,
        title: 'Visit not found',
        description: 'A valid visit id is required.',
      );
    }

    final viewAsync = ref.watch(visitDetailViewProvider(id));

    return viewAsync.when(
      loading: () => const RecordDetailPattern(
        title: 'Visit detail',
        body: Center(child: AppSpinner()),
      ),
      error: (error, _) => RecordDetailPattern(
        title: 'Visit detail',
        body: AppErrorState(
          message: error is RpcFailure ? visitMessageForRpc(error) : error.toString(),
          onRetry: () => ref.invalidate(visitDetailViewProvider(id)),
        ),
      ),
      data: (view) {
        if (view.canEditDocumentation) {
          return _EditableVisitDetail(visitId: id, view: view);
        }
        return _ReadOnlyVisitDetail(view: view);
      },
    );
  }
}

class _EditableVisitDetail extends ConsumerWidget {
  const _EditableVisitDetail({required this.visitId, required this.view});

  final String visitId;
  final VisitDetailViewState view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docAsync = ref.watch(visitDocumentationProvider(visitId));

    return docAsync.when(
      loading: () => RecordDetailPattern(
        title: 'Visit · ${view.visit.doctorName}',
        body: const Center(child: AppSpinner()),
      ),
      error: (error, _) => RecordDetailPattern(
        title: 'Visit detail',
        body: AppErrorState(
          message: error is RpcFailure ? visitMessageForRpc(error) : error.toString(),
          onRetry: () => ref.invalidate(visitDocumentationProvider(visitId)),
        ),
      ),
      data: (docState) => _VisitDetailBody(
        visitId: visitId,
        view: view,
        docState: docState,
        canEditInline: view.visit.status != VisitStatus.completed,
      ),
    );
  }
}

class _ReadOnlyVisitDetail extends StatelessWidget {
  const _ReadOnlyVisitDetail({required this.view});

  final VisitDetailViewState view;

  @override
  Widget build(BuildContext context) {
    return _VisitDetailBody(
      visitId: view.visit.id,
      view: view,
      canEditInline: false,
    );
  }
}

class _VisitDetailBody extends ConsumerWidget {
  const _VisitDetailBody({
    required this.visitId,
    required this.view,
    this.docState,
    required this.canEditInline,
  });

  final String visitId;
  final VisitDetailViewState view;
  final VisitDocumentationState? docState;
  final bool canEditInline;

  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.patients);
  }

  void _openDocumentation(BuildContext context, {bool startEditing = false}) {
    context.go(AppRoutes.visitDocument(visitId, startEditing: startEditing));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = docState?.visit ?? view.visit;
    final status = visit.status;

    return RecordDetailPattern(
      title: 'Visit · ${visit.doctorName}',
      description:
          '${VisitPresentationFormatting.visitDate.format(visit.visitDate)} · ${VisitPresentationFormatting.displayVisitId(visit.id)}',
      statusBadge: AppBadge(
        color: status == VisitStatus.completed ? AppBadgeColor.success : AppBadgeColor.info,
        child: Text(VisitPresentationFormatting.statusLabel(status)),
      ),
      actions: Wrap(
        spacing: AppSpacing.s2,
        runSpacing: AppSpacing.s2,
        children: [
          AppButton(
            label: 'Back',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.sm,
            onPressed: () => _goBack(context),
          ),
          if (view.canEditDocumentation)
            AppButton(
              label: status == VisitStatus.completed ? 'Edit documentation' : 'Open workspace',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              leadingIcon: LucideIcons.fileText,
              onPressed: () => _openDocumentation(
                context,
                startEditing: status == VisitStatus.completed,
              ),
            ),
        ],
      ),
      body: AppScrollArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!view.hasBranchAccess) ...[
                const AppAlert(
                  variant: AppAlertVariant.warning,
                  title: 'This visit belongs to a branch you are not assigned to.',
                  body: 'Clinical documentation is read-only.',
                ),
                const SizedBox(height: AppSpacing.s4),
              ],
              AppDescriptionList(
                items: [
                  AppDescriptionItem(
                    label: 'Doctor',
                    value: Text(visit.doctorName),
                  ),
                  AppDescriptionItem(
                    label: 'Visit date',
                    value: Text(VisitPresentationFormatting.visitDate.format(visit.visitDate)),
                    tabular: true,
                  ),
                  if (visit.visitType != null && visit.visitType!.trim().isNotEmpty)
                    AppDescriptionItem(
                      label: 'Visit type',
                      value: Text(visit.visitType!),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.s6),
              EncounterReviewPanel(
                visitId: visitId,
                visit: visit,
                state: docState,
                canEdit: canEditInline && view.canEditDocumentation,
                canUploadAttachments: view.canUploadAttachments,
                onEditPhase: canEditInline && view.canEditDocumentation
                    ? (_) => _openDocumentation(context, startEditing: false)
                    : view.canEditDocumentation
                    ? (_) => _openDocumentation(context, startEditing: true)
                    : null,
              ),
            ],
          ),
        ),
    );
  }
}
