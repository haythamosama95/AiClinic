import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _MoneyDisplayCopy {
  const _MoneyDisplayCopy({required this.variants});

  final String variants;
}

const _copyEn = _MoneyDisplayCopy(variants: 'Variants');

const _copyAr = _MoneyDisplayCopy(variants: 'المتغيرات');

_MoneyDisplayCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Money display showcase (web `MoneyDisplayShowcase`).
class MoneyDisplayShowcaseSection extends ConsumerWidget {
  const MoneyDisplayShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'money-display',
      title: 'Money display',
      componentName: 'MoneyDisplay',
      child: ShowcaseDemo(
        label: copy.variants,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppMoneyDisplay(amount: Money.parse('1250.50'), currency: 'EGP'),
            const SizedBox(height: AppSpacing.space2),
            AppMoneyDisplay(amount: Money.parse('1250.50'), currency: 'EGP', emphasis: true),
            const SizedBox(height: AppSpacing.space2),
            AppMoneyDisplay(amount: Money.parse('-320'), currency: 'EGP', negative: true),
          ],
        ),
      ),
    );
  }
}
