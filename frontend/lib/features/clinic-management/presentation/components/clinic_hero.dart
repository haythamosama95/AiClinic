import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';

class _ClinicHeroCopy {
  const _ClinicHeroCopy({
    required this.clinicIdentity,
    required this.branchesLabel,
    required this.staffLabel,
    required this.activeLocationsLabel,
  });

  final String clinicIdentity;
  final String branchesLabel;
  final String staffLabel;
  final String activeLocationsLabel;
}

const _copyEn = _ClinicHeroCopy(
  clinicIdentity: 'Clinic identity',
  branchesLabel: 'Branches',
  staffLabel: 'Team members',
  activeLocationsLabel: 'Active locations',
);

const _copyAr = _ClinicHeroCopy(
  clinicIdentity: 'هوية العيادة',
  branchesLabel: 'الفروع',
  staffLabel: 'أعضاء الفريق',
  activeLocationsLabel: 'المواقع النشطة',
);

_ClinicHeroCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

class _HeroStat {
  const _HeroStat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final int value;
}

/// Identity banner with organization name, avatar, and summary stats (web `ClinicHero`).
class ClinicHero extends StatelessWidget {
  const ClinicHero({
    required this.organization,
    required this.branchCount,
    required this.staffCount,
    required this.activeBranchCount,
    super.key,
  });

  final OrganizationProfile organization;
  final int branchCount;
  final int staffCount;
  final int activeBranchCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final copy = _copyFor(Localizations.localeOf(context).languageCode);
    final currencyCode = organization.currencyCode ?? '—';
    final timezoneLabel = (organization.timezone ?? '—').replaceAll('_', ' ');
    final stats = [
      _HeroStat(icon: Icons.location_on, label: copy.branchesLabel, value: branchCount),
      _HeroStat(icon: Icons.group, label: copy.staffLabel, value: staffCount),
      _HeroStat(icon: Icons.shield, label: copy.activeLocationsLabel, value: activeBranchCount),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: const Alignment(-1, -0.5),
                    end: const Alignment(1, 0.5),
                    colors: [
                      AppColorPrimitives.teal500.withValues(alpha: 0.07),
                      AppColorPrimitives.violet500.withValues(alpha: 0.07),
                      AppColorPrimitives.teal600.withValues(alpha: 0.07),
                    ],
                    stops: const [0.0, 0.48, 1.0],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 640;

                  final identity = Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AppAvatar(name: organization.name, src: organization.logoUrl, dimension: AppSpacing.space16),
                      const SizedBox(width: AppSpacing.space5),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.apartment_outlined, size: 14, color: colors.textTertiary),
                                const SizedBox(width: AppSpacing.space2),
                                Text(
                                  copy.clinicIdentity.toUpperCase(),
                                  style: AppTypography.caption(context).copyWith(
                                    color: colors.textTertiary,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.space1),
                            Text(
                              organization.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.h2(context).copyWith(color: colors.textPrimary),
                            ),
                            const SizedBox(height: AppSpacing.space1),
                            Text('$currencyCode · $timezoneLabel', style: AppTypography.bodySm(context)),
                          ],
                        ),
                      ),
                    ],
                  );

                  final statTiles = _StatTileGrid(stats: stats, horizontal: isWide);

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: identity),
                        const SizedBox(width: AppSpacing.space6),
                        statTiles,
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      identity,
                      const SizedBox(height: AppSpacing.space6),
                      statTiles,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTileGrid extends StatelessWidget {
  const _StatTileGrid({required this.stats, this.horizontal = false});

  final List<_HeroStat> stats;
  final bool horizontal;

  static const _tileMinWidth = 124.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tiles = [for (final stat in stats) _buildTile(context, colors, stat)];

    if (horizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < tiles.length; index++) ...[
            if (index > 0) const SizedBox(width: AppSpacing.space3),
            tiles[index],
          ],
        ],
      );
    }

    return Wrap(spacing: AppSpacing.space3, runSpacing: AppSpacing.space3, children: tiles);
  }

  Widget _buildTile(BuildContext context, AppSemanticColors colors, _HeroStat stat) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: _tileMinWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceDefault.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: colors.borderSubtle.withValues(alpha: 0.6)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
          child: _StatTile(stat: stat),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final _HeroStat stat;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(stat.icon, size: 14, color: colors.textTertiary),
            const SizedBox(width: AppSpacing.space2),
            Text(stat.label, style: AppTypography.caption(context).copyWith(color: colors.textTertiary)),
          ],
        ),
        const SizedBox(height: AppSpacing.space1),
        Text(
          '${stat.value}',
          style: AppTypography.h3(
            context,
          ).copyWith(color: colors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}
