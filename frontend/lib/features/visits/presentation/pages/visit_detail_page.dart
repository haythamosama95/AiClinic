import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/feedback/app_full_page_loading.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_review.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_detail_actions.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Visit detail — clinical chart workspace with inline editing when permitted (013 US6).
class VisitDetailPage extends ConsumerWidget {
  const VisitDetailPage({required this.visitId, super.key});

  final String? visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = visitId?.trim();
    if (id == null || id.isEmpty) {
      return const _VisitNotFound(message: 'Visit not found.');
    }

    final viewAsync = ref.watch(visitDetailViewProvider(id));

    return viewAsync.when(
      loading: () => const AppFullPageLoading(message: 'Loading visit…'),
      error: (error, _) => _VisitDetailError(
        message: error is RpcFailure ? visitMessageForRpc(error) : error.toString(),
        onRetry: () => ref.invalidate(visitDetailViewProvider(id)),
        onBack: () => _goBack(context),
      ),
      data: (view) {
        if (view.canEditDocumentation) {
          return _EditableVisitDetailPage(visitId: id, view: view, onBack: () => _goBack(context));
        }
        return _ReadOnlyVisitDetailPage(view: view, onBack: () => _goBack(context));
      },
    );
  }

  static void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.patients);
  }
}

class _EditableVisitDetailPage extends ConsumerWidget {
  const _EditableVisitDetailPage({required this.visitId, required this.view, required this.onBack});

  final String visitId;
  final VisitDetailViewState view;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docAsync = ref.watch(visitDocumentationProvider(visitId));

    return docAsync.when(
      loading: () => const AppFullPageLoading(message: 'Loading visit…'),
      error: (error, _) => _VisitDetailError(
        message: error is RpcFailure ? visitMessageForRpc(error) : error.toString(),
        onRetry: () => ref.invalidate(visitDocumentationProvider(visitId)),
        onBack: onBack,
      ),
      data: (docState) => VisitPageShell(
        hideTopBar: true,
        onBack: onBack,
        body: _VisitDetailBody(
          visitId: visitId,
          visit: docState.visit,
          state: docState,
          canEdit: view.visit.status != VisitStatus.completed,
          hasEditPermission: view.canEditDocumentation,
          hasBranchAccess: view.hasBranchAccess,
          canUploadAttachments: view.canUploadAttachments,
          onRefresh: () => ref.read(visitDocumentationProvider(visitId).notifier).refreshVisitPreservingDraft(),
          onBack: onBack,
          onEditDocumentation: () =>
              context.go(AppRoutes.visitDocument(visitId, startEditing: view.visit.status == VisitStatus.completed)),
        ),
      ),
    );
  }
}

class _ReadOnlyVisitDetailPage extends StatelessWidget {
  const _ReadOnlyVisitDetailPage({required this.view, required this.onBack});

  final VisitDetailViewState view;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return VisitPageShell(
      hideTopBar: true,
      onBack: onBack,
      body: _VisitDetailBody(
        visitId: view.visit.id,
        visit: view.visit,
        canEdit: false,
        hasEditPermission: view.canEditDocumentation,
        hasBranchAccess: view.hasBranchAccess,
        canUploadAttachments: false,
        onRefresh: () {},
        onBack: onBack,
        onEditDocumentation: view.canEditDocumentation
            ? () => context.go(AppRoutes.visitDocument(view.visit.id, startEditing: true))
            : null,
      ),
    );
  }
}

class _VisitDetailBody extends ConsumerWidget {
  const _VisitDetailBody({
    required this.visitId,
    required this.visit,
    required this.canEdit,
    required this.hasEditPermission,
    required this.hasBranchAccess,
    required this.canUploadAttachments,
    required this.onRefresh,
    required this.onBack,
    this.state,
    this.onEditDocumentation,
  });

  final String visitId;
  final VisitDetail visit;
  final bool canEdit;
  final bool hasEditPermission;
  final bool hasBranchAccess;
  final bool canUploadAttachments;
  final VoidCallback onRefresh;
  final VoidCallback onBack;
  final VisitDocumentationState? state;
  final VoidCallback? onEditDocumentation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trailing = visit.status == VisitStatus.completed
        ? VisitDetailActions(visitId: visitId, status: visit.status, canEditDocumentation: hasEditPermission)
        : null;

    return Column(
      key: const Key('visit_detail_body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncounterHeader(
          visit: visit,
          onBack: onBack,
          onEdit: hasEditPermission && onEditDocumentation != null ? onEditDocumentation : null,
          trailing: trailing,
        ),
        const SizedBox(height: VisitPageTokens.sectionGap),
        if (!hasBranchAccess) ...[
          const AppAlert(
            key: Key('visit_branch_access_denied_banner'),
            title: 'This visit belongs to a branch you are not assigned to.',
            subtitle: 'Clinical documentation is read-only.',
            icon: Icon(Icons.lock_outlined),
          ),
          const SizedBox(height: VisitPageTokens.sectionGap),
        ],
        EncounterReview(
          visitId: visitId,
          visit: visit,
          state: state,
          canEdit: canEdit,
          canUploadAttachments: canUploadAttachments,
          onRefresh: onRefresh,
          onEditPhase: canEdit && onEditDocumentation != null ? (_) => onEditDocumentation!() : null,
        ),
      ],
    );
  }
}

class _VisitDetailError extends StatelessWidget {
  const _VisitDetailError({required this.message, required this.onRetry, required this.onBack});

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return VisitPageShell(
      onBack: onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          AppAlert(title: message, variant: AppAlertVariant.destructive),
          const SizedBox(height: SpacingTokens.md),
          AppButton(label: 'Retry', onPressed: onRetry),
          const Spacer(),
        ],
      ),
    );
  }
}

class _VisitNotFound extends StatelessWidget {
  const _VisitNotFound({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message));
  }
}
