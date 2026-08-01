import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_view.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/navigation/visit_route_extra.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_patient_banner.dart';

/// Read-only encounter chronicle for a single visit (web `VisitSummaryChronicle`).
class VisitDetailPage extends ConsumerStatefulWidget {
  const VisitDetailPage({required this.visitId, this.extra, super.key});

  final String visitId;
  final VisitRouteExtra? extra;

  @override
  ConsumerState<VisitDetailPage> createState() => _VisitDetailPageState();
}

class _VisitDetailPageState extends ConsumerState<VisitDetailPage> with SingleTickerProviderStateMixin {
  late final AnimationController _enterController;
  late final CurvedAnimation _enterAnimation;
  var _enterConfigured = false;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(vsync: this);
    _enterAnimation = CurvedAnimation(parent: _enterController, curve: AppMotionEasing.out);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enterConfigured) {
      return;
    }
    _enterConfigured = true;

    final reducedMotion = AppMotion.prefersReducedMotion(context);
    _enterController.duration = AppMotion.resolveDuration(AppMotionPreset.fadeScale, reducedMotion: reducedMotion);

    if (reducedMotion) {
      _enterController.value = 1;
      return;
    }

    _enterController.forward(from: 0);
  }

  @override
  void dispose() {
    _enterAnimation.dispose();
    _enterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessVisitDetail(auth)) {
      return const _VisitDetailPermissionDenied();
    }

    final detailAsync = ref.watch(visitDetailViewProvider(widget.visitId));

    return detailAsync.when(
      loading: () => const AppSkeletonizerZone(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSkeleton(variant: SkeletonVariant.rectangular, height: 96),
              SizedBox(height: AppSpacing.space6),
              AppSkeleton(variant: SkeletonVariant.rectangular, height: 420),
            ],
          ),
        ),
      ),
      error: (error, _) => AppErrorState(
        message: error.toString(),
        onRetry: () => ref.invalidate(visitDetailViewProvider(widget.visitId)),
      ),
      data: (view) {
        if (!view.hasBranchAccess) {
          return const _VisitDetailPermissionDenied();
        }

        final visit = view.visit;
        final safetyAsync = ref.watch(patientSafetyProvider(visit.patientId));
        final patientName = visitPatientDisplayName(visit.patientId);
        final timestamp = _chronicleTimestamp(visit);
        final formattedTimestamp = _formatChronicleDate(context, timestamp);

        final chronicle = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BreadcrumbTrailView(),
            const SizedBox(height: AppSpacing.space4),
            _ChronicleHeader(
              patientName: patientName,
              metaLine: '${visit.doctorName} · $formattedTimestamp',
              canEdit: view.canEditDocumentation,
              onCardView: () => context.nav.goVisitDocumentFromDetail(widget.visitId),
              onEdit: view.canEditDocumentation ? () => _openDocumentForEdit(context) : null,
              onPrint: () {},
              onNewVisit: () => _startNewVisit(context, visit),
            ),
            const SizedBox(height: AppSpacing.space6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 768),
                child: AppCard(
                  variant: CardVariant.raised,
                  padding: CardPadding.lg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Continuous record', style: AppTypography.h3(context)),
                      const SizedBox(height: AppSpacing.space3),
                      safetyAsync.when(
                        loading: () => AppTimeline(
                          events: _buildTimelineEvents(
                            visit: visit,
                            patientSafety: const PatientSafetyContext(),
                            formattedTimestamp: formattedTimestamp,
                          ),
                        ),
                        error: (_, _) => AppTimeline(
                          events: _buildTimelineEvents(
                            visit: visit,
                            patientSafety: const PatientSafetyContext(),
                            formattedTimestamp: formattedTimestamp,
                          ),
                        ),
                        data: (safety) => AppTimeline(
                          events: _buildTimelineEvents(
                            visit: visit,
                            patientSafety: safety,
                            formattedTimestamp: formattedTimestamp,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

        final reducedMotion = AppMotion.prefersReducedMotion(context);
        final animatedChronicle = reducedMotion
            ? chronicle
            : AppMotion.animatedPreset(
                context: context,
                preset: AppMotionPreset.fadeScale,
                animation: _enterAnimation,
                child: chronicle,
              );

        return animatedChronicle;
      },
    );
  }

  Future<void> _openDocumentForEdit(BuildContext context) async {
    context.nav.goVisitDocumentFromDetail(widget.visitId);
    try {
      await ref.read(visitDocumentationProvider(widget.visitId).future);
      ref.read(visitDocumentationProvider(widget.visitId).notifier).enterWorkspaceEditMode();
      ref.read(encounterActivePhaseProvider(widget.visitId).notifier).setPhase(EncounterPhase.subjective);
    } catch (_) {
      // Document page will surface load errors.
    }
  }

  Future<void> _startNewVisit(BuildContext context, VisitDetail visit) async {
    context.nav.goVisitDocumentFromDetail(widget.visitId);
    try {
      await ref.read(visitDocumentationProvider(widget.visitId).future);
      final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
      await notifier.reloadVisit();
      ref.read(encounterActivePhaseProvider(widget.visitId).notifier).setPhase(EncounterPhase.subjective);
      if (visit.status == VisitStatus.completed) {
        notifier.enterWorkspaceEditMode();
      }
    } catch (_) {
      // Document page will surface load errors.
    }
  }
}

class _ChronicleHeader extends StatelessWidget {
  const _ChronicleHeader({
    required this.patientName,
    required this.metaLine,
    required this.canEdit,
    required this.onCardView,
    required this.onEdit,
    required this.onPrint,
    required this.onNewVisit,
  });

  final String patientName;
  final String metaLine;
  final bool canEdit;
  final VoidCallback onCardView;
  final VoidCallback? onEdit;
  final VoidCallback onPrint;
  final VoidCallback onNewVisit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Encounter chronicle',
          style: AppTypography.overline(context).copyWith(color: context.appColors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.space1),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.start,
          spacing: AppSpacing.space4,
          runSpacing: AppSpacing.space4,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patientName, style: AppTypography.h2(context)),
                const SizedBox(height: AppSpacing.space1),
                Text(metaLine, style: AppTypography.bodySm(context).copyWith(color: context.appColors.textSecondary)),
              ],
            ),
            Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: [
                AppButton(
                  variant: AppButtonVariant.ghost,
                  leadingIcon: const Icon(Icons.grid_view_rounded, size: 16),
                  onPressed: onCardView,
                  child: const Text('Card view'),
                ),
                if (canEdit && onEdit != null)
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    leadingIcon: const Icon(Icons.restore_rounded, size: 16),
                    onPressed: onEdit,
                    child: const Text('Edit visit'),
                  ),
                AppButton(
                  variant: AppButtonVariant.secondary,
                  leadingIcon: const Icon(Icons.print_outlined, size: 16),
                  onPressed: onPrint,
                  child: const Text('Print'),
                ),
                AppButton(
                  variant: AppButtonVariant.primary,
                  leadingIcon: const Icon(Icons.arrow_back_rounded, size: 16),
                  onPressed: onNewVisit,
                  child: const Text('New visit'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _VisitDetailPermissionDenied extends StatelessWidget {
  const _VisitDetailPermissionDenied();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      title: 'Visit chronicle unavailable',
      description: 'You do not have permission to view this encounter record, or it belongs to another branch.',
    );
  }
}

DateTime _chronicleTimestamp(VisitDetail visit) {
  return visit.updatedAt ?? visit.documentation?.updatedAt ?? visit.visitDate;
}

String _formatChronicleDate(BuildContext context, DateTime timestamp) {
  final locale = Localizations.localeOf(context).toString();
  return DateFormat.yMMMEd(locale).add_jm().format(timestamp.toLocal());
}

List<TimelineEvent> _buildTimelineEvents({
  required VisitDetail visit,
  required PatientSafetyContext patientSafety,
  required String formattedTimestamp,
}) {
  final documentation = visit.documentation;

  return [
    TimelineEvent(
      time: formattedTimestamp,
      title: 'Intake',
      group: 'Encounter record',
      description: _joinSections([
        _proseField('Chief complaint', documentation?.complaint),
        _proseField('History', documentation?.history),
        _labeledInlineList(
          'Chronic conditions',
          patientSafety.chronicConditions.map((item) => _safetyLabel(item.name, item.note)).toList(),
        ),
        _labeledInlineList(
          'Allergies',
          patientSafety.allergies.map((item) => _safetyLabel(item.substance, item.reaction)).toList(),
        ),
        _labeledInlineList(
          'Current medications',
          patientSafety.currentMedications.map((item) => _safetyLabel(item.name, item.note)).toList(),
        ),
      ]),
    ),
    TimelineEvent(
      time: formattedTimestamp,
      title: 'Findings & diagnosis',
      description: _joinSections([
        _proseField('Examination', documentation?.examination),
        _labeledInlineList('Vital signs', visit.vitalSigns.map(_vitalLine).toList()),
        _proseField('Diagnosis', documentation?.diagnosis),
      ]),
    ),
    TimelineEvent(
      time: formattedTimestamp,
      title: 'Treatment',
      description: _joinSections([
        _proseField('Treatment notes', documentation?.plan),
        _labeledInlineList(
          'Investigations ordered',
          visit.investigations.map(_investigationLine).toList(),
          emptyLabel: 'None ordered',
        ),
        _labeledInlineList(
          'Prescriptions',
          visit.treatmentPlans.map(_treatmentLine).toList(),
          emptyLabel: 'None prescribed',
        ),
        _labeledAttachments('Attachments', visit.attachments.map((item) => item.label ?? item.fileType.label).toList()),
      ]),
    ),
  ];
}

String? _proseField(String label, String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }
  return '$label\n$trimmed';
}

String _labeledInlineList(String label, List<String> items, {String emptyLabel = 'None recorded'}) {
  final body = items.isEmpty ? emptyLabel : items.join(' · ');
  return '$label\n$body';
}

String _labeledAttachments(String label, List<String> items) {
  final body = items.isEmpty ? 'No attachments' : items.map((name) => '• $name').join('\n');
  return '$label\n$body';
}

String _safetyLabel(String primary, String? secondary) {
  final meta = secondary?.trim();
  if (meta == null || meta.isEmpty) {
    return primary;
  }
  return '$primary ($meta)';
}

String _vitalLine(VisitVitalSign vital) {
  final unit = vital.unit?.trim();
  final value = vital.value.trim().isEmpty ? '—' : '${vital.value}${unit == null || unit.isEmpty ? '' : ' $unit'}';
  return '${vital.name}: $value';
}

String _investigationLine(VisitInvestigation investigation) {
  final note = investigation.note?.trim();
  if (note == null || note.isEmpty) {
    return investigation.name;
  }
  return '${investigation.name} — $note';
}

String _treatmentLine(TreatmentPlanItem item) {
  final details = [
    item.dosage,
    item.frequency,
    item.duration,
  ].where((part) => part?.trim().isNotEmpty ?? false).join(', ');
  if (details.isEmpty) {
    return item.medicationName;
  }
  return '${item.medicationName} ($details)';
}

String _joinSections(List<String?> sections) {
  return sections.whereType<String>().where((section) => section.trim().isNotEmpty).join('\n\n');
}
