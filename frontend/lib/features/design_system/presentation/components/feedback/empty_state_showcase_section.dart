import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

const _variants = <EmptyStateVariant>[
  EmptyStateVariant.firstRun,
  EmptyStateVariant.noResults,
  EmptyStateVariant.noAccess,
  EmptyStateVariant.error,
];

class _EmptyStateCopy {
  const _EmptyStateCopy({required this.addPatient});

  final String addPatient;
}

const _copyEn = _EmptyStateCopy(addPatient: 'Add patient');
const _copyAr = _EmptyStateCopy(addPatient: 'إضافة مريض');

_EmptyStateCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Empty states showcase (web `EmptyStateShowcase`).
class EmptyStateShowcaseSection extends ConsumerWidget {
  const EmptyStateShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'empty-state',
      title: 'Empty states',
      componentName: 'EmptyState',
      child: ShowcaseDemoGrid(
        columns: 2,
        children: [
          for (final variant in _variants)
            AppEmptyState(
              variant: variant,
              action: variant == EmptyStateVariant.firstRun
                  ? EmptyStateAction(label: copy.addPatient, onPressed: () {})
                  : null,
              shortcutHint: variant == EmptyStateVariant.firstRun ? const ['⌘', 'N'] : null,
            ),
        ],
      ),
    );
  }
}
