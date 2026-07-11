import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_description_list.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/settings/presentation/screens/_empty_screen.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_providers.dart';

class GeneralScreen extends ConsumerWidget {
  const GeneralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgAsync = ref.watch(clinicSetupOrganizationProvider);
    final colors = context.appColors;

    final org = orgAsync.asData?.value;
    final timezoneLabel = org?.timezone ?? '—';
    final currencyLabel = org?.currencyCode ?? '—';
    final organizationName = (org?.name.isNotEmpty ?? false) ? org!.name : '—';

    return EmptySettingsScreen(
      icon: Icons.business,
      title: 'General',
      description: 'Organization-wide defaults that apply to every branch.',
      body: AppCard(
        variant: CardVariant.flat,
        padding: CardPadding.lg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppDescriptionList(
              items: [
                DescriptionItem(
                  label: 'Organization name',
                  value: Text(organizationName),
                ),
                DescriptionItem(
                  label: 'Timezone',
                  value: Text(timezoneLabel),
                ),
                DescriptionItem(
                  label: 'Currency',
                  value: Text(currencyLabel),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space4),
            Text(
              'Edit these in the Setup wizard or update them here when editing is enabled.',
              style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
