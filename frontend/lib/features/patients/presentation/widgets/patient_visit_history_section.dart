import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/data/paginated_list_notifier.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_visit_history_provider.dart';
import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';

/// Patient profile visit history with pagination and permission-aware detail access (V1-5 US6).
class PatientVisitHistorySection extends ConsumerWidget {
  const PatientVisitHistorySection({required this.patientId, super.key});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = patientId.trim();
    if (id.isEmpty) {
      return const SizedBox.shrink();
    }

    final permissions = ref.watch(permissionServiceProvider);
    final canOpenDetail = permissions.canViewVisitClinicalDetail();
    final canEditVisit = permissions.canEditVisitSoap();
    final historyAsync = ref.watch(patientVisitHistoryProvider(id));

    return Card(
      key: const Key('patient_visit_history_section'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.event_note_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text('Visit history', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            historyAsync.when(
              loading: () => const Center(
                key: Key('patient_visit_history_loading'),
                child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
              ),
              error: (error, _) => _HistoryError(
                message: error.toString(),
                onRetry: () => ref.invalidate(patientVisitHistoryProvider(id)),
              ),
              data: (page) =>
                  _HistoryBody(patientId: id, page: page, canOpenDetail: canOpenDetail, canEditVisit: canEditVisit),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('patient_visit_history_error'),
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

class _HistoryBody extends ConsumerWidget {
  const _HistoryBody({
    required this.patientId,
    required this.page,
    required this.canOpenDetail,
    required this.canEditVisit,
  });

  final String patientId;
  final PaginatedList<VisitListItem> page;
  final bool canOpenDetail;
  final bool canEditVisit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (page.items.isEmpty) {
      return Text(
        'No visits recorded yet.',
        key: const Key('patient_visit_history_empty'),
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    final notifier = ref.read(patientVisitHistoryProvider(patientId).notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!canOpenDetail)
          Text(
            'Visit dates and doctors are shown below. Clinical documentation requires visit permissions.',
            key: const Key('patient_visit_history_metadata_only'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        if (!canOpenDetail) const SizedBox(height: 8),
        ...page.items.map(
          (item) => _VisitHistoryRow(
            item: item,
            canOpenDetail: canOpenDetail,
            canEditVisit: canEditVisit,
            onOpenDetail: canOpenDetail ? () => context.nav.pushVisitDetail(item.id) : null,
            onOpenDocument: canEditVisit ? () => context.nav.pushVisitDocument(item.id) : null,
          ),
        ),
        if (page.loadMoreError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Failed to load more visits.'),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: notifier.loadMore, child: const Text('Retry')),
                ],
              ),
            ),
          )
        else if (page.hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: page.isLoadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      key: const Key('patient_visit_history_load_more'),
                      onPressed: notifier.loadMore,
                      child: Text('Load more (${page.items.length} of ${page.totalCount})'),
                    ),
            ),
          ),
      ],
    );
  }
}

class _VisitHistoryRow extends StatelessWidget {
  const _VisitHistoryRow({
    required this.item,
    required this.canOpenDetail,
    required this.canEditVisit,
    this.onOpenDetail,
    this.onOpenDocument,
  });

  final VisitListItem item;
  final bool canOpenDetail;
  final bool canEditVisit;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onOpenDocument;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat.yMMMd().format(item.visitDate.toLocal());
    final subtitle = '${item.doctorName} · ${item.branchName} · ${item.status.label}';

    if (canOpenDetail && onOpenDetail != null) {
      return ListTile(
        key: Key('patient_visit_history_row_${item.id}'),
        contentPadding: EdgeInsets.zero,
        title: Text(dateLabel),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canEditVisit && onOpenDocument != null)
              IconButton(
                key: Key('patient_visit_history_edit_${item.id}'),
                icon: const Icon(Icons.edit_note_outlined),
                tooltip: 'Edit visit',
                onPressed: onOpenDocument,
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onOpenDetail,
      );
    }

    return Padding(
      key: Key('patient_visit_history_row_${item.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dateLabel, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
