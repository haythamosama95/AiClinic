import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';

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
      loading: () => _PatientDetailLoadingView(preview: preview, onBack: () => _goBack(context)),
      error: (error, _) => _PatientDetailErrorView(
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

class _PatientDetailContentView extends StatelessWidget {
  const _PatientDetailContentView({required this.detail, required this.onBack});

  final PatientDetail detail;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return _PatientDetailScaffold(
      onBack: onBack,
      header: _PatientDetailHeader(
        fullName: detail.fullName,
        id: detail.id,
        phone: detail.phone,
        dateOfBirth: detail.dateOfBirth,
        gender: detail.gender,
      ),
      body: _PatientDetailBody(detail: detail),
    );
  }
}

class _PatientDetailLoadingView extends StatelessWidget {
  const _PatientDetailLoadingView({required this.onBack, this.preview});

  final VoidCallback onBack;
  final PatientListItem? preview;

  @override
  Widget build(BuildContext context) {
    return _PatientDetailScaffold(
      onBack: onBack,
      header: preview != null
          ? _PatientDetailHeader(
              fullName: preview!.fullName,
              id: preview!.id,
              phone: preview!.phone,
              dateOfBirth: preview!.dateOfBirth,
              gender: preview!.gender,
            )
          : const _PatientDetailHeaderSkeleton(),
      body: const AppDeferredLoading(
        isLoading: true,
        placeholder: _PatientDetailBodySkeleton(),
        loading: _PatientDetailBodyLoading(),
      ),
    );
  }
}

class _PatientDetailErrorView extends StatelessWidget {
  const _PatientDetailErrorView({required this.message, required this.onBack, required this.onRetry});

  final String message;
  final VoidCallback onBack;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _PatientDetailScaffold(
      onBack: onBack,
      body: _PatientDetailBodyError(message: message, onRetry: onRetry),
    );
  }
}

class _PatientDetailScaffold extends StatelessWidget {
  const _PatientDetailScaffold({required this.onBack, required this.body, this.header});

  final VoidCallback onBack;
  final Widget? header;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PatientDetailTopBar(onBack: onBack),
                    SizedBox(height: header == null ? SpacingTokens.lg : SpacingTokens.md),
                    if (header != null) ...[header!, const SizedBox(height: SpacingTokens.lg)],
                    Expanded(child: body),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PatientDetailTopBar extends StatelessWidget {
  const _PatientDetailTopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        AppIconButton(icon: const Icon(Icons.arrow_back, size: 20), tooltip: 'Back to patients', onPressed: onBack),
        const SizedBox(width: SpacingTokens.sm),
        Text('Patient detail', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _PatientDetailHeader extends StatelessWidget {
  const _PatientDetailHeader({required this.fullName, required this.id, this.phone, this.dateOfBirth, this.gender});

  final String fullName;
  final String id;
  final String? phone;
  final DateTime? dateOfBirth;
  final PatientGender? gender;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final ageGender = PatientPresentationFormatting.ageGenderLabel(
      age: PatientPresentationFormatting.ageYears(dateOfBirth),
      gender: gender,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Row(
          children: [
            _PatientAvatar(name: fullName),
            const SizedBox(width: SpacingTokens.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: SpacingTokens.xs),
                  Text(
                    'Patient ID ${PatientPresentationFormatting.displayId(id)}',
                    style: theme.textTheme.labelSmall?.copyWith(color: colors.mutedForeground),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Text(
                    '${PatientPresentationFormatting.orDash(phone)} · $ageGender',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientDetailHeaderSkeleton extends StatelessWidget {
  const _PatientDetailHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: const Padding(
        padding: EdgeInsets.all(SpacingTokens.lg),
        child: Row(
          children: [
            AppSkeletonCircle(size: 44),
            SizedBox(width: SpacingTokens.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeletonBox(width: 180, height: 16),
                  SizedBox(height: SpacingTokens.xs),
                  AppSkeletonBox(width: 120, height: 12),
                  SizedBox(height: SpacingTokens.sm),
                  AppSkeletonBox(width: 160, height: 12),
                ],
              ),
            ),
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
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PatientDetailInfoRow(label: 'Phone', value: PatientPresentationFormatting.orDash(detail.phone)),
            const SizedBox(height: SpacingTokens.lg),
            _PatientDetailInfoRow(
              label: 'Date of birth',
              value: PatientPresentationFormatting.dateOfBirthLabel(detail.dateOfBirth),
            ),
            const SizedBox(height: SpacingTokens.lg),
            _PatientDetailInfoRow(label: 'Gender', value: detail.gender?.label ?? '—'),
            const SizedBox(height: SpacingTokens.lg),
            _PatientDetailInfoRow(label: 'Marital status', value: detail.maritalStatus?.label ?? '—'),
            const SizedBox(height: SpacingTokens.lg),
            _PatientDetailInfoRow(label: 'Branch', value: detail.branchName),
            const SizedBox(height: SpacingTokens.lg),
            _PatientDetailInfoRow(label: 'Notes', value: PatientPresentationFormatting.orDash(detail.notes)),
            const SizedBox(height: SpacingTokens.lg),
            _PatientDetailInfoRow(
              label: 'Created',
              value: PatientPresentationFormatting.dateTime.format(detail.createdAt),
            ),
            const SizedBox(height: SpacingTokens.lg),
            _PatientDetailInfoRow(
              label: 'Last updated',
              value: PatientPresentationFormatting.dateTime.format(detail.updatedAt),
            ),
            const SizedBox(height: SpacingTokens.lg),
            _PatientDetailInfoRow(
              label: 'Created by',
              value: PatientPresentationFormatting.orDash(detail.createdByDisplay),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientDetailBodySkeleton extends StatelessWidget {
  const _PatientDetailBodySkeleton();

  static const _labels = ['Phone', 'Date of birth', 'Gender', 'Marital status', 'Branch', 'Notes'];

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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < _labels.length; index++) ...[
              if (index > 0) const SizedBox(height: SpacingTokens.lg),
              Text(_labels[index], style: theme.textTheme.labelMedium?.copyWith(color: colors.mutedForeground)),
              const SizedBox(height: SpacingTokens.xs),
              AppSkeletonBox(width: index.isEven ? 160 : 120, height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _PatientDetailBodyLoading extends StatelessWidget {
  const _PatientDetailBodyLoading();

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        const _PatientDetailBodySkeleton(),
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

class _PatientAvatar extends StatelessWidget {
  const _PatientAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final initials = _initialsFor(name);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondary,
        borderRadius: BorderRadius.circular(context.shapeTokens.sm),
        border: Border.all(color: colors.border),
      ),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Text(
            initials,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colors.secondaryForeground, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  static String _initialsFor(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
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
