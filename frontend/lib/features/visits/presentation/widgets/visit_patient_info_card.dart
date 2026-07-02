import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_gender_avatar.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Patient demographics header for visit detail and documentation pages.
class VisitPatientBasicInfoCard extends ConsumerWidget {
  const VisitPatientBasicInfoCard({required this.patientId, super.key});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientAsync = ref.watch(patientDetailProvider(patientId));

    return patientAsync.when(
      loading: () => const _VisitPatientBasicInfoShell(child: _VisitPatientBasicInfoLoading()),
      error: (error, _) => const _VisitPatientBasicInfoShell(
        child: _VisitPatientBasicInfoMessage(message: 'Unable to load patient information.'),
      ),
      data: (detail) => _VisitPatientBasicInfoContent(detail: detail),
    );
  }
}

class _VisitPatientBasicInfoContent extends StatelessWidget {
  const _VisitPatientBasicInfoContent({required this.detail});

  final PatientDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return _VisitPatientBasicInfoShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PatientGenderAvatar(gender: detail.gender, size: 48),
              const SizedBox(width: SpacingTokens.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(detail.fullName, style: theme.title()),
                    const SizedBox(height: SpacingTokens.xs),
                    Text('ID ${PatientPresentationFormatting.displayId(detail.id)}', style: theme.caption()),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text('Basic information', style: theme.title(size: 13))),
              const SizedBox(width: SpacingTokens.sm),
              Flexible(
                child: Text(
                  'Registered ${PatientPresentationFormatting.dateTime.format(detail.createdAt)}',
                  style: theme.caption(),
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.md),
          _PatientInfoGrid(
            items: [
              _PatientInfoItem(label: 'Gender', value: detail.gender?.label ?? '—'),
              _PatientInfoItem(
                label: 'Date of birth',
                value: PatientPresentationFormatting.dateOfBirthLabel(detail.dateOfBirth),
              ),
              _PatientInfoItem(label: 'Phone', value: PatientPresentationFormatting.orDash(detail.phone)),
              _PatientInfoItem(label: 'Marital status', value: detail.maritalStatus?.label ?? '—'),
            ],
          ),
        ],
      ),
    );
  }
}

class _VisitPatientBasicInfoShell extends StatelessWidget {
  const _VisitPatientBasicInfoShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return AppNotchedCard(
      titleIcon: Icons.person_outline,
      title: Text('Patient', style: theme.title()),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(SpacingTokens.md, 0, SpacingTokens.md, SpacingTokens.md),
        child: child,
      ),
    );
  }
}

class _VisitPatientBasicInfoLoading extends StatelessWidget {
  const _VisitPatientBasicInfoLoading();

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: theme.tile, shape: BoxShape.circle),
            ),
            const SizedBox(width: SpacingTokens.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 18,
                    width: 180,
                    decoration: BoxDecoration(color: theme.tile, borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Container(
                    height: 14,
                    width: 96,
                    decoration: BoxDecoration(color: theme.tile, borderRadius: BorderRadius.circular(4)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: SpacingTokens.lg),
        Container(
          height: 14,
          width: 140,
          decoration: BoxDecoration(color: theme.tile, borderRadius: BorderRadius.circular(4)),
        ),
      ],
    );
  }
}

class _VisitPatientBasicInfoMessage extends StatelessWidget {
  const _VisitPatientBasicInfoMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
      child: Text(message, style: context.visitTheme.caption(), textAlign: TextAlign.center),
    );
  }
}

@immutable
class _PatientInfoItem {
  const _PatientInfoItem({required this.label, required this.value});

  final String label;
  final String value;
}

class _PatientInfoGrid extends StatelessWidget {
  const _PatientInfoGrid({required this.items});

  final List<_PatientInfoItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth >= 360 ? 2 : 1;
        final itemWidth = (constraints.maxWidth - (columnCount - 1) * SpacingTokens.md) / columnCount;

        return Wrap(
          spacing: SpacingTokens.md,
          runSpacing: SpacingTokens.md,
          children: [
            for (final item in items)
              SizedBox(
                width: columnCount == 1 ? constraints.maxWidth : itemWidth,
                child: _PatientInfoRow(label: item.label, value: item.value),
              ),
          ],
        );
      },
    );
  }
}

class _PatientInfoRow extends StatelessWidget {
  const _PatientInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.eyebrow(size: 10)),
        const SizedBox(height: SpacingTokens.xs),
        Text(value, style: theme.body()),
      ],
    );
  }
}
