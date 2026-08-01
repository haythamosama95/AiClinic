import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_kbd.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _KbdCopy {
  const _KbdCopy({
    required this.sectionDescription,
    required this.singleKeyLabel,
    required this.singleKeyHint,
    required this.chordLabel,
    required this.chordHint,
    required this.searchHintLabel,
    required this.searchHintHint,
    required this.searchHintPrefix,
    required this.searchHintSuffix,
  });

  final String sectionDescription;
  final String singleKeyLabel;
  final String singleKeyHint;
  final String chordLabel;
  final String chordHint;
  final String searchHintLabel;
  final String searchHintHint;
  final String searchHintPrefix;
  final String searchHintSuffix;
}

const _copyEn = _KbdCopy(
  sectionDescription: 'Keyboard shortcut chips for menus, tooltips, and empty states.',
  singleKeyLabel: 'Single key',
  singleKeyHint: '<KbdKey>',
  chordLabel: 'Chord',
  chordHint: 'keys={["⌘", "K"]}',
  searchHintLabel: 'Search hint',
  searchHintHint: 'menu / Command Bar',
  searchHintPrefix: 'Press',
  searchHintSuffix: 'to search',
);

const _copyAr = _KbdCopy(
  sectionDescription: 'شرائح اختصارات لوحة المفاتيح للقوائم والتلميحات والحالات الفارغة.',
  singleKeyLabel: 'مفتاح واحد',
  singleKeyHint: '<KbdKey>',
  chordLabel: 'اختصار مركّب',
  chordHint: 'keys={["⌘", "K"]}',
  searchHintLabel: 'تلميح البحث',
  searchHintHint: 'menu / Command Bar',
  searchHintPrefix: 'اضغط',
  searchHintSuffix: 'للبحث',
);

_KbdCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Kbd showcase (web `KbdShowcase`).
class KbdShowcaseSection extends ConsumerWidget {
  const KbdShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'kbd',
      title: 'Kbd / Shortcut hint',
      description: copy.sectionDescription,
      componentName: 'Kbd · KbdKey',
      child: ShowcaseDemoGrid(
        columns: 3,
        children: [
          ShowcaseDemo(
            label: copy.singleKeyLabel,
            propsHint: copy.singleKeyHint,
            child: const Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: [
                AppKbdKey(child: Text('Enter')),
                AppKbdKey(child: Text('Esc')),
                AppKbdKey(child: Text('/')),
              ],
            ),
          ),
          ShowcaseDemo(
            label: copy.chordLabel,
            propsHint: copy.chordHint,
            child: const AppKbd(keys: ['⌘', 'K']),
          ),
          ShowcaseDemo(
            label: copy.searchHintLabel,
            propsHint: copy.searchHintHint,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(copy.searchHintPrefix, style: AppTypography.body(context).copyWith(color: colors.textSecondary)),
                const SizedBox(width: AppSpacing.space2),
                const AppKbd(keys: ['⌘', 'F']),
                const SizedBox(width: AppSpacing.space2),
                Text(copy.searchHintSuffix, style: AppTypography.body(context).copyWith(color: colors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
