import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/patients/application/patient_rpc_messages.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_detail_overview_tab.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_detail_visits_tab.dart';

/// Full patient profile page loaded via `get_patient`.
class PatientDetailPage extends ConsumerStatefulWidget {
  const PatientDetailPage({
    required this.patientId,
    this.preview,
    super.key,
  });

  final String patientId;

  /// Optional list-row preview while the profile loads.
  final PatientListItem? preview;

  @override
  ConsumerState<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends ConsumerState<PatientDetailPage> {
  static const _tabOverview = 'overview';
  static const _tabVisits = 'visits';
  static const _tabBilling = 'billing';

  var _selectedTabId = _tabOverview;
  var _isDeleting = false;

  void _goBack() {
    context.nav.popOrHome();
  }

  Future<void> _confirmDelete(PatientDetail detail) async {
    final name = detail.fullName.trim();
    final message = name.isEmpty
        ? 'This patient will be archived and removed from active lists. Historical records stay linked.'
        : '$name will be archived and removed from active lists. Historical records stay linked.';

    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Delete patient?',
      message: message,
      confirmLabel: 'Delete patient',
      destructive: true,
      loading: _isDeleting,
    );

    if (!confirmed || !mounted) {
      return;
    }
    await _deletePatient(detail.id);
  }

  Future<void> _deletePatient(String patientId) async {
    if (_isDeleting) {
      return;
    }

    setState(() => _isDeleting = true);
    try {
      await ref.read(archivePatientUseCaseProvider)(patientId);
      if (!mounted) {
        return;
      }
      ref.invalidate(patientListProvider);
      ref.showAppToast(message: 'Patient deleted.', variant: AppToastVariant.success);
      _goBack();
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isDeleting = false);
      ref.showAppToast(
        message: patientMessageForRpc(error),
        variant: AppToastVariant.danger,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isDeleting = false);
      ref.showAppToast(
        message: 'Unable to delete patient. Try again.',
        variant: AppToastVariant.danger,
      );
    }
  }

  Widget _buildBody(PatientDetail detail) {
    return switch (_selectedTabId) {
      _tabVisits => PatientDetailVisitsTab(detail: detail),
      _tabBilling => PatientDetailBillingTab(patientId: detail.id),
      _ => PatientDetailOverviewTab(detail: detail),
    };
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessPatientDetail(auth)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Patient detail',
        description: 'You do not have permission to view this patient.',
      );
    }

    final detailAsync = ref.watch(patientDetailProvider(widget.patientId));
    final canEdit = AuthRouteGuard.canAccessPatientEdit(auth);
    final canDelete = AuthRouteGuard.canAccessPatientDelete(auth);

    return detailAsync.when(
      skipLoadingOnReload: true,
      loading: () => RecordDetailPattern(
        title: widget.preview?.fullName ?? 'Patient detail',
        description: widget.preview == null
            ? null
            : 'MRN · ${PatientPresentationFormatting.displayId(widget.preview!.id)}',
        body: const Center(child: AppSpinner()),
      ),
      error: (error, _) => RecordDetailPattern(
        title: 'Patient detail',
        body: AppErrorState(
          message: error.toString(),
          onRetry: () => ref.invalidate(patientDetailProvider(widget.patientId)),
        ),
      ),
      data: (detail) => RecordDetailPattern(
        title: detail.fullName,
        description: 'MRN · ${PatientPresentationFormatting.displayId(detail.id)} · ${detail.branchName}',
        statusBadge: const AppBadge(
          color: AppBadgeColor.success,
          child: Text('Active'),
        ),
        actions: Wrap(
          spacing: AppSpacing.s2,
          runSpacing: AppSpacing.s2,
          children: [
            if (canEdit)
              AppButton(
                label: 'Edit patient',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                leadingIcon: LucideIcons.pencil,
                onPressed: () => context.nav.goPatientEdit(detail.id),
              ),
            if (canDelete)
              AppButton(
                label: 'Delete patient',
                variant: AppButtonVariant.danger,
                size: AppButtonSize.sm,
                leadingIcon: LucideIcons.trash2,
                loading: _isDeleting,
                onPressed: _isDeleting ? null : () => _confirmDelete(detail),
              ),
          ],
        ),
        tabItems: const [
          AppTabItem(id: _tabOverview, label: 'Overview'),
          AppTabItem(id: _tabVisits, label: 'Visits'),
          AppTabItem(id: _tabBilling, label: 'Billing'),
        ],
        selectedTabId: _selectedTabId,
        onTabChanged: (tabId) => setState(() => _selectedTabId = tabId),
        tabsSemanticLabel: 'Patient sections',
        body: _buildBody(detail),
      ),
    );
  }
}
