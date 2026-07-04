import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/navigation/nav_model.dart';
import 'package:ai_clinic/core/ui/providers/density_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/search_input.dart';
import 'package:ai_clinic/core/ui/widgets/overlay/app_popover.dart';

/// Dropdown for switching the active clinic branch.
class BranchSwitcher extends ConsumerStatefulWidget {
  const BranchSwitcher({
    super.key,
    required this.branches,
    required this.currentBranchId,
    required this.onBranchChange,
  });

  final List<Branch> branches;
  final String currentBranchId;
  final ValueChanged<String> onBranchChange;

  @override
  ConsumerState<BranchSwitcher> createState() => _BranchSwitcherState();
}

class _BranchSwitcherState extends ConsumerState<BranchSwitcher> {
  bool _open = false;
  String _query = '';
  String? _feedback;
  Timer? _feedbackTimer;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  Branch? get _current {
    for (final branch in widget.branches) {
      if (branch.id == widget.currentBranchId) return branch;
    }
    return widget.branches.isNotEmpty ? widget.branches.first : null;
  }

  List<Branch> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.branches;
    return widget.branches
        .where(
          (b) =>
              b.name.toLowerCase().contains(q) ||
              b.org.toLowerCase().contains(q),
        )
        .toList();
  }

  void _handleSelect(String branchId, VoidCallback hide) {
    Branch? branch;
    for (final candidate in widget.branches) {
      if (candidate.id == branchId) {
        branch = candidate;
        break;
      }
    }
    if (branch == null || branchId == widget.currentBranchId) {
      hide();
      setState(() => _open = false);
      return;
    }

    widget.onBranchChange(branchId);
    final branchName = branch.name;
    setState(() {
      _open = false;
      _query = '';
      _feedback = 'Switched to $branchName';
    });
    hide();

    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final density = ref.watch(appDensityProvider);
    final current = _current;
    final verticalPadding = density == AppDensity.compact
        ? AppSpacing.s1
        : density == AppDensity.comfortable
        ? AppSpacing.s2
        : AppSpacing.s1 + AppSpacing.s0_5;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppPopover(
          open: _open,
          onOpenChange: (value) => setState(() => _open = value),
          placement: const AppPopoverPlacement(
            side: AppPopoverSide.bottom,
            align: AppPopoverAlign.end,
          ),
          minWidth: 288,
          contentPadding: EdgeInsets.zero,
          trigger: _BranchTrigger(
            branchName: current?.name ?? 'Unknown',
            verticalPadding: verticalPadding,
          ),
          contentBuilder: (context, hide) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s2),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: colors.borderSubtle),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        current?.org ?? '',
                        style: typography.overline.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                      if (widget.branches.length > 4) ...[
                        const SizedBox(height: AppSpacing.s2),
                        AppSearchInput(
                          size: AppInputSize.sm,
                          hintText: 'Search branches…',
                          showShortcutHint: false,
                          debounceMs: 0,
                          onChanged: (value) => setState(() => _query = value),
                        ),
                      ],
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: _filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s2,
                            vertical: AppSpacing.s3,
                          ),
                          child: Text(
                            'No branches found',
                            textAlign: TextAlign.center,
                            style: typography.bodySm.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(AppSpacing.s1),
                          shrinkWrap: true,
                          children: [
                            for (final branch in _filtered)
                              _BranchMenuItem(
                                branch: branch,
                                selected: branch.id == widget.currentBranchId,
                                onSelect: () => _handleSelect(branch.id, hide),
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
        if (_feedback != null)
          PositionedDirectional(
            end: 0,
            top: double.infinity,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s1),
              child: Semantics(
                liveRegion: true,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceRaised,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(color: colors.borderDefault),
                    boxShadow: context.elevation.level2,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s3,
                      vertical: AppSpacing.s1 + AppSpacing.s0_5,
                    ),
                    child: Text(
                      _feedback!,
                      style: typography.bodySm.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BranchTrigger extends StatefulWidget {
  const _BranchTrigger({
    required this.branchName,
    required this.verticalPadding,
  });

  final String branchName;
  final double verticalPadding;

  @override
  State<_BranchTrigger> createState() => _BranchTriggerState();
}

class _BranchTriggerState extends State<_BranchTrigger> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return LayoutBuilder(
      builder: (context, constraints) {
        const maxTriggerWidth = 192.0;
        final hasBoundedWidth = constraints.maxWidth.isFinite;
        final triggerWidth = hasBoundedWidth
            ? constraints.maxWidth.clamp(0.0, maxTriggerWidth)
            : null;

        return Semantics(
          button: true,
          label: 'Current branch: ${widget.branchName}',
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: triggerWidth,
              constraints: hasBoundedWidth
                  ? null
                  : const BoxConstraints(maxWidth: maxTriggerWidth),
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.s3,
                vertical: widget.verticalPadding,
              ),
              decoration: BoxDecoration(
                color: _hovered ? colors.surfaceHover : colors.surfaceDefault,
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: colors.borderDefault),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.business_outlined,
                    size: 16,
                    color: colors.iconDefault,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Flexible(
                    child: Text(
                      widget.branchName,
                      overflow: TextOverflow.ellipsis,
                      style: typography.bodySm.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Icon(Icons.expand_more, size: 16, color: colors.iconMuted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BranchMenuItem extends StatefulWidget {
  const _BranchMenuItem({
    required this.branch,
    required this.selected,
    required this.onSelect,
  });

  final Branch branch;
  final bool selected;
  final VoidCallback onSelect;

  @override
  State<_BranchMenuItem> createState() => _BranchMenuItemState();
}

class _BranchMenuItemState extends State<_BranchMenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onSelect,
          borderRadius: AppRadius.mdAll,
          hoverColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s2,
              vertical: AppSpacing.s1 + AppSpacing.s0_5,
            ),
            decoration: BoxDecoration(
              color: _hovered ? colors.surfaceHover : Colors.transparent,
              borderRadius: AppRadius.mdAll,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.branch.name,
                    overflow: TextOverflow.ellipsis,
                    style: typography.body.copyWith(color: colors.textPrimary),
                  ),
                ),
                if (widget.selected)
                  Icon(Icons.check, size: 16, color: colors.textLink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
