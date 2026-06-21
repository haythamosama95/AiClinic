import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';

/// Column 2 — checked-in patients ordered by wait priority.
class AppointmentQueueWaitingColumn extends ConsumerStatefulWidget {
  const AppointmentQueueWaitingColumn({required this.items, required this.now, super.key});

  final List<AppointmentListItem> items;
  final DateTime now;

  @override
  ConsumerState<AppointmentQueueWaitingColumn> createState() => _AppointmentQueueWaitingColumnState();
}

class _AppointmentQueueWaitingColumnState extends ConsumerState<AppointmentQueueWaitingColumn> {
  String? _busyItemId;

  Future<void> _callNext(AppointmentListItem item) async {
    if (_busyItemId != null) {
      return;
    }

    final timezone = ref.read(authSessionProvider).context?.organizationTimezone?.trim() ?? 'UTC';
    final target = forwardStatusTargetFor(item, organizationTimezone: timezone);
    if (target == null) {
      return;
    }

    setState(() => _busyItemId = item.id);
    try {
      await ref.read(appointmentRepositoryProvider).updateAppointmentStatus(appointmentId: item.id, newStatus: target);
      if (!mounted) {
        return;
      }
      ref.invalidate(appointmentQueueProvider);
      ref.invalidate(appointmentCalendarProvider);
      AppToast.success(context, message: '${item.patientName} sent to exam room.');
    } on RpcFailure catch (error) {
      if (mounted) {
        AppToast.error(context, message: appointmentMessageForRpc(error));
      }
    } catch (_) {
      if (mounted) {
        AppToast.error(context, message: 'Unable to update status. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _busyItemId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAdvance = ref.watch(permissionServiceProvider).canCreateAppointments();

    return _WaitingColumnShell(
      title: 'Checked-in & waiting',
      subtitle: 'Ordered by arrival — longest waits first',
      child: widget.items.isEmpty
          ? const _WaitingEmptyState()
          : ListView.separated(
              itemCount: widget.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: SpacingTokens.sm),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                final (waitLabel, tier) = AppointmentQueueDisplay.waitPresentation(item, now: widget.now);
                return _WaitingRow(
                  item: item,
                  waitLabel: waitLabel,
                  tier: tier,
                  isBusy: _busyItemId == item.id,
                  canCallNext: canAdvance,
                  onCallNext: () => _callNext(item),
                  onTap: () => AppNavigator(context).pushAppointmentDetail(item.id),
                );
              },
            ),
    );
  }
}

class _WaitingColumnShell extends StatelessWidget {
  const _WaitingColumnShell({required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(SpacingTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.md, SpacingTokens.md, SpacingTokens.md, SpacingTokens.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: SpacingTokens.xs / 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(padding: const EdgeInsets.all(SpacingTokens.sm), child: child),
          ),
        ],
      ),
    );
  }
}

class _WaitingRow extends StatelessWidget {
  const _WaitingRow({
    required this.item,
    required this.waitLabel,
    required this.tier,
    required this.isBusy,
    required this.canCallNext,
    required this.onCallNext,
    required this.onTap,
  });

  final AppointmentListItem item;
  final String waitLabel;
  final AppointmentQueueWaitTier tier;
  final bool isBusy;
  final bool canCallNext;
  final VoidCallback onCallNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final (background, waitColor, borderColor) = switch (tier) {
      AppointmentQueueWaitTier.normal => (colors.card, colors.mutedForeground, colors.border),
      AppointmentQueueWaitTier.warning => (const Color(0xFFFFF7ED), const Color(0xFFEA580C), const Color(0xFFFDBA74)),
      AppointmentQueueWaitTier.critical => (const Color(0xFFFEF2F2), const Color(0xFFDC2626), const Color(0xFFFECACA)),
    };

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(SpacingTokens.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SpacingTokens.sm),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SpacingTokens.sm),
            border: Border.all(color: borderColor, width: tier == AppointmentQueueWaitTier.normal ? 1 : 1.5),
          ),
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.patientName,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: SpacingTokens.xs / 2),
                        Text(
                          item.doctorDisplayName,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  if (tier == AppointmentQueueWaitTier.critical)
                    Padding(
                      padding: const EdgeInsets.only(left: SpacingTokens.sm),
                      child: AppBadge(label: 'Critical', variant: AppBadgeVariant.outline, dense: true),
                    ),
                ],
              ),
              const SizedBox(height: SpacingTokens.sm),
              Text(
                waitLabel,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: waitColor,
                  fontWeight: tier == AppointmentQueueWaitTier.normal ? FontWeight.w500 : FontWeight.w700,
                ),
              ),
              if (canCallNext) ...[
                const SizedBox(height: SpacingTokens.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppButton(
                    label: 'Call next',
                    variant: AppButtonVariant.secondary,
                    size: AppFieldSize.sm,
                    isLoading: isBusy,
                    icon: const Icon(Icons.meeting_room_outlined, size: 16),
                    onPressed: isBusy ? null : onCallNext,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WaitingEmptyState extends StatelessWidget {
  const _WaitingEmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_empty_outlined, size: 40, color: colors.mutedForeground),
            const SizedBox(height: SpacingTokens.md),
            Text(
              'Waiting room is clear',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: SpacingTokens.xs),
            Text(
              'Checked-in patients will appear here with wait times.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
