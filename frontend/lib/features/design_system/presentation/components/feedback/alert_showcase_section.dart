import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_alert.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

const _variants = <AppAlertVariant>[
  AppAlertVariant.info,
  AppAlertVariant.success,
  AppAlertVariant.warning,
  AppAlertVariant.danger,
  AppAlertVariant.ai,
];

class _AlertCopy {
  const _AlertCopy({
    required this.infoTitle,
    required this.successTitle,
    required this.warningTitle,
    required this.dangerTitle,
    required this.aiTitle,
    required this.bodyForVariant,
  });

  final String infoTitle;
  final String successTitle;
  final String warningTitle;
  final String dangerTitle;
  final String aiTitle;
  final String Function(String variant) bodyForVariant;

  String titleFor(AppAlertVariant variant) => switch (variant) {
    AppAlertVariant.info => infoTitle,
    AppAlertVariant.success => successTitle,
    AppAlertVariant.warning => warningTitle,
    AppAlertVariant.danger => dangerTitle,
    AppAlertVariant.ai => aiTitle,
  };

  String bodyFor(AppAlertVariant variant) => bodyForVariant(variant.name);
}

const _copyEn = _AlertCopy(
  infoTitle: 'Info notice',
  successTitle: 'Success notice',
  warningTitle: 'Warning notice',
  dangerTitle: 'Danger notice',
  aiTitle: 'AI suggestions require your approval',
  bodyForVariant: _bodyForVariantEn,
);

const _copyAr = _AlertCopy(
  infoTitle: 'إشعار معلوماتي',
  successTitle: 'إشعار نجاح',
  warningTitle: 'إشعار تحذير',
  dangerTitle: 'إشعار خطر',
  aiTitle: 'اقتراحات الذكاء الاصطناعي تتطلب موافقتك',
  bodyForVariant: _bodyForVariantAr,
);

String _bodyForVariantEn(String variant) => 'Contextual message for the $variant variant.';

String _bodyForVariantAr(String variant) => 'رسالة سياقية لمتغير $variant.';

_AlertCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Inline alert showcase (web `AlertShowcase`).
class AlertShowcaseSection extends ConsumerWidget {
  const AlertShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'alert',
      title: 'Inline alert',
      componentName: 'Alert',
      child: Column(
        children: [
          for (var i = 0; i < _variants.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.space4),
            AppAlert(
              variant: _variants[i],
              title: copy.titleFor(_variants[i]),
              dismissible: true,
              child: Text(copy.bodyFor(_variants[i])),
            ),
          ],
        ],
      ),
    );
  }
}
