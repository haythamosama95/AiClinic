import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_label.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_provider.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_view.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:ai_clinic/features/patients/presentation/edit_patient/edit_patient_dialog.dart';
import 'package:ai_clinic/features/patients/presentation/pages/mrn_reassignment_dialog.dart';
import 'package:ai_clinic/features/patients/presentation/navigation/patient_detail_route_extra.dart';
import 'package:ai_clinic/features/patients/presentation/providers/active_branch_name_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_history_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_detail_section.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_document_card.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_invoice_card.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_notes_dialog.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_record_grid.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_visit_record_card.dart';
<<<<<<< HEAD
=======
import 'package:ai_clinic/features/visits/presentation/navigation/visit_navigation.dart';
>>>>>>> master

/// Patient profile route (`/patients/:patientId`).
class PatientDetailPage extends ConsumerStatefulWidget {
  const PatientDetailPage({required this.patientId, this.extra, super.key});

  final String patientId;
  final PatientDetailRouteExtra? extra;

  @override
  ConsumerState<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends ConsumerState<PatientDetailPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enterController;
  CurvedAnimation? _enterAnimation;
  var _enterStarted = false;
  var _section = PatientDetailSection.visits;

  PatientListItem? get _preview => widget.extra?.preview;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_enterStarted) {
      _enterStarted = true;
      final reducedMotion = AppMotion.prefersReducedMotion(context);
      _enterController.duration = reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 220);
      _enterAnimation = CurvedAnimation(
        parent: _enterController,
        curve: AppMotion.resolveCurve(
          AppMotionPreset.rowEnter,
          reducedMotion: reducedMotion,
        ),
      );
      if (reducedMotion) {
        _enterController.value = 1;
      } else {
        _enterController.forward();
      }
    }
  }

  @override
  void dispose() {
    _enterAnimation?.dispose();
    _enterController.dispose();
    super.dispose();
  }

  void _invalidateDetail() {
    ref.invalidate(patientDetailProvider(widget.patientId));
  }

  void _openEditPatient() {
    showDialog<void>(
      context: context,
      builder: (_) => EditPatientDialog(patientId: widget.patientId),
    );
  }

  Future<void> _openReassignMrn(String currentMrn) async {
    final success = await MrnReassignmentDialog.show(
      context,
      patientId: widget.patientId,
      currentMrn: currentMrn,
    );
    if (!mounted || !success) {
      return;
    }
    ref.invalidate(patientDetailProvider(widget.patientId));
  }

  void _openPatientNotes(String notes) {
    PatientNotesDialog.show(context, notes: notes);
  }

  bool _isPatientNotFound(Object error) {
    return error is RpcFailure && error.code == 'NOT_FOUND';
  }

  String _errorMessage(Object error) {
    if (error is RpcFailure) {
      return error.message;
    }
    if (error is StateError) {
      return error.message;
    }
    return error.toString();
  }

  _PatientIdentityView _identityView({
    PatientDetail? detail,
    PatientListItem? preview,
  }) {
    if (detail != null) {
      return _PatientIdentityView(
        fullName: detail.fullName,
        mrn: detail.mrn,
        phone: detail.phone,
        dateOfBirth: detail.dateOfBirth,
        gender: detail.gender,
        maritalStatus: detail.maritalStatus,
        branchName: detail.branchName,
      );
    }
    if (preview != null) {
      return _PatientIdentityView(
        fullName: preview.fullName,
        mrn: preview.mrn,
        phone: preview.phone,
        dateOfBirth: preview.dateOfBirth,
        gender: preview.gender,
        branchName: preview.registeringBranchName,
      );
    }
    return const _PatientIdentityView(fullName: 'Patient');
  }

  List<AppTabItem> _tabItems(BuildContext context) {
    return PatientDetailSection.values
        .map(
          (section) => AppTabItem(
            id: section.name,
            label: patientDetailSectionLabel(context, section),
          ),
        )
        .toList(growable: false);
  }

  Widget _buildBreadcrumb(BuildContext context, String patientName) {
<<<<<<< HEAD
    final l10n = context.l10n;
    return AppBreadcrumb(
      items: [
        AppBreadcrumbItem(
          label: l10n.patients,
          onTap: () => context.nav.goPatients(),
        ),
        AppBreadcrumbItem(label: patientName),
      ],
    );
=======
    scheduleBreadcrumbEntryLabelUpdate(
      ref,
      'patient:${widget.patientId}',
      BreadcrumbLabel.fixed(patientName),
    );
    return const BreadcrumbTrailView();
>>>>>>> master
  }

  /// Centers tab placeholder states (empty / error) within the full content width.
  Widget _buildCenteredTabPlaceholder(Widget child) {
    return SizedBox(
      width: double.infinity,
      child: Center(child: child),
    );
  }

  Widget _buildNotFound(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.space6,
      children: [
        AppPageHeader(
          title: l10n.patientNotFound,
<<<<<<< HEAD
          breadcrumb: AppBreadcrumb(
            items: [
              AppBreadcrumbItem(
                label: l10n.patients,
                onTap: () => context.nav.goPatients(),
              ),
              AppBreadcrumbItem(label: l10n.patientDetailBreadcrumb),
            ],
          ),
=======
          breadcrumb: const BreadcrumbTrailView(),
>>>>>>> master
        ),
        AppEmptyState(
          variant: AppEmptyStateVariant.error,
          title: l10n.patientNotFound,
          description: l10n.patientNotFoundDescription,
          action: EmptyStateAction(
            label: l10n.backToPatients,
            onPressed: () => context.nav.goPatients(),
          ),
        ),
      ],
    );
  }

  double _recordSkeletonHeight(PatientDetailSection section) {
    return switch (section) {
      PatientDetailSection.documents => 200,
      PatientDetailSection.billing => 132,
      PatientDetailSection.visits => 152,
    };
  }

  double? _recordGridExtent(PatientDetailSection section) {
    return switch (section) {
      PatientDetailSection.documents => null,
      PatientDetailSection.billing => null,
      PatientDetailSection.visits => null,
    };
  }

  int _maxCrossAxisCount(PatientDetailSection section) {
    return switch (section) {
      PatientDetailSection.visits || PatientDetailSection.billing => 4,
      _ => 3,
    };
  }

  Widget _buildRecordCardSkeletonGrid({
    required int count,
    PatientDetailSection? section,
  }) {
    final resolvedSection = section ?? _section;
    final height = _recordSkeletonHeight(resolvedSection);
    return AppSkeletonizerZone(
      child: PatientRecordGrid(
        mainAxisExtent: _recordGridExtent(resolvedSection),
        maxCrossAxisCount: _maxCrossAxisCount(resolvedSection),
        children: [
          for (var index = 0; index < count; index++)
            AppSkeleton(variant: SkeletonVariant.rectangular, height: height),
        ],
      ),
    );
  }

  String? _resolveBranchId({PatientDetail? detail}) {
    final fromDetail = detail?.branchId.trim();
    if (fromDetail != null && fromDetail.isNotEmpty) {
      return fromDetail;
    }
    final fromPreview = _preview?.registeringBranchId.trim();
    if (fromPreview != null && fromPreview.isNotEmpty) {
      return fromPreview;
    }
    final fromSession = ref
        .read(authSessionProvider)
        .context
        ?.activeBranchId
        ?.trim();
    if (fromSession != null && fromSession.isNotEmpty) {
      return fromSession;
    }
    return null;
  }

  String? _resolveBranchName({PatientDetail? detail}) {
    final fromDetail = detail?.branchName.trim();
    if (fromDetail != null && fromDetail.isNotEmpty) {
      return fromDetail;
    }
    final fromPreview = _preview?.registeringBranchName.trim();
    if (fromPreview != null && fromPreview.isNotEmpty) {
      return fromPreview;
    }
    return ref.watch(activeBranchNameProvider).value;
  }

  Widget _buildVisitsTabBody({PatientDetail? detail}) {
    final l10n = context.l10n;
    final visitsAsync = ref.watch(patientPastVisitsProvider(widget.patientId));
    final branchId = _resolveBranchId(detail: detail);
    final branchName = _resolveBranchName(detail: detail);

    final appointmentsAsync = branchId == null
        ? const AsyncValue<List<AppointmentListItem>>.data([])
        : ref.watch(
            patientUpcomingAppointmentsProvider(
              PatientDetailHistoryQuery(
                patientId: widget.patientId,
                branchId: branchId,
              ),
            ),
          );

    if (visitsAsync.isLoading || appointmentsAsync.isLoading) {
      return _buildRecordCardSkeletonGrid(
        count: 3,
        section: PatientDetailSection.visits,
      );
    }

    if (visitsAsync.hasError) {
      return _buildCenteredTabPlaceholder(
        AppErrorState(
          message: _errorMessage(visitsAsync.error!),
          onRetry: () =>
              ref.invalidate(patientPastVisitsProvider(widget.patientId)),
        ),
      );
    }

    final visits = visitsAsync.value ?? [];
    final appointments = appointmentsAsync.hasError
        ? <AppointmentListItem>[]
        : (appointmentsAsync.value ?? []);

    if (visits.isEmpty && appointments.isEmpty) {
      return _buildCenteredTabPlaceholder(
        AppEmptyState(
          variant: AppEmptyStateVariant.firstRun,
          title: l10n.noVisitsYet,
          description: l10n.noVisitsYetDescription,
        ),
      );
    }

    final records = <({DateTime sortDate, Widget card})>[
      for (final appointment in appointments)
        (
          sortDate: appointment.startTime,
          card: PatientVisitRecordCard.fromAppointment(
            appointment,
            branchName: branchName,
            key: ValueKey('appointment-${appointment.id}'),
          ),
        ),
      for (final visit in visits)
        (
          sortDate: visit.visitDate,
          card: PatientVisitRecordCard.fromVisit(
            visit,
            key: ValueKey('visit-${visit.id}'),
<<<<<<< HEAD
=======
            onTap: canOpenVisitFromPatientHistory(ref, visit)
                ? () => openVisitFromPatientHistory(context, ref, visit)
                : null,
>>>>>>> master
          ),
        ),
    ]..sort((a, b) => b.sortDate.compareTo(a.sortDate));

    return PatientRecordGrid(
      maxCrossAxisCount: 4,
      mainAxisExtent: null,
      children: [for (final record in records) record.card],
    );
  }

  Widget _buildBillingTabBody() {
    final canAccessBilling = ref.watch(
      authSessionProvider.select(AuthRouteGuard.canAccessInvoiceList),
    );
    final invoicesAsync = ref.watch(patientInvoicesProvider(widget.patientId));
    final l10n = context.l10n;

    return invoicesAsync.when(
      loading: () => _buildRecordCardSkeletonGrid(
        count: 3,
        section: PatientDetailSection.billing,
      ),
      error: (error, _) => _buildCenteredTabPlaceholder(
        AppErrorState(
          message: _errorMessage(error),
          onRetry: () =>
              ref.invalidate(patientInvoicesProvider(widget.patientId)),
        ),
      ),
      data: (pageResult) {
        if (!canAccessBilling) {
          return _buildCenteredTabPlaceholder(
            AppEmptyState(
              variant: AppEmptyStateVariant.noAccess,
              title: l10n.billingNoAccess,
            ),
          );
        }

        final invoices = [...pageResult.items]
          ..sort((a, b) {
            final aDate = a.issuedAt ?? a.createdAt;
            final bDate = b.issuedAt ?? b.createdAt;
            return bDate.compareTo(aDate);
          });

        if (invoices.isEmpty) {
          return _buildCenteredTabPlaceholder(
            AppEmptyState(
              variant: AppEmptyStateVariant.firstRun,
              title: l10n.noInvoices,
              description: l10n.noInvoicesDescription,
            ),
          );
        }

        return PatientRecordGrid(
          mainAxisExtent: _recordGridExtent(PatientDetailSection.billing),
          maxCrossAxisCount: _maxCrossAxisCount(PatientDetailSection.billing),
          children: [
            for (final invoice in invoices)
              PatientInvoiceCard(invoice: invoice),
          ],
        );
      },
    );
  }

  Widget _buildDocumentsTabBody() {
    final documentsAsync = ref.watch(
      patientVisitDocumentsProvider(widget.patientId),
    );
    final l10n = context.l10n;

    return documentsAsync.when(
      loading: () => _buildRecordCardSkeletonGrid(
        count: 3,
        section: PatientDetailSection.documents,
      ),
      error: (error, _) => _buildCenteredTabPlaceholder(
        AppErrorState(
          message: _errorMessage(error),
          onRetry: () =>
              ref.invalidate(patientVisitDocumentsProvider(widget.patientId)),
        ),
      ),
      data: (documents) {
        if (documents.isEmpty) {
          return _buildCenteredTabPlaceholder(
            AppEmptyState(
              variant: AppEmptyStateVariant.firstRun,
              title: l10n.noDocuments,
              description: l10n.noDocumentsDescription,
            ),
          );
        }
        return PatientRecordGrid(
          mainAxisExtent: _recordGridExtent(PatientDetailSection.documents),
          children: [
            for (final document in documents)
              PatientDocumentCard(document: document),
          ],
        );
      },
    );
  }

  Widget _buildActiveTabBody({PatientDetail? detail}) {
    return switch (_section) {
      PatientDetailSection.visits => _buildVisitsTabBody(detail: detail),
      PatientDetailSection.documents => _buildDocumentsTabBody(),
      PatientDetailSection.billing => _buildBillingTabBody(),
    };
  }

  Widget _buildMainContent({
    required BuildContext context,
    required _PatientIdentityView identity,
    required bool skeletonizeHeader,
    required bool showTabSkeleton,
    required bool canReassignMrn,
    Widget? tabBodyOverride,
    PatientDetail? detail,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.space6,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.space4,
          children: [
            _buildBreadcrumb(context, identity.fullName),
            _PatientIdentityCard(
              identity: identity,
              section: _section,
              tabItems: _tabItems(context),
              skeletonize: skeletonizeHeader,
              onSectionChanged: (section) => setState(() => _section = section),
              onViewNotes:
                  detail?.notes != null && detail!.notes!.trim().isNotEmpty
                  ? () => _openPatientNotes(detail.notes!)
                  : null,
              onEdit: detail != null ? _openEditPatient : null,
              onReassignMrn:
                  detail != null && canReassignMrn && detail.mrn != null
                  ? () => _openReassignMrn(detail.mrn!)
                  : null,
            ),
          ],
        ),
        if (tabBodyOverride != null)
          tabBodyOverride
        else if (showTabSkeleton)
          _buildRecordCardSkeletonGrid(count: 3, section: _section)
        else
          _buildActiveTabBody(detail: detail),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(patientDetailProvider(widget.patientId));
    final canReassignMrn = ref
        .watch(permissionServiceProvider)
        .canReassignPatientMrn();
    final preview = _preview;

    Widget content;
    if (detailAsync.hasError && _isPatientNotFound(detailAsync.error!)) {
      content = _buildNotFound(context);
    } else if (detailAsync.hasError) {
      final identity = _identityView(preview: preview);
      content = preview == null
          ? AppErrorState(
              message: _errorMessage(detailAsync.error!),
              onRetry: _invalidateDetail,
            )
          : _buildMainContent(
              context: context,
              identity: identity,
              skeletonizeHeader: false,
              showTabSkeleton: false,
              canReassignMrn: canReassignMrn,
              tabBodyOverride: _buildCenteredTabPlaceholder(
                AppErrorState(
                  message: _errorMessage(detailAsync.error!),
                  onRetry: _invalidateDetail,
                ),
              ),
            );
    } else if (detailAsync.isLoading) {
      final identity = _identityView(
        detail: detailAsync.value,
        preview: preview,
      );
      content = _buildMainContent(
        context: context,
        identity: identity,
        skeletonizeHeader: preview == null,
        showTabSkeleton: true,
        canReassignMrn: canReassignMrn,
      );
    } else {
      final detail = detailAsync.value;
      if (detail == null) {
        content = _buildNotFound(context);
      } else {
        final identity = _identityView(detail: detail, preview: preview);
        content = _buildMainContent(
          context: context,
          identity: identity,
          skeletonizeHeader: false,
          showTabSkeleton: false,
          canReassignMrn: canReassignMrn,
          detail: detail,
        );
      }
    }

    return AppMotion.animatedPreset(
      context: context,
      preset: AppMotionPreset.rowEnter,
      animation: _enterAnimation ?? _enterController,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.hasBoundedHeight) {
            return SingleChildScrollView(child: content);
          }
          return content;
        },
      ),
    );
  }
}

class _PatientIdentityView {
  const _PatientIdentityView({
    required this.fullName,
    this.mrn,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.maritalStatus,
    this.branchName,
  });

  final String fullName;
  final String? mrn;
  final String? phone;
  final DateTime? dateOfBirth;
  final PatientGender? gender;
  final PatientMaritalStatus? maritalStatus;
  final String? branchName;
}

class _PatientIdentityCard extends StatelessWidget {
  const _PatientIdentityCard({
    required this.identity,
    required this.section,
    required this.tabItems,
    required this.onSectionChanged,
    this.skeletonize = false,
    this.onViewNotes,
    this.onEdit,
    this.onReassignMrn,
  });

  final _PatientIdentityView identity;
  final PatientDetailSection section;
  final List<AppTabItem> tabItems;
  final ValueChanged<PatientDetailSection> onSectionChanged;
  final bool skeletonize;
  final VoidCallback? onViewNotes;
  final VoidCallback? onEdit;
  final VoidCallback? onReassignMrn;

  @override
  Widget build(BuildContext context) {
    if (skeletonize) {
      return AppSkeletonizerZone(
        child: AppCard(
          variant: CardVariant.raised,
          padding: CardPadding.lg,
          footer: const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.space6),
            child: AppSkeleton(
              variant: SkeletonVariant.rectangular,
              height: 40,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              AppSkeleton(
                variant: SkeletonVariant.circular,
                width: 40,
                height: 40,
              ),
              SizedBox(width: AppSpacing.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.space3,
                  children: [
                    AppSkeleton(
                      variant: SkeletonVariant.rectangular,
                      width: 220,
                      height: 32,
                    ),
                    Wrap(
                      spacing: AppSpacing.space2,
                      runSpacing: AppSpacing.space2,
                      children: [
                        AppSkeleton(
                          variant: SkeletonVariant.rectangular,
                          width: 72,
                          height: 24,
                        ),
                        AppSkeleton(
                          variant: SkeletonVariant.rectangular,
                          width: 120,
                          height: 24,
                        ),
                        AppSkeleton(
                          variant: SkeletonVariant.rectangular,
                          width: 96,
                          height: 24,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final colors = context.appColors;
    final l10n = context.l10n;
    final age = PatientPresentationFormatting.ageYears(identity.dateOfBirth);
    final dobLabel = identity.dateOfBirth != null
        ? '${l10n.dateOfBirthLabel} ${PatientPresentationFormatting.formatCalendarDate(identity.dateOfBirth!)}'
        : '—';
    final maritalLabel = identity.maritalStatus?.label;
    final branchName = identity.branchName?.trim();

    return AppCard(
      variant: CardVariant.raised,
      padding: CardPadding.lg,
      footer: AppTabs(
        items: tabItems,
        value: section.name,
        onChanged: (id) =>
            onSectionChanged(PatientDetailSection.values.byName(id)),
        ariaLabel: 'Patient sections',
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(name: identity.fullName, size: AvatarSize.lg),
          const SizedBox(width: AppSpacing.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: AppSpacing.space3,
              children: [
                Text(
                  identity.fullName,
                  style: AppTypography.h1(
                    context,
                  ).copyWith(color: colors.textPrimary),
                ),
                Wrap(
                  spacing: AppSpacing.space3,
                  runSpacing: AppSpacing.space3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (identity.mrn != null)
                      AppBadge(
                        size: BadgeSize.md,
                        variant: BadgeVariant.soft,
                        color: BadgeColor.teal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.badge_outlined,
                              size: 14,
                              color: colors.iconMuted,
                            ),
                            const SizedBox(width: AppSpacing.space1),
                            Text(
                              identity.mrn!,
                              style: AppTypography.mono(context),
                            ),
                          ],
                        ),
                      ),
                    AppBadge(
                      size: BadgeSize.md,
                      variant: BadgeVariant.soft,
                      color: BadgeColor.neutral,
                      label: PatientPresentationFormatting.ageGenderLabel(
                        age: age,
                        gender: identity.gender,
                      ),
                    ),
                    AppBadge(
                      size: BadgeSize.md,
                      variant: BadgeVariant.soft,
                      color: BadgeColor.neutral,
                      label: dobLabel,
                    ),
                    if (maritalLabel != null)
                      AppBadge(
                        size: BadgeSize.md,
                        variant: BadgeVariant.soft,
                        color: BadgeColor.neutral,
                        label: maritalLabel,
                      ),
                    AppBadge(
                      size: BadgeSize.md,
                      variant: BadgeVariant.soft,
                      color: BadgeColor.neutral,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.phone_outlined,
                            size: 14,
                            color: colors.iconMuted,
                          ),
                          const SizedBox(width: AppSpacing.space1 + 2),
                          Text(
                            PatientPresentationFormatting.orDash(
                              identity.phone,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (branchName != null && branchName.isNotEmpty)
                      AppBadge(
                        size: BadgeSize.md,
                        variant: BadgeVariant.soft,
                        color: BadgeColor.neutral,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.apartment,
                              size: 14,
                              color: colors.iconMuted,
                            ),
                            const SizedBox(width: AppSpacing.space2),
                            Text(branchName),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (onViewNotes != null || onEdit != null || onReassignMrn != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onViewNotes != null) ...[
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.md,
                    leadingIcon: const Icon(Icons.notes_outlined, size: 16),
                    onPressed: onViewNotes,
                    child: Text(l10n.notesLabel),
                  ),
                  if (onEdit != null || onReassignMrn != null)
                    const SizedBox(width: AppSpacing.space2),
                ],
                if (onReassignMrn != null) ...[
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.md,
                    leadingIcon: const Icon(Icons.badge_outlined, size: 16),
                    onPressed: onReassignMrn,
                    child: const Text('Reassign MRN'),
                  ),
                  if (onEdit != null) const SizedBox(width: AppSpacing.space2),
                ],
                if (onEdit != null)
                  AppButton(
                    variant: AppButtonVariant.primary,
                    size: AppButtonSize.md,
                    leadingIcon: const Icon(Icons.edit_outlined, size: 16),
                    onPressed: onEdit,
                    child: Text(l10n.editPatient),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
