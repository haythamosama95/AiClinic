import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';

/// Shown when [set_branch_active] returns `LAST_ACTIVE_BRANCH` (FR-003a).
Future<void> showLastActiveBranchBlockedDialog(BuildContext context, {required String branchId}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Cannot deactivate branch'),
        content: const Text(
          'This is the only active branch in your clinic. Deactivate another branch first, '
          'or edit this branch instead of deactivating it.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.go(AppRoutes.settingsBranchEdit(branchId));
            },
            child: const Text('Edit branch'),
          ),
        ],
      );
    },
  );
}
