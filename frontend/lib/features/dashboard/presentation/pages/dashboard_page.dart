import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Clinic dashboard landing page inside the authenticated shell.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppNotchedCard(
                    title: Text('Appointments', style: theme.textTheme.titleMedium),
                    description: Text(
                      'Today\'s schedule',
                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                    ),
                    actions: [
                      AppIconButton(
                        icon: const Icon(Icons.calendar_month_outlined),
                        tooltip: 'Open calendar',
                        onPressed: () {},
                      ),
                    ],
                    body: _AppointmentsSummary(colors: colors, theme: theme),
                  ),
                ),
                const SizedBox(width: SpacingTokens.lg),
                Expanded(
                  child: AppNotchedCard(
                    title: Text('Queue', style: theme.textTheme.titleMedium),
                    description: Text(
                      'Patients waiting',
                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                    ),
                    actions: [
                      AppIconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh queue', onPressed: () {}),
                    ],
                    body: const _QueueList(),
                  ),
                ),
                const SizedBox(width: SpacingTokens.lg),
                Expanded(
                  child: AppNotchedCard(
                    title: Text('Revenue', style: theme.textTheme.titleMedium),
                    description: Text(
                      'Month to date',
                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                    ),
                    actions: [
                      AppIconButton(icon: const Icon(Icons.trending_up), tooltip: 'View reports', onPressed: () {}),
                    ],
                    body: _RevenueSummary(colors: colors, theme: theme),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppNotchedCard(
                    title: Text('Patients', style: theme.textTheme.titleMedium),
                    description: Text(
                      'Registry overview',
                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                    ),
                    actions: [
                      AppIconButton(icon: const Icon(Icons.search), tooltip: 'Search patients', onPressed: () {}),
                      AppIconButton(
                        icon: const Icon(Icons.person_add_outlined),
                        tooltip: 'Add patient',
                        onPressed: () {},
                      ),
                      AppIconButton(icon: const Icon(Icons.filter_list), tooltip: 'Filter list', onPressed: () {}),
                    ],
                    body: _PatientsSummary(colors: colors, theme: theme),
                  ),
                ),
                const SizedBox(width: SpacingTokens.lg),
                Expanded(
                  child: AppNotchedCard(
                    title: Text('Tasks', style: theme.textTheme.titleMedium),
                    description: Text(
                      'Team follow-ups',
                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                    ),
                    actions: [
                      AppIconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit task', onPressed: () {}),
                      AppIconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete task', onPressed: () {}),
                      AppIconButton(icon: const Icon(Icons.share_outlined), tooltip: 'Assign task', onPressed: () {}),
                    ],
                    body: const _TasksList(),
                  ),
                ),
                const SizedBox(width: SpacingTokens.lg),
                Expanded(
                  child: AppNotchedCard(
                    title: Text('Inventory', style: theme.textTheme.titleMedium),
                    description: Text(
                      'Stock alerts',
                      style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                    ),
                    actions: [
                      AppIconButton(icon: const Icon(Icons.add_shopping_cart), tooltip: 'Reorder', onPressed: () {}),
                      AppIconButton(
                        icon: const Icon(Icons.download_outlined),
                        tooltip: 'Export list',
                        onPressed: () {},
                      ),
                    ],
                    body: _InventorySummary(colors: colors, theme: theme),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.lg),
            AppNotchedCard(
              title: Text('Billing overview', style: theme.textTheme.titleMedium),
              description: Text(
                'Collections and adjustments',
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
              ),
              actions: [
                AppButton(
                  label: 'Last 6 months',
                  icon: const Icon(Icons.expand_more, size: 18),
                  variant: AppButtonVariant.ghost,
                  size: AppFieldSize.sm,
                  onPressed: () {},
                ),
                AppIconButton(
                  icon: const Icon(Icons.filter_list_outlined),
                  tooltip: 'Filter billing',
                  onPressed: () {},
                ),
              ],
              body: _BillingOverview(colors: colors, theme: theme),
            ),
            const SizedBox(height: SpacingTokens.lg),
            Directionality(
              textDirection: TextDirection.rtl,
              child: AppNotchedCard(
                title: Text('جدول الموظفين', style: theme.textTheme.titleMedium),
                description: Text(
                  'ورديات اليوم',
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                ),
                actions: [
                  AppIconButton(
                    icon: const Icon(Icons.calendar_month_outlined),
                    tooltip: 'فتح التقويم',
                    onPressed: () {},
                  ),
                  AppIconButton(icon: const Icon(Icons.groups_outlined), tooltip: 'عرض الفريق', onPressed: () {}),
                ],
                body: _RtlStaffSchedule(theme: theme),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentsSummary extends StatelessWidget {
  const _AppointmentsSummary({required this.colors, required this.theme});

  final SemanticColors colors;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('12', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: SpacingTokens.sm),
        const AppBadge(label: '3 upcoming', variant: AppBadgeVariant.primary),
        const SizedBox(height: SpacingTokens.md),
        Text(
          'Next: 10:30 AM — Sarah Johnson',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
        ),
      ],
    );
  }
}

class _QueueList extends StatelessWidget {
  const _QueueList();

  @override
  Widget build(BuildContext context) {
    return AppTileGroup(
      tiles: [
        AppTileSpec(
          title: 'Ahmed Hassan',
          subtitle: 'Check-up',
          details: '12 min',
          prefix: const Icon(Icons.person_outline, size: 20),
        ),
        AppTileSpec(
          title: 'Lina Farouk',
          subtitle: 'Follow-up',
          details: '28 min',
          prefix: const Icon(Icons.person_outline, size: 20),
        ),
        AppTileSpec(
          title: 'Omar Khalil',
          subtitle: 'Consultation',
          details: '41 min',
          prefix: const Icon(Icons.person_outline, size: 20),
        ),
      ],
    );
  }
}

class _RevenueSummary extends StatelessWidget {
  const _RevenueSummary({required this.colors, required this.theme});

  final SemanticColors colors;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(r'$18,420', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: SpacingTokens.sm),
        const AppBadge(
          label: '+12% vs last month',
          variant: AppBadgeVariant.accent,
          icon: Icon(Icons.arrow_upward, size: 12),
        ),
        const SizedBox(height: SpacingTokens.lg),
        Text('Monthly target', style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground)),
        const SizedBox(height: SpacingTokens.xs),
        const AppDeterminateProgress(value: 0.72),
        const SizedBox(height: SpacingTokens.xs),
        Text('72% of \$25,600 goal', style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground)),
      ],
    );
  }
}

class _PatientsSummary extends StatelessWidget {
  const _PatientsSummary({required this.colors, required this.theme});

  final SemanticColors colors;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('1,248', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: SpacingTokens.sm),
        Wrap(
          spacing: SpacingTokens.sm,
          runSpacing: SpacingTokens.sm,
          children: const [
            AppBadge(label: '24 new this week', variant: AppBadgeVariant.primary),
            AppBadge(label: 'Active', variant: AppBadgeVariant.outline),
          ],
        ),
        const SizedBox(height: SpacingTokens.md),
        Text(
          '18 profiles need document updates',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
        ),
      ],
    );
  }
}

class _TasksList extends StatelessWidget {
  const _TasksList();

  @override
  Widget build(BuildContext context) {
    return AppTileGroup(
      tiles: [
        AppTileSpec(
          title: 'Call lab for Hassan results',
          subtitle: 'Due today',
          prefix: const Icon(Icons.task_alt_outlined, size: 20),
          suffix: const AppBadge(label: 'High', variant: AppBadgeVariant.accent, dense: true),
        ),
        AppTileSpec(
          title: 'Review prescription refill',
          subtitle: 'Dr. Nasser',
          prefix: const Icon(Icons.medication_outlined, size: 20),
        ),
        AppTileSpec(
          title: 'Confirm tomorrow\'s surgeries',
          subtitle: '3 pending',
          prefix: const Icon(Icons.event_note_outlined, size: 20),
        ),
      ],
    );
  }
}

class _BillingOverview extends StatelessWidget {
  const _BillingOverview({required this.colors, required this.theme});

  final SemanticColors colors;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r'$42,180', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: SpacingTokens.sm),
              const AppBadge(
                label: '+8.2% vs prior period',
                variant: AppBadgeVariant.accent,
                icon: Icon(Icons.arrow_upward, size: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: SpacingTokens.lg),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BillingLegendItem(color: colors.primary, label: 'Insurance claims', theme: theme),
            const SizedBox(height: SpacingTokens.sm),
            _BillingLegendItem(color: colors.accent, label: 'Patient payments', theme: theme),
          ],
        ),
      ],
    );
  }
}

class _BillingLegendItem extends StatelessWidget {
  const _BillingLegendItem({required this.color, required this.label, required this.theme});

  final Color color;
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _InventorySummary extends StatelessWidget {
  const _InventorySummary({required this.colors, required this.theme});

  final SemanticColors colors;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppAlert(
          title: 'Low stock',
          subtitle: 'Surgical gloves and saline bags are below threshold.',
          icon: Icon(Icons.warning_amber_outlined),
        ),
        const SizedBox(height: SpacingTokens.md),
        Text('5 items need reorder', style: theme.textTheme.bodyMedium),
        const SizedBox(height: SpacingTokens.xs),
        Text('Last restock: 4 days ago', style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground)),
      ],
    );
  }
}

class _RtlStaffSchedule extends StatelessWidget {
  const _RtlStaffSchedule({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return AppTileGroup(
      tiles: [
        AppTileSpec(
          title: 'د. ناصر — عيادة عامة',
          subtitle: '08:00 – 14:00',
          details: '6 مواعيد',
          prefix: const Icon(Icons.person_outline, size: 20),
        ),
        AppTileSpec(
          title: 'د. ليلى — طب الأطفال',
          subtitle: '09:00 – 15:00',
          details: '4 مواعيد',
          prefix: const Icon(Icons.person_outline, size: 20),
        ),
        AppTileSpec(
          title: 'الممرضة سارة — الاستقبال',
          subtitle: '07:30 – 15:30',
          details: 'متاحة',
          prefix: const Icon(Icons.person_outline, size: 20),
        ),
      ],
    );
  }
}
