import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';

/// Card displaying a staff member's name, role, phone, and branch assignments.
class StaffMemberCard extends StatelessWidget {
  const StaffMemberCard({
    required this.member,
    required this.onEdit,
    required this.onToggleActive,
    this.isBusy = false,
    super.key,
  });

  final StaffListItem member;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(color: colors.foreground.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isBusy ? null : onEdit,
          borderRadius: BorderRadius.circular(context.shapeTokens.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SpacingTokens.lg,
                  SpacingTokens.lg,
                  SpacingTokens.md,
                  SpacingTokens.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: colors.muted,
                      foregroundColor: colors.foreground,
                      child: Text(_initials(member.fullName), style: theme.textTheme.titleSmall),
                    ),
                    const SizedBox(width: SpacingTokens.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.fullName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colors.foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: SpacingTokens.xs),
                          Text(
                            _roleLabel(member.role),
                            style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                          ),
                        ],
                      ),
                    ),
                    if (isBusy)
                      const SizedBox(width: 24, height: 24, child: AppCircularProgress())
                    else
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              onEdit();
                            case 'toggle':
                              onToggleActive();
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'toggle', child: Text(member.isActive ? 'Deactivate' : 'Reactivate')),
                        ],
                      ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: colors.border),
              Padding(
                padding: const EdgeInsets.all(SpacingTokens.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _InfoRow(
                      icon: Icons.phone_outlined,
                      child: Text(
                        member.phone ?? 'No phone number',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: member.phone != null
                              ? colors.mutedForeground
                              : colors.mutedForeground.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.md),
                    _InfoRow(
                      icon: Icons.storefront_outlined,
                      child: member.branches.isEmpty
                          ? Text(
                              'No branches assigned',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.mutedForeground.withValues(alpha: 0.7),
                              ),
                            )
                          : Wrap(
                              spacing: SpacingTokens.sm,
                              runSpacing: SpacingTokens.sm,
                              children: [for (final branch in member.branches) _BranchChip(branch: branch)],
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initials(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }

  static String _roleLabel(StaffRole role) => switch (role) {
    StaffRole.administrator => 'Administrator',
    StaffRole.doctor => 'Doctor',
    StaffRole.receptionist => 'Receptionist',
    StaffRole.labStaff => 'Lab staff',
  };
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colors.mutedForeground),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(child: child),
      ],
    );
  }
}

class _BranchChip extends StatelessWidget {
  const _BranchChip({required this.branch});

  final StaffBranchLabel branch;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    if (branch.isPrimary) {
      return DecoratedBox(
        decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(999)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.xs),
          child: Text(
            branch.name,
            style: theme.textTheme.labelMedium?.copyWith(color: colors.primaryForeground, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.xs),
        child: Text(branch.name, style: theme.textTheme.labelMedium?.copyWith(color: colors.mutedForeground)),
      ),
    );
  }
}
