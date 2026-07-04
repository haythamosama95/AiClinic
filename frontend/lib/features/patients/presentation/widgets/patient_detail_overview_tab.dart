import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_visit_document.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_history_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';

/// Overview tab — demographics, notes, and documents.
class PatientDetailOverviewTab extends ConsumerStatefulWidget {
  const PatientDetailOverviewTab({required this.detail, super.key});

  final PatientDetail detail;

  @override
  ConsumerState<PatientDetailOverviewTab> createState() => _PatientDetailOverviewTabState();
}

class _PatientDetailOverviewTabState extends ConsumerState<PatientDetailOverviewTab> {
  late final TextEditingController _notesController;
  var _notesDirty = false;
  var _isSavingNotes = false;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.detail.notes ?? '');
  }

  @override
  void didUpdateWidget(covariant PatientDetailOverviewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.id != widget.detail.id) {
      _notesController.text = widget.detail.notes ?? '';
      _notesDirty = false;
      return;
    }
    if (!_notesDirty && oldWidget.detail.notes != widget.detail.notes) {
      _notesController.text = widget.detail.notes ?? '';
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  bool get _canEditNotes => AuthRouteGuard.canAccessPatientEdit(ref.read(authSessionProvider));

  Future<void> _saveNotes() async {
    if (_isSavingNotes || !_canEditNotes) {
      return;
    }

    setState(() => _isSavingNotes = true);
    try {
      final notes = _notesController.text.trim();
      await ref.read(updatePatientUseCaseProvider)(
        UpdatePatientInput(
          patientId: widget.detail.id,
          fullName: widget.detail.fullName,
          expectedUpdatedAt: widget.detail.updatedAt,
          notes: notes.isEmpty ? null : notes,
        ),
      );
      if (!mounted) {
        return;
      }
      ref.invalidate(patientDetailProvider(widget.detail.id));
      setState(() => _notesDirty = false);
      ref.showAppToast(message: 'Notes saved.', variant: AppToastVariant.success);
    } catch (_) {
      if (mounted) {
        ref.showAppToast(
          message: 'Unable to save notes. Try again.',
          variant: AppToastVariant.danger,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingNotes = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final documentsAsync = ref.watch(patientVisitDocumentsProvider(detail.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDescriptionList(
          items: [
            AppDescriptionItem(
              label: 'Phone',
              tabular: true,
              value: Text(PatientPresentationFormatting.orDash(detail.phone)),
            ),
            AppDescriptionItem(
              label: 'Date of birth',
              tabular: true,
              value: Text(PatientPresentationFormatting.dateOfBirthLabel(detail.dateOfBirth)),
            ),
            AppDescriptionItem(
              label: 'Gender',
              value: Text(detail.gender?.label ?? '—'),
            ),
            AppDescriptionItem(
              label: 'Marital status',
              value: Text(detail.maritalStatus?.label ?? '—'),
            ),
            AppDescriptionItem(
              label: 'Registering branch',
              value: Text(detail.branchName),
            ),
            AppDescriptionItem(
              label: 'Registered',
              tabular: true,
              value: Text(PatientPresentationFormatting.dateTime.format(detail.createdAt.toLocal())),
            ),
            if (detail.createdByDisplay != null)
              AppDescriptionItem(
                label: 'Created by',
                value: Text(detail.createdByDisplay!),
              ),
          ],
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        AppSectionHeader(
          title: 'Notes',
          description: 'Front-desk and clinical notes for this patient.',
          actions: _canEditNotes
              ? AppButton(
                  label: 'Save note',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  loading: _isSavingNotes,
                  disabled: !_notesDirty || _isSavingNotes,
                  onPressed: _saveNotes,
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.s4),
        AppTextArea(
          controller: _notesController,
          hintText: _canEditNotes ? 'Add clinical or reception notes…' : 'No notes recorded.',
          disabled: !_canEditNotes || _isSavingNotes,
          minRows: 4,
          onChanged: (_) => setState(() => _notesDirty = true),
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        AppSectionHeader(
          title: 'Documents',
          description: 'Attachments from past visits.',
        ),
        const SizedBox(height: AppSpacing.s4),
        documentsAsync.when(
          loading: () => const Center(child: AppSpinner()),
          error: (_, _) => AppErrorState(
            message: 'Unable to load documents.',
            onRetry: () => ref.invalidate(patientVisitDocumentsProvider(detail.id)),
          ),
          data: (documents) => _PatientDocumentsList(documents: documents),
        ),
      ],
    );
  }
}

class _PatientDocumentsList extends StatelessWidget {
  const _PatientDocumentsList({required this.documents});

  final List<PatientVisitDocument> documents;

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noResults,
        title: 'No documents yet',
        description: 'Visit attachments will appear here.',
      );
    }

    final typography = context.typography;
    final colors = context.colors;

    return Column(
      children: [
        for (final doc in documents) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: AppIcon(
              icon: LucideIcons.fileText,
              color: colors.iconMuted,
            ),
            title: Text(
              doc.attachment.label ?? doc.attachment.fileType.label,
              style: typography.bodyStrong,
            ),
            subtitle: Text(
              '${PatientPresentationFormatting.date.format(doc.visitDate)} · Visit ${doc.visitId.substring(0, 8)}',
              style: typography.bodySm.copyWith(color: colors.textSecondary),
            ),
          ),
          if (doc != documents.last)
            Divider(height: 1, color: colors.borderSubtle),
        ],
      ],
    );
  }
}

/// Billing tab — patient invoice history.
class PatientDetailBillingTab extends ConsumerWidget {
  const PatientDetailBillingTab({required this.patientId, super.key});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessInvoiceList(auth)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Billing',
        description: 'You do not have permission to view invoices.',
      );
    }

    final invoicesAsync = ref.watch(patientInvoicesProvider(patientId));

    return invoicesAsync.when(
      loading: () => const Center(child: AppSpinner()),
      error: (error, _) => AppErrorState(
        message: 'Unable to load invoices: $error',
        onRetry: () => ref.invalidate(patientInvoicesProvider(patientId)),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return const AppEmptyState(
            variant: AppEmptyStateVariant.noResults,
            title: 'No invoices yet',
            description: 'Invoice history for this patient will appear here.',
          );
        }

        return AppCard(
          padding: AppCardPadding.sm,
          child: Column(
            children: [
              for (final item in page.items) ...[
                _PatientInvoiceRow(
                  item: item,
                  onTap: () => _openInvoice(context, item),
                ),
                if (item != page.items.last)
                  Divider(height: 1, color: context.colors.borderSubtle),
              ],
            ],
          ),
        );
      },
    );
  }

  void _openInvoice(BuildContext context, InvoiceListItem item) {
    if (item.status == InvoiceStatus.draft) {
      context.push(AppRoutes.billingInvoiceEdit(item.id));
      return;
    }
    context.push(AppRoutes.billingInvoiceDetail(item.id));
  }
}

class _PatientInvoiceRow extends StatelessWidget {
  const _PatientInvoiceRow({required this.item, required this.onTap});

  final InvoiceListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;
    final date = item.issuedAt ?? item.createdAt;

    return AppPressable(
      onTap: onTap,
      borderRadius: AppRadii.mdAll,
      semanticLabel: 'Open invoice',
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s3,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    BillingFormatting.invoiceDisplayNumber(item.invoiceNumber, item.id),
                    style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    BillingFormatting.formatDate(date),
                    style: typography.tabular(typography.bodySm).copyWith(
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Flexible(
              child: Text(
                BillingFormatting.formatMoney(item.subtotal - item.discountAmount),
                style: typography.tabular(typography.bodyStrong),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            _InvoiceStatusBadge(status: item.status),
          ],
        ),
      ),
    );
  }
}

class _InvoiceStatusBadge extends StatelessWidget {
  const _InvoiceStatusBadge({required this.status});

  final InvoiceStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      InvoiceStatus.draft => (AppBadgeColor.neutral, status.label),
      InvoiceStatus.issued => (AppBadgeColor.info, status.label),
      InvoiceStatus.partiallyPaid => (AppBadgeColor.warning, status.label),
      InvoiceStatus.paid => (AppBadgeColor.success, status.label),
      InvoiceStatus.voided => (AppBadgeColor.danger, status.label),
    };

    return AppBadge(color: color, child: Text(label));
  }
}
