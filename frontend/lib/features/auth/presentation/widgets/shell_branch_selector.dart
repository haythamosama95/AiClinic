import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Minimal active-branch selector for the placeholder shell (FR-019a).
class ShellBranchSelector extends ConsumerWidget {
  const ShellBranchSelector({super.key, required this.branches});

  final List<BranchSummary> branches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBranchId = ref.watch(authSessionProvider.select((state) => state.context?.activeBranchId));

    if (branches.isEmpty) {
      return const SizedBox.shrink();
    }

    if (branches.length == 1) {
      final branch = branches.first;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Chip(avatar: const Icon(Icons.store_outlined, size: 18), label: Text(branch.name)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: activeBranchId != null && branches.any((b) => b.id == activeBranchId)
              ? activeBranchId
              : branches.first.id,
          items: [for (final branch in branches) DropdownMenuItem(value: branch.id, child: Text(branch.name))],
          onChanged: (branchId) {
            if (branchId == null) {
              return;
            }
            ref.read(authSessionProvider.notifier).setActiveBranch(branchId);
          },
        ),
      ),
    );
  }
}
