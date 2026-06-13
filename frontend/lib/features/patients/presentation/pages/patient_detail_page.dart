import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/application/patient_rpc_messages.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_history_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_detail_documents_card.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_detail_notes_card.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_detail_timeline_section.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_gender_avatar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';

/// Full patient profile page loaded via `get_patient`.
class PatientDetailPage extends ConsumerWidget {
  const PatientDetailPage({required this.patientId, this.preview, super.key});

  final String patientId;
  final PatientListItem? preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessPatientDetail(auth)) {
      return const _PatientDetailPermissionDenied();
    }

    final detailAsync = ref.watch(patientDetailProvider(patientId));

    return detailAsync.when(
      skipLoadingOnReload: true,
      loading: () => _PatientDetailLoadingView(patientId: patientId, preview: preview, onBack: () => _goBack(context)),
      error: (error, _) => _PatientDetailErrorView(
        patientId: patientId,
        message: error.toString(),
        onBack: () => _goBack(context),
        onRetry: () => ref.invalidate(patientDetailProvider(patientId)),
      ),
      data: (detail) => _PatientDetailContentView(detail: detail, onBack: () => _goBack(context)),
    );
  }

  static void _goBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.nav.goPatients();
  }
}

class _PatientDetailContentView extends ConsumerWidget {
  const _PatientDetailContentView({required this.detail, required this.onBack});

  final PatientDetail detail;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyQuery = PatientDetailHistoryQuery(patientId: detail.id, branchId: detail.branchId);
    final pastVisitsAsync = ref.watch(patientPastVisitsProvider(detail.id));
    final upcomingAsync = ref.watch(patientUpcomingAppointmentsProvider(historyQuery));

    return _PatientDetailScaffold(
      patientId: detail.id,
      patientName: detail.fullName,
      onBack: onBack,
      body: (pageHeight) => LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1080;
          final isMedium = constraints.maxWidth >= 720;
          final sideCardHeight = (pageHeight - SpacingTokens.lg) / 2;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isWide)
                _PatientDetailSplitLayout(
                  mode: _PatientDetailSplitLayoutMode.wide,
                  pageHeight: pageHeight,
                  detail: detail,
                  pastCount: pastVisitsAsync.value?.length ?? 0,
                  upcomingCount: upcomingAsync.value?.length ?? 0,
                  historyQuery: historyQuery,
                  pastVisits: pastVisitsAsync.value ?? const [],
                  upcomingAppointments: upcomingAsync.value ?? const [],
                  pastLoading: pastVisitsAsync.isLoading,
                  upcomingLoading: upcomingAsync.isLoading,
                  pastError: pastVisitsAsync.hasError ? 'Unable to load past visits.' : null,
                  upcomingError: upcomingAsync.hasError ? 'Unable to load upcoming appointments.' : null,
                  onRetryPast: () => ref.invalidate(patientPastVisitsProvider(detail.id)),
                  onRetryUpcoming: () => ref.invalidate(patientUpcomingAppointmentsProvider(historyQuery)),
                )
              else if (isMedium)
                _PatientDetailSplitLayout(
                  mode: _PatientDetailSplitLayoutMode.medium,
                  pageHeight: pageHeight,
                  detail: detail,
                  pastCount: pastVisitsAsync.value?.length ?? 0,
                  upcomingCount: upcomingAsync.value?.length ?? 0,
                  historyQuery: historyQuery,
                  pastVisits: pastVisitsAsync.value ?? const [],
                  upcomingAppointments: upcomingAsync.value ?? const [],
                  pastLoading: pastVisitsAsync.isLoading,
                  upcomingLoading: upcomingAsync.isLoading,
                  pastError: pastVisitsAsync.hasError ? 'Unable to load past visits.' : null,
                  upcomingError: upcomingAsync.hasError ? 'Unable to load upcoming appointments.' : null,
                  onRetryPast: () => ref.invalidate(patientPastVisitsProvider(detail.id)),
                  onRetryUpcoming: () => ref.invalidate(patientUpcomingAppointmentsProvider(historyQuery)),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PatientProfileCard(
                      detail: detail,
                      upcomingCount: upcomingAsync.value?.length ?? 0,
                      pastCount: pastVisitsAsync.value?.length ?? 0,
                    ),
                    const SizedBox(height: SpacingTokens.lg),
                    _PatientBasicInfoCard(detail: detail),
                    const SizedBox(height: SpacingTokens.lg),
                    SizedBox(
                      height: sideCardHeight,
                      child: PatientDetailNotesCard(detail: detail),
                    ),
                    const SizedBox(height: SpacingTokens.lg),
                    PatientDetailTimelineSection(
                      patientId: detail.id,
                      pastVisits: pastVisitsAsync.value ?? const [],
                      upcomingAppointments: upcomingAsync.value ?? const [],
                      patientBranchName: detail.branchName,
                      pastLoading: pastVisitsAsync.isLoading,
                      upcomingLoading: upcomingAsync.isLoading,
                      pastError: pastVisitsAsync.hasError ? 'Unable to load past visits.' : null,
                      upcomingError: upcomingAsync.hasError ? 'Unable to load upcoming appointments.' : null,
                      onRetryPast: () => ref.invalidate(patientPastVisitsProvider(detail.id)),
                      onRetryUpcoming: () => ref.invalidate(patientUpcomingAppointmentsProvider(historyQuery)),
                    ),
                    const SizedBox(height: SpacingTokens.lg),
                    SizedBox(
                      height: sideCardHeight,
                      child: PatientDetailDocumentsCard(patientId: detail.id),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

enum _PatientDetailSplitLayoutMode { wide, medium }

/// Wide/medium layout with a left content column and a right column for notes
/// and documents, each sized to half of the patient detail page viewport.
class _PatientDetailSplitLayout extends StatelessWidget {
  const _PatientDetailSplitLayout({
    required this.mode,
    required this.pageHeight,
    required this.detail,
    required this.pastCount,
    required this.upcomingCount,
    required this.historyQuery,
    required this.pastVisits,
    required this.upcomingAppointments,
    required this.pastLoading,
    required this.upcomingLoading,
    this.pastError,
    this.upcomingError,
    required this.onRetryPast,
    required this.onRetryUpcoming,
  });

  final _PatientDetailSplitLayoutMode mode;
  final double pageHeight;
  final PatientDetail detail;
  final int pastCount;
  final int upcomingCount;
  final PatientDetailHistoryQuery historyQuery;
  final List<VisitListItem> pastVisits;
  final List<AppointmentListItem> upcomingAppointments;
  final bool pastLoading;
  final bool upcomingLoading;
  final String? pastError;
  final String? upcomingError;
  final VoidCallback onRetryPast;
  final VoidCallback onRetryUpcoming;

  Widget _buildTimelineSection() {
    return PatientDetailTimelineSection(
      patientId: detail.id,
      pastVisits: pastVisits,
      upcomingAppointments: upcomingAppointments,
      patientBranchName: detail.branchName,
      pastLoading: pastLoading,
      upcomingLoading: upcomingLoading,
      pastError: pastError,
      upcomingError: upcomingError,
      onRetryPast: onRetryPast,
      onRetryUpcoming: onRetryUpcoming,
    );
  }

  Widget _buildTopSection() {
    if (mode == _PatientDetailSplitLayoutMode.wide) {
      return _EqualHeightRow(
        children: [
          _EqualHeightRowChild(
            child: _PatientProfileCard(detail: detail, upcomingCount: upcomingCount, pastCount: pastCount),
          ),
          _EqualHeightRowChild(flex: 2, child: _PatientBasicInfoCard(detail: detail)),
        ],
      );
    }

    return _PatientBasicInfoCard(detail: detail);
  }

  Widget _buildSideColumn() {
    return SizedBox(
      height: pageHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: PatientDetailNotesCard(detail: detail)),
          const SizedBox(height: SpacingTokens.lg),
          Expanded(child: PatientDetailDocumentsCard(patientId: detail.id)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final splitRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: mode == _PatientDetailSplitLayoutMode.wide ? 3 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopSection(),
              const SizedBox(height: SpacingTokens.lg),
              _buildTimelineSection(),
            ],
          ),
        ),
        const SizedBox(width: SpacingTokens.lg),
        Expanded(child: _buildSideColumn()),
      ],
    );

    if (mode == _PatientDetailSplitLayoutMode.medium) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PatientProfileCard(detail: detail, upcomingCount: upcomingCount, pastCount: pastCount),
          const SizedBox(height: SpacingTokens.lg),
          splitRow,
        ],
      );
    }

    return splitRow;
  }
}

@immutable
class _EqualHeightRowChild {
  const _EqualHeightRowChild({required this.child, this.flex = 1});

  final Widget child;
  final int flex;
}

/// Keeps row children at a shared height equal to the tallest card.
///
/// Uses post-layout measurement because [IntrinsicHeight] is unreliable when
/// descendants include [LayoutBuilder] (for example [_InfoGrid]).
class _EqualHeightRow extends StatefulWidget {
  const _EqualHeightRow({required this.children});

  final List<_EqualHeightRowChild> children;

  @override
  State<_EqualHeightRow> createState() => _EqualHeightRowState();
}

class _EqualHeightRowState extends State<_EqualHeightRow> {
  final _childKeys = <GlobalKey>[];
  double? _sharedHeight;

  @override
  void initState() {
    super.initState();
    _resetKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncSharedHeight());
  }

  @override
  void didUpdateWidget(covariant _EqualHeightRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.children.length != widget.children.length) {
      _resetKeys();
      _sharedHeight = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncSharedHeight());
  }

  void _resetKeys() {
    _childKeys
      ..clear()
      ..addAll(List.generate(widget.children.length, (_) => GlobalKey()));
  }

  void _syncSharedHeight() {
    if (!mounted) {
      return;
    }

    final measuredHeights = <double>[
      for (final key in _childKeys)
        if (key.currentContext?.size case final size?) size.height,
    ];
    if (measuredHeights.isEmpty) {
      return;
    }

    final tallest = measuredHeights.reduce(math.max);
    if (tallest <= 0 || _sharedHeight == tallest) {
      return;
    }

    setState(() => _sharedHeight = tallest);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.children.length; i++) ...[
          if (i > 0) const SizedBox(width: SpacingTokens.lg),
          Expanded(
            flex: widget.children[i].flex,
            child: SizedBox(
              height: _sharedHeight,
              child: KeyedSubtree(key: _childKeys[i], child: widget.children[i].child),
            ),
          ),
        ],
      ],
    );
  }
}

class _PatientProfileCard extends StatelessWidget {
  const _PatientProfileCard({required this.detail, required this.pastCount, required this.upcomingCount});

  final PatientDetail detail;
  final int pastCount;
  final int upcomingCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              detail.fullName,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              'ID ${PatientPresentationFormatting.displayId(detail.id)}',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SpacingTokens.md),
            _ProfileStatsWithFloatingAvatar(gender: detail.gender, pastCount: pastCount, upcomingCount: upcomingCount),
          ],
        ),
      ),
    );
  }
}

/// Past / upcoming counts with the avatar centered over the middle gap.
///
/// The stats row and avatar share the same vertical band; the avatar is painted
/// on top via [Stack] rather than occupying a third column.
class _ProfileStatsWithFloatingAvatar extends StatelessWidget {
  const _ProfileStatsWithFloatingAvatar({required this.gender, required this.pastCount, required this.upcomingCount});

  static const _avatarSize = 96.0;

  final PatientGender? gender;
  final int pastCount;
  final int upcomingCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm, horizontal: SpacingTokens.md),
          child: SizedBox(
            height: _avatarSize,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: _ProfileStat(label: 'Past', value: '$pastCount'),
                  ),
                ),
                SizedBox(width: _avatarSize, child: const SizedBox()),
                Expanded(
                  child: Center(
                    child: _ProfileStat(label: 'Upcoming', value: '$upcomingCount'),
                  ),
                ),
              ],
            ),
          ),
        ),
        PatientGenderAvatar(gender: gender, size: _avatarSize),
      ],
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: colors.mutedForeground),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: colors.primary),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _PatientBasicInfoCard extends StatelessWidget {
  const _PatientBasicInfoCard({required this.detail});

  final PatientDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Basic information',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Flexible(
                  child: Text(
                    'Registered ${PatientPresentationFormatting.dateTime.format(detail.createdAt)}',
                    style: theme.textTheme.labelSmall?.copyWith(color: colors.mutedForeground),
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.lg),
            _InfoGrid(
              items: [
                _InfoGridItem(label: 'Gender', value: detail.gender?.label ?? '—'),
                _InfoGridItem(
                  label: 'Date of birth',
                  value: PatientPresentationFormatting.dateOfBirthLabel(detail.dateOfBirth),
                ),
                _InfoGridItem(label: 'Phone', value: PatientPresentationFormatting.orDash(detail.phone)),
                _InfoGridItem(label: 'Marital status', value: detail.maritalStatus?.label ?? '—'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

@immutable
class _InfoGridItem {
  const _InfoGridItem({required this.label, required this.value});

  final String label;
  final String value;
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.items});

  final List<_InfoGridItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth >= 360 ? 2 : 1;
        final itemWidth = (constraints.maxWidth - (columnCount - 1) * SpacingTokens.lg) / columnCount;

        return Wrap(
          spacing: SpacingTokens.lg,
          runSpacing: SpacingTokens.lg,
          children: [
            for (final item in items)
              SizedBox(
                width: columnCount == 1 ? constraints.maxWidth : itemWidth,
                child: _PatientDetailInfoRow(label: item.label, value: item.value),
              ),
          ],
        );
      },
    );
  }
}

class _PatientDetailLoadingView extends StatelessWidget {
  const _PatientDetailLoadingView({required this.patientId, required this.onBack, this.preview});

  final String patientId;
  final VoidCallback onBack;
  final PatientListItem? preview;

  @override
  Widget build(BuildContext context) {
    return _PatientDetailScaffold(
      patientId: patientId,
      patientName: preview?.fullName,
      onBack: onBack,
      body: (pageHeight) => AppDeferredLoading(
        isLoading: true,
        placeholder: preview != null
            ? _PatientDetailPreviewLayout(preview: preview!, pageHeight: pageHeight)
            : _PatientDetailBodySkeleton(pageHeight: pageHeight),
        loading: _PatientDetailBodyLoading(pageHeight: pageHeight),
      ),
    );
  }
}

class _PatientDetailPreviewLayout extends StatelessWidget {
  const _PatientDetailPreviewLayout({required this.preview, required this.pageHeight});

  final PatientListItem preview;
  final double pageHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Opacity(
      opacity: 0.72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(context.shapeTokens.lg),
              border: Border.all(color: colors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.lg),
              child: Row(
                children: [
                  PatientGenderAvatar(gender: preview.gender, size: 72),
                  const SizedBox(width: SpacingTokens.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preview.fullName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          _PatientDetailBodySkeleton(pageHeight: pageHeight),
        ],
      ),
    );
  }
}

class _PatientDetailErrorView extends StatelessWidget {
  const _PatientDetailErrorView({
    required this.patientId,
    required this.message,
    required this.onBack,
    required this.onRetry,
  });

  final String patientId;
  final String message;
  final VoidCallback onBack;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _PatientDetailScaffold(
      patientId: patientId,
      onBack: onBack,
      body: (_) => _PatientDetailBodyError(message: message, onRetry: onRetry),
    );
  }
}

class _PatientDetailScaffold extends ConsumerWidget {
  const _PatientDetailScaffold({required this.patientId, required this.onBack, this.patientName, required this.body});

  final String patientId;
  final VoidCallback onBack;
  final String? patientName;
  final Widget Function(double pageHeight) body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PatientDetailHeader(patientId: patientId, patientName: patientName, onBack: onBack),
          const SizedBox(height: SpacingTokens.md),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(child: body(constraints.maxHeight));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientDetailHeader extends ConsumerStatefulWidget {
  const _PatientDetailHeader({required this.patientId, required this.onBack, this.patientName});

  final String patientId;
  final VoidCallback onBack;
  final String? patientName;

  @override
  ConsumerState<_PatientDetailHeader> createState() => _PatientDetailHeaderState();
}

class _PatientDetailHeaderState extends ConsumerState<_PatientDetailHeader> {
  var _isDeleting = false;

  bool get _canEdit => AuthRouteGuard.canAccessPatientEdit(ref.read(authSessionProvider));

  bool get _canDelete => AuthRouteGuard.canAccessPatientDelete(ref.read(authSessionProvider));

  Future<void> _confirmDelete() async {
    final name = widget.patientName?.trim();
    final message = name == null || name.isEmpty
        ? 'This patient will be archived and removed from active lists. Historical records stay linked.'
        : '$name will be archived and removed from active lists. Historical records stay linked.';

    await AppDialog.showConfirmation(
      context: context,
      title: 'Delete patient?',
      message: message,
      confirmLabel: 'Delete patient',
      cancelLabel: 'Cancel',
      destructive: true,
      onConfirm: _deletePatient,
    );
  }

  Future<void> _deletePatient() async {
    if (_isDeleting) {
      return;
    }

    setState(() => _isDeleting = true);
    try {
      await ref.read(archivePatientUseCaseProvider)(widget.patientId);
      if (!mounted) {
        return;
      }
      AppToast.success(context, message: 'Patient deleted.');
      PatientDetailPage._goBack(context);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isDeleting = false);
      AppToast.error(context, message: patientMessageForRpc(error));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isDeleting = false);
      AppToast.error(context, message: 'Unable to delete patient. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return SizedBox(
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AppIconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              tooltip: 'Back to patients',
              onPressed: widget.onBack,
            ),
          ),
          Text(
            'Patient Details',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_canEdit)
                  IconButton(
                    tooltip: 'Edit patient',
                    onPressed: () => context.nav.goPatientEdit(widget.patientId),
                    icon: Icon(Icons.edit_outlined, color: colors.mutedForeground),
                  ),
                if (_canDelete)
                  IconButton(
                    tooltip: 'Delete patient',
                    onPressed: _isDeleting ? null : _confirmDelete,
                    icon: _isDeleting
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: colors.destructive),
                          )
                        : Icon(Icons.delete_outline, color: colors.destructive),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientDetailBodySkeleton extends StatelessWidget {
  const _PatientDetailBodySkeleton({required this.pageHeight});

  final double pageHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final sideCardHeight = (pageHeight - SpacingTokens.lg) / 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1080;

        if (!isWide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _skeletonCard(colors, context),
              const SizedBox(height: SpacingTokens.lg),
              SizedBox(height: sideCardHeight, child: _skeletonCard(colors, context)),
              const SizedBox(height: SpacingTokens.lg),
              SizedBox(height: sideCardHeight, child: _skeletonCard(colors, context)),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _EqualHeightRow(
                    children: [
                      _EqualHeightRowChild(child: _skeletonCard(colors, context)),
                      _EqualHeightRowChild(flex: 2, child: _skeletonCard(colors, context)),
                    ],
                  ),
                  const SizedBox(height: SpacingTokens.lg),
                  _skeletonCard(colors, context),
                ],
              ),
            ),
            const SizedBox(width: SpacingTokens.lg),
            Expanded(
              child: SizedBox(
                height: pageHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _skeletonCard(colors, context)),
                    const SizedBox(height: SpacingTokens.lg),
                    Expanded(child: _skeletonCard(colors, context)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _skeletonCard(SemanticColors colors, BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: const Padding(
        padding: EdgeInsets.all(SpacingTokens.xl),
        child: Center(child: AppSkeletonBox(width: 120, height: 16)),
      ),
    );
  }
}

class _PatientDetailBodyLoading extends StatelessWidget {
  const _PatientDetailBodyLoading({required this.pageHeight});

  final double pageHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return Stack(
      children: [
        _PatientDetailBodySkeleton(pageHeight: pageHeight),
        ColoredBox(
          color: colors.background.withValues(alpha: 0.72),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppCircularProgress(),
                const SizedBox(height: SpacingTokens.md),
                Text(
                  'Loading patient…',
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PatientDetailBodyError extends StatelessWidget {
  const _PatientDetailBodyError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Unable to load patient details',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SpacingTokens.xs),
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SpacingTokens.lg),
              AppButton(label: 'Retry', expand: false, onPressed: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatientDetailInfoRow extends StatelessWidget {
  const _PatientDetailInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: colors.mutedForeground)),
        const SizedBox(height: SpacingTokens.xs),
        Text(value, style: theme.textTheme.bodyLarge?.copyWith(color: colors.foreground)),
      ],
    );
  }
}

class _PatientDetailPermissionDenied extends StatelessWidget {
  const _PatientDetailPermissionDenied();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(SpacingTokens.lg),
        child: Text('You do not have permission to view this patient.'),
      ),
    );
  }
}
