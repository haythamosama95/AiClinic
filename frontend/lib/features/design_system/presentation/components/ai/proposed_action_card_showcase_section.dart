import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_proposed_action_card.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

const _proposedStates = <ProposedActionState>[
  ProposedActionState.proposed,
  ProposedActionState.editing,
  ProposedActionState.submitting,
  ProposedActionState.approved,
  ProposedActionState.rejected,
  ProposedActionState.failed,
];

class _ProposedActionCardCopy {
  const _ProposedActionCardCopy({
    required this.sectionDescription,
    required this.title,
    required this.summary,
    required this.errorMessage,
    required this.patientLabel,
    required this.dateLabel,
    required this.timeLabel,
    required this.patientValue,
    required this.dateValue,
    required this.timeValue,
    required this.statesTitle,
  });

  final String sectionDescription;
  final String title;
  final String summary;
  final String errorMessage;
  final String patientLabel;
  final String dateLabel;
  final String timeLabel;
  final String patientValue;
  final String dateValue;
  final String timeValue;
  final String statesTitle;
}

const _copyEn = _ProposedActionCardCopy(
  sectionDescription: 'Human-gated AI actions. Approve runs the validated backend path.',
  title: 'Book appointment',
  summary: 'Schedule a follow-up for Layla Hassan with Dr. Ahmed on Jul 8 at 10:00 AM.',
  errorMessage: 'Doctor is not available at the selected time.',
  patientLabel: 'Patient',
  dateLabel: 'Date',
  timeLabel: 'Time',
  patientValue: 'Layla Hassan',
  dateValue: 'Jul 8, 2026',
  timeValue: '10:00 AM',
  statesTitle: 'States',
);

const _copyAr = _ProposedActionCardCopy(
  sectionDescription: 'إجراءات ذكاء اصطناعي تتطلب موافقة بشرية. الموافقة تشغّل المسار الآمن في الخادم.',
  title: 'حجز موعد',
  summary: 'جدولة متابعة ليلى حسن مع د. أحمد في 8 يوليو الساعة 10:00 ص.',
  errorMessage: 'الطبيب غير متاح في الوقت المحدد.',
  patientLabel: 'المريض',
  dateLabel: 'التاريخ',
  timeLabel: 'الوقت',
  patientValue: 'Layla Hassan',
  dateValue: 'Jul 8, 2026',
  timeValue: '10:00 AM',
  statesTitle: 'الحالات',
);

_ProposedActionCardCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

String _stateLabel(ProposedActionState state) => state.name;

/// Proposed action card showcase (web `ProposedActionCardShowcase` in `AiShowcase.tsx`).
class ProposedActionCardShowcaseSection extends ConsumerStatefulWidget {
  const ProposedActionCardShowcaseSection({super.key});

  @override
  ConsumerState<ProposedActionCardShowcaseSection> createState() => _ProposedActionCardShowcaseSectionState();
}

class _ProposedActionCardShowcaseSectionState extends ConsumerState<ProposedActionCardShowcaseSection> {
  ProposedActionState _activeState = ProposedActionState.proposed;

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'proposed-action-card',
      title: 'Proposed action card',
      description: copy.sectionDescription,
      componentName: 'ProposedActionCard',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShowcaseVariantMatrix(
            title: copy.statesTitle,
            children: [
              for (final state in _proposedStates)
                _StateButton(
                  label: _stateLabel(state),
                  onPressed: () => setState(() => _activeState = state),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space6),
          SizedBox(
            width: 448,
            child: AppProposedActionCard(
              title: copy.title,
              summary: copy.summary,
              state: _activeState,
              errorMessage: _activeState == ProposedActionState.failed ? copy.errorMessage : null,
              fields: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppFormField(
                    id: 'pa-patient',
                    label: copy.patientLabel,
                    child: AppTextInput(
                      id: 'pa-patient',
                      readOnly: true,
                      initialValue: copy.patientValue,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  AppFormField(
                    id: 'pa-date',
                    label: copy.dateLabel,
                    child: AppTextInput(
                      id: 'pa-date',
                      initialValue: copy.dateValue,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  AppFormField(
                    id: 'pa-time',
                    label: copy.timeLabel,
                    child: AppTextInput(
                      id: 'pa-time',
                      initialValue: copy.timeValue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateButton extends StatefulWidget {
  const _StateButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_StateButton> createState() => _StateButtonState();
}

class _StateButtonState extends State<_StateButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered ? colors.surfaceHover : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.borderDefault),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space1),
              child: Text(
                widget.label,
                style: AppTypography.caption(context).copyWith(color: colors.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
