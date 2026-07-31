import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_entry.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_provider.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_resolver.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_view.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/billing/presentation/navigation/visit_billing_route_extra.dart';
import 'package:ai_clinic/features/billing/presentation/providers/visit_billing_flow_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Bill a visit after documentation review (`/billing/visits/:visitId`).
class VisitBillingPage extends ConsumerStatefulWidget {
  const VisitBillingPage({required this.visitId, this.extra, super.key});

  final String visitId;
  final VisitBillingRouteExtra? extra;

  @override
  ConsumerState<VisitBillingPage> createState() => _VisitBillingPageState();
}

class _VisitBillingPageState extends ConsumerState<VisitBillingPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(visitBillingFlowProvider(widget.visitId).notifier).beginBilling();
      }
    });
  }

  void _backToReview() {
    ref.read(visitBillingFlowProvider(widget.visitId).notifier).reset();
    final currentTrail = ref.read(breadcrumbTrailProvider);
    final visitDocEntry = currentTrail.entries
        .where((entry) => entry.id.startsWith('visit-doc:'))
        .toList(growable: false);
    final BreadcrumbTrail trail;
    if (visitDocEntry.isNotEmpty) {
      final index = currentTrail.entries.indexOf(visitDocEntry.last);
      trail = BreadcrumbTrail(currentTrail.entries.sublist(0, index + 1));
    } else {
      trail = BreadcrumbTrailResolver.inheritFrom(context).append(BreadcrumbEntries.visitDocument(widget.visitId));
    }
    context.nav.goVisitDocument(widget.visitId, trail: trail);
  }

  void _onCompleted() {
    if (mounted) {
      context.nav.goBillingInvoices();
    }
  }

  @override
  Widget build(BuildContext context) {
    final docAsync = ref.watch(visitDocumentationProvider(widget.visitId));

    if (docAsync.hasError && !docAsync.hasValue) {
      return Center(child: Text(docAsync.error!.toString()));
    }

    return docAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (error, _) => Center(child: Text(error.toString())),
      data: (docState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppPageHeader(
              title: 'Bill this visit',
              description: 'Select services performed, review the invoice, then finalize the visit.',
              breadcrumb: BreadcrumbTrailView(),
            ),
            const SizedBox(height: AppSpacing.space5),
            Expanded(
              child: VisitBillingFlow(
                visitId: widget.visitId,
                onBackToReview: _backToReview,
                onCompleted: _onCompleted,
              ),
            ),
          ],
        );
      },
    );
  }
}
