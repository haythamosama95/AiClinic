import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
<<<<<<< HEAD
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
=======

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_entry.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_provider.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_resolver.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_view.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/billing/presentation/navigation/visit_billing_route_extra.dart';
>>>>>>> master
import 'package:ai_clinic/features/billing/presentation/providers/visit_billing_flow_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Bill a visit after documentation review (`/billing/visits/:visitId`).
class VisitBillingPage extends ConsumerStatefulWidget {
<<<<<<< HEAD
  const VisitBillingPage({required this.visitId, super.key});

  final String visitId;
=======
  const VisitBillingPage({required this.visitId, this.extra, super.key});

  final String visitId;
  final VisitBillingRouteExtra? extra;
>>>>>>> master

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
<<<<<<< HEAD
    context.nav.goVisitDocument(widget.visitId);
=======
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
>>>>>>> master
  }

  void _onCompleted() {
    if (mounted) {
<<<<<<< HEAD
      context.go(AppRoutes.billingInvoices);
=======
      context.nav.goBillingInvoices();
>>>>>>> master
    }
  }

  @override
  Widget build(BuildContext context) {
    final docAsync = ref.watch(visitDocumentationProvider(widget.visitId));

<<<<<<< HEAD
=======
    if (docAsync.hasError && !docAsync.hasValue) {
      return Center(child: Text(docAsync.error!.toString()));
    }

>>>>>>> master
    return docAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (error, _) => Center(child: Text(error.toString())),
      data: (docState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
<<<<<<< HEAD
            AppPageHeader(
              title: 'Bill this visit',
              description: 'Select services performed, review the invoice, then finalize the visit.',
=======
            const AppPageHeader(
              title: 'Bill this visit',
              description: 'Select services performed, review the invoice, then finalize the visit.',
              breadcrumb: BreadcrumbTrailView(),
>>>>>>> master
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
