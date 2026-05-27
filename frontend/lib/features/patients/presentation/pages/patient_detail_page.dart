import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/utils/date_format_utils.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_exceptions.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_archive_dialog.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_visits_placeholder.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

void _leavePatientDetail(BuildContext context) {
  if (context.nav.canPop()) {
    context.nav.pop();
  } else {
    context.nav.goPatients();
  }
}

/// Patient profile detail with medical-history placeholder (US3).
class PatientDetailPage extends ConsumerWidget {
  const PatientDetailPage({required this.patientId, super.key});

  final String? patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    final canView = permissions.canViewPatients();
    final canEdit = permissions.canEditPatients();
    final canDelete = permissions.canDeletePatients();
    final id = patientId?.trim() ?? '';

    if (!canView) {
      return _PatientScaffold(
        title: 'Patient',
        body: const Center(
          key: Key('patient_detail_permission_denied'),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to view patients.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (id.isEmpty) {
      return _PatientScaffold(
        title: 'Patient',
        body: const Center(
          key: Key('patient_detail_invalid_id'),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('A valid patient id is required.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final detailAsync = ref.watch(patientDetailProvider(id));

    return _PatientScaffold(
      title: detailAsync.maybeWhen(data: (detail) => detail.fullName, orElse: () => 'Patient'),
      actions: detailAsync.maybeWhen(
        data: (detail) => _PatientDetailActions(detail: detail, patientId: id, canEdit: canEdit, canDelete: canDelete),
        orElse: () => null,
      ),
      body: detailAsync.when(
        loading: () => const Center(key: Key('patient_detail_loading'), child: CircularProgressIndicator()),
        error: (error, _) => _PatientDetailError(
          error: error,
          message: error.toString(),
          onRetry: () => ref.invalidate(patientDetailProvider(id)),
        ),
        data: (detail) => _PatientDetailBody(detail: detail),
      ),
    );
  }
}

class _PatientScaffold extends StatelessWidget {
  const _PatientScaffold({required this.title, required this.body, this.actions});

  final String title;
  final Widget body;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(tooltip: 'Go back', icon: const Icon(Icons.arrow_back), onPressed: () => _leavePatientDetail(context)),
        actions: actions == null ? null : [actions!],
      ),
      body: body,
    );
  }
}

class _PatientDetailActions extends ConsumerWidget {
  const _PatientDetailActions({
    required this.detail,
    required this.patientId,
    required this.canEdit,
    required this.canDelete,
  });

  final PatientDetail detail;
  final String patientId;
  final bool canEdit;
  final bool canDelete;

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final confirmed = await PatientArchiveDialog.show(context, patientId: patientId, patientName: detail.fullName);
    if (confirmed != true || !context.mounted) {
      return;
    }

    ref.invalidate(patientListProvider);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Patient archived.')));
    if (context.nav.canPop()) {
      context.nav.pop();
    } else {
      context.nav.goPatients();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canEdit)
          IconButton(
            key: const Key('patient_detail_edit'),
            tooltip: 'Edit patient',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.nav.pushPatientEdit(patientId),
          ),
        if (canDelete)
          IconButton(
            key: const Key('patient_detail_archive'),
            tooltip: 'Archive patient',
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => _archive(context, ref),
          ),
      ],
    );
  }
}

class _PatientDetailError extends StatelessWidget {
  const _PatientDetailError({required this.error, required this.message, required this.onRetry});

  final Object error;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isArchived = error is PatientArchivedException;

    return Center(
      key: Key(isArchived ? 'patient_detail_archived' : 'patient_detail_error'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (isArchived)
              FilledButton(onPressed: () => _leavePatientDetail(context), child: const Text('Back to patients'))
            else ...[
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
              TextButton(onPressed: () => _leavePatientDetail(context), child: const Text('Back to patients')),
            ],
          ],
        ),
      ),
    );
  }
}

class _PatientDetailBody extends StatelessWidget {
  const _PatientDetailBody({required this.detail});

  final PatientDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      key: const Key('patient_detail_body'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Profile', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          key: const Key('patient_detail_profile'),
          child: Column(
            children: [
              _ProfileRow(label: 'Full name', value: detail.fullName),
              _ProfileRow(label: 'Mobile number', value: detail.phone ?? '—'),
              _ProfileRow(label: 'Date of birth', value: formatDate(detail.dateOfBirth)),
              _ProfileRow(label: 'Gender', value: detail.gender?.label ?? '—'),
              _ProfileRow(label: 'Marital status', value: detail.maritalStatus?.label ?? '—'),
              _ProfileRow(label: 'Registering branch', value: detail.branchName),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Medical history', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          key: const Key('patient_detail_medical_history'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Notes', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  (detail.notes == null || detail.notes!.isEmpty) ? 'No notes recorded.' : detail.notes!,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const PatientVisitsPlaceholder(),
        const SizedBox(height: 24),
        Text('Record history', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          key: const Key('patient_detail_audit'),
          child: Column(
            children: [
              _ProfileRow(label: 'Created', value: formatDateTime(detail.createdAt)),
              _ProfileRow(label: 'Last updated', value: formatDateTime(detail.updatedAt)),
              if (detail.createdByDisplay != null) _ProfileRow(label: 'Registered by', value: detail.createdByDisplay!),
            ],
          ),
        ),
      ],
    );
  }

}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 160, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyLarge)),
        ],
      ),
    );
  }
}
