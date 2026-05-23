import 'package:flutter/material.dart';

import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';

/// Advisory dialog when create/update finds likely duplicate patients (V1-3).
class DuplicateCandidatesDialog extends StatelessWidget {
  const DuplicateCandidatesDialog({required this.candidates, super.key});

  final List<DuplicateCandidate> candidates;

  static Future<bool?> show(BuildContext context, {required List<DuplicateCandidate> candidates}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DuplicateCandidatesDialog(candidates: candidates),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Similar patients found'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'These records may be the same person. Review before registering, or continue if this is a new patient.',
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: candidates.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) => _CandidateTile(candidate: candidates[index]),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Go back')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continue anyway')),
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
    final dobLabel = dob == null
        ? null
        : '${dob.year}-${dob.month.toString().padLeft(2, '0')}-${dob.day.toString().padLeft(2, '0')}';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(candidate.fullName, style: theme.titleSmall),
      subtitle: Text(
        [
          if (candidate.phone != null && candidate.phone!.isNotEmpty) candidate.phone,
          if (dobLabel != null) dobLabel,
          candidate.branchName,
        ].whereType<String>().join(' · '),
        style: theme.bodySmall,
      ),
    );
  }
}
