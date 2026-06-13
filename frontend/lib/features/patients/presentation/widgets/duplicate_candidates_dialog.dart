import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/utils/date_format_utils.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';

/// Advisory dialog when create/update finds likely duplicate patients (V1-3).
class DuplicateCandidatesDialog extends StatelessWidget {
  const DuplicateCandidatesDialog({required this.candidates, super.key});

  final List<DuplicateCandidate> candidates;

  static Future<bool?> show(BuildContext context, {required List<DuplicateCandidate> candidates}) {
    return AppDialog.show<bool>(
      context: context,
      title: 'Similar patients found',
      barrierDismissible: false,
      body: DuplicateCandidatesDialog(candidates: candidates),
      actions: [
        AppButton(
          label: 'Go back',
          variant: AppButtonVariant.outline,
          expand: false,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(label: 'Continue anyway', expand: false, onPressed: () => Navigator.of(context).pop(true)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'These records may be the same person. Review before registering, or continue if this is a new patient.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: SpacingTokens.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: candidates.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _CandidateTile(candidate: candidates[index]),
          ),
        ),
      ],
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.candidate});

  final DuplicateCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final dob = candidate.dateOfBirth;
    final dobLabel = dob == null ? null : formatDate(dob);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(candidate.fullName, style: theme.titleSmall),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            [
              if (candidate.phone != null && candidate.phone!.isNotEmpty) candidate.phone,
              ?dobLabel,
              candidate.branchName,
            ].whereType<String>().join(' · '),
            style: theme.bodySmall,
          ),
        ],
      ),
    );
  }
}
