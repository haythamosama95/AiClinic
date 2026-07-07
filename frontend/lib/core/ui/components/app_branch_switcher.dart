import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_nav_models.dart';
import 'package:ai_clinic/core/ui/components/app_popover.dart';
import 'package:ai_clinic/core/ui/components/app_search_input.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Branch scope switcher for the top bar (web `BranchSwitcher`).
class AppBranchSwitcher extends StatefulWidget {
  const AppBranchSwitcher({
    required this.branches,
    required this.currentBranchId,
    required this.onBranchChange,
    super.key,
  });

  final List<AppBranch> branches;
  final String currentBranchId;
  final ValueChanged<String> onBranchChange;

  @override
  State<AppBranchSwitcher> createState() => _AppBranchSwitcherState();
}

class _AppBranchSwitcherState extends State<AppBranchSwitcher> {
  var _open = false;
  var _query = '';
  String? _feedback;
  Timer? _feedbackTimer;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  void _showFeedback(String message) {
    _feedbackTimer?.cancel();
    setState(() => _feedback = message);
    _feedbackTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  void _handleSelect(String branchId) {
    final branch = widget.branches.firstWhere((b) => b.id == branchId);
    if (branchId == widget.currentBranchId) {
      setState(() => _open = false);
      return;
    }
    widget.onBranchChange(branchId);
    _showFeedback('Switched to ${branch.name}');
    setState(() {
      _open = false;
      _query = '';
    });
  }

  List<AppBranch> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.branches;
    return widget.branches
        .where((b) => b.name.toLowerCase().contains(q) || b.org.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.branches.isEmpty) return const SizedBox.shrink();

    final colors = context.appColors;
    final current = widget.branches.firstWhere(
      (b) => b.id == widget.currentBranchId,
      orElse: () => widget.branches.first,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppPopover(
          open: _open,
          onOpenChange: (value) => setState(() => _open = value),
          align: AppPopoverAlign.end,
          matchTriggerWidth: false,
          width: 288,
          triggerBuilder: (context, isOpen, onToggle) {
            return Semantics(
              button: true,
              label: 'Current branch: ${current.name}',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  hoverColor: colors.surfaceHover,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 192),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.surfaceDefault,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: colors.borderDefault),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.apartment, size: 16, color: colors.iconDefault),
                        const SizedBox(width: AppSpacing.space2),
                        Flexible(
                          child: Text(
                            current.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySm(context).copyWith(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Icon(Icons.expand_more, size: 16, color: colors.iconMuted),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.space2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(current.org, style: AppTypography.overline(context)),
                    if (widget.branches.length > 4) ...[
                      const SizedBox(height: AppSpacing.space2),
                      AppSearchInput(
                        size: AppInputSize.sm,
                        placeholder: 'Search branches…',
                        initialValue: _query,
                        onValueChange: (value) => setState(() => _query = value),
                        showShortcutHint: false,
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: _filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
                        child: Center(
                          child: Text(
                            'No branches found',
                            style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary),
                          ),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(AppSpacing.space1),
                        children: [
                          for (final branch in _filtered)
                            _BranchRow(
                              branch: branch,
                              selected: branch.id == widget.currentBranchId,
                              onSelect: () => _handleSelect(branch.id),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        if (_feedback != null)
          PositionedDirectional(
            end: 0,
            top: 40,
            child: Semantics(
              liveRegion: true,
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceRaised,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: colors.borderDefault),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: 6),
                    child: Text(_feedback!, style: AppTypography.bodySm(context)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.branch,
    required this.selected,
    required this.onSelect,
  });

  final AppBranch branch;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(AppRadius.md),
        hoverColor: colors.surfaceHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2, vertical: AppSpacing.space2),
          child: Row(
            children: [
              Expanded(
                child: Text(branch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (selected) Icon(Icons.check, size: 16, color: colors.textLink),
            ],
          ),
        ),
      ),
    );
  }
}
