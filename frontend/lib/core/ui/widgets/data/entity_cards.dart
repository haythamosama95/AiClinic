import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Appointment status for [AppointmentCard].
enum AppointmentCardStatus {
  confirmed,
  pending,
  cancelled,
}

/// Invoice payment status for [InvoiceCard].
enum InvoiceCardStatus {
  paid,
  pending,
  overdue,
}

/// Global service availability for [ServiceCard].
enum ServiceCardGlobalStatus {
  active,
  inactive,
}

/// Patient summary card — avatar, identifiers, phone, and optional tags.
class PatientCard extends StatelessWidget {
  const PatientCard({
    required this.name,
    required this.mrn,
    required this.phone,
    this.tags = const [],
    this.onTap,
    this.onActionsPressed,
    super.key,
  });

  final String name;
  final String mrn;
  final String phone;
  final List<String> tags;
  final VoidCallback? onTap;
  final VoidCallback? onActionsPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return AppCard(
      variant: AppCardVariant.interactive,
      padding: AppCardPadding.sm,
      onTap: onTap,
      semanticLabel: 'Patient $name',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(name: name, size: AppAvatarSize.lg),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: typography.bodyStrong.copyWith(
                              color: colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'MRN · $mrn',
                            style: typography.tabular(typography.caption)
                                .copyWith(color: colors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    AppIconButton(
                      icon: LucideIcons.moreHorizontal,
                      semanticLabel: 'Patient actions',
                      size: AppIconButtonSize.sm,
                      onPressed: onActionsPressed,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s2),
                Row(
                  children: [
                    AppIcon(
                      icon: LucideIcons.phone,
                      dimension: AppSpacing.s3 + AppSpacing.s0_5,
                      color: colors.iconMuted,
                    ),
                    const SizedBox(width: AppSpacing.s1 + AppSpacing.s0_5),
                    Expanded(
                      child: Text(
                        phone,
                        style: typography.tabular(typography.bodySm).copyWith(
                          color: colors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s3),
                  Wrap(
                    spacing: AppSpacing.s1 + AppSpacing.s0_5,
                    runSpacing: AppSpacing.s1 + AppSpacing.s0_5,
                    children: [
                      for (final tag in tags)
                        AppBadge(
                          size: AppBadgeSize.sm,
                          color: AppBadgeColor.neutral,
                          child: Text(tag),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Appointment queue card with time badge, participants, and status pill.
class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    required this.time,
    required this.patient,
    required this.doctor,
    required this.status,
    required this.branch,
    super.key,
  });

  final String time;
  final String patient;
  final String doctor;
  final AppointmentCardStatus status;
  final String branch;

  AppBadgeColor get _statusColor => switch (status) {
    AppointmentCardStatus.confirmed => AppBadgeColor.success,
    AppointmentCardStatus.pending => AppBadgeColor.warning,
    AppointmentCardStatus.cancelled => AppBadgeColor.danger,
  };

  String get _statusLabel => switch (status) {
    AppointmentCardStatus.confirmed => 'confirmed',
    AppointmentCardStatus.pending => 'pending',
    AppointmentCardStatus.cancelled => 'cancelled',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final timeLabel = time.split(' ').first;

    return Semantics(
      container: true,
      label: 'Appointment for $patient at $time',
      child: AppCard(
        variant: AppCardVariant.flat,
        padding: AppCardPadding.sm,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: AppSpacing.s10,
                    height: AppSpacing.s10,
                    decoration: BoxDecoration(
                      color: colors.surfaceSelected,
                      borderRadius: AppRadii.mdAll,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(
                          icon: LucideIcons.calendar,
                          dimension: AppSpacing.s3 + AppSpacing.s0_5,
                          color: colors.textLink,
                        ),
                        Text(
                          timeLabel,
                          style: typography.tabular(typography.caption)
                              .copyWith(color: colors.textLink),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patient,
                          style: typography.bodyStrong.copyWith(
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          doctor,
                          style: typography.bodySm.copyWith(
                            color: colors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          branch,
                          style: typography.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            AppBadge(
              color: _statusColor,
              child: Text(_statusLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Invoice summary card with mono number, amount, and status pill.
class InvoiceCard extends StatelessWidget {
  const InvoiceCard({
    required this.number,
    required this.patient,
    required this.amount,
    required this.status,
    required this.date,
    super.key,
  });

  final String number;
  final String patient;
  final num amount;
  final InvoiceCardStatus status;
  final String date;

  AppBadgeColor get _statusColor => switch (status) {
    InvoiceCardStatus.paid => AppBadgeColor.success,
    InvoiceCardStatus.pending => AppBadgeColor.warning,
    InvoiceCardStatus.overdue => AppBadgeColor.danger,
  };

  String get _statusLabel => switch (status) {
    InvoiceCardStatus.paid => 'paid',
    InvoiceCardStatus.pending => 'pending',
    InvoiceCardStatus.overdue => 'overdue',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Semantics(
      container: true,
      label: 'Invoice $number for $patient',
      child: AppCard(
        variant: AppCardVariant.flat,
        padding: AppCardPadding.sm,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    number,
                    style: typography.mono.copyWith(color: colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    patient,
                    style: typography.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    date,
                    style: typography.tabular(typography.caption).copyWith(
                      color: colors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AppMoney.fromNum(amount, emphasis: AppMoneyEmphasis.strong),
                const SizedBox(height: AppSpacing.s1),
                AppBadge(
                  color: _statusColor,
                  child: Text(_statusLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Catalog service card with price, branch summary, and optional action.
class ServiceCard extends StatelessWidget {
  const ServiceCard({
    required this.name,
    required this.price,
    required this.globalStatus,
    required this.branchSummary,
    this.onViewBranches,
    super.key,
  });

  final String name;
  final num price;
  final ServiceCardGlobalStatus globalStatus;
  final String branchSummary;
  final VoidCallback? onViewBranches;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final statusLabel = globalStatus.name;
    final statusColor = globalStatus == ServiceCardGlobalStatus.active
        ? AppBadgeColor.success
        : AppBadgeColor.neutral;

    return Semantics(
      container: true,
      label: 'Service $name',
      child: AppCard(
        variant: AppCardVariant.raised,
        padding: AppCardPadding.sm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: typography.bodyStrong.copyWith(
                          color: colors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.s1),
                      AppMoney.fromNum(price),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        branchSummary,
                        style: typography.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s3),
                AppBadge(
                  color: statusColor,
                  child: Text(statusLabel),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            AppButton(
              label: 'View branches',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: onViewBranches,
            ),
          ],
        ),
      ),
    );
  }
}
