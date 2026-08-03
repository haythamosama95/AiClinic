import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Reusable rounded card shell for vital/investigation/treatment/safety entry cards.
///
/// Mirrors web `*EntryCard.tsx` shells: left-accent border, surface background,
/// and a one-shot `fade-scale` enter animation.
class VisitEntryCard extends StatefulWidget {
  const VisitEntryCard({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.space5, vertical: 14),
    this.width,
    this.constraints,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? width;
  final BoxConstraints? constraints;

  @override
  State<VisitEntryCard> createState() => _VisitEntryCardState();
}

class _VisitEntryCardState extends State<VisitEntryCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  CurvedAnimation? _animation;
  var _configured = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) {
      return;
    }
    _configured = true;

    final reducedMotion = AppMotion.prefersReducedMotion(context);
    _controller.duration = AppMotion.resolveDuration(AppMotionPreset.fadeScale, reducedMotion: reducedMotion);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.resolveCurve(AppMotionPreset.fadeScale, reducedMotion: reducedMotion),
    );

    if (reducedMotion) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _animation?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    Widget card = Material(
      type: MaterialType.transparency,
      child: AppMotion.animatedPreset(
        context: context,
        preset: AppMotionPreset.fadeScale,
        animation: _animation ?? _controller,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceDefault,
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Stack(
              children: [
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  child: ColoredBox(
                    color: colors.actionPrimary.withValues(alpha: 0.5),
                    child: const SizedBox(width: 3),
                  ),
                ),
                Padding(padding: widget.padding, child: widget.child),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.constraints != null) {
      card = ConstrainedBox(constraints: widget.constraints!, child: card);
    }
    if (widget.width != null) {
      card = SizedBox(width: widget.width, child: card);
    }

    return card;
  }
}

/// Label + value field inside an entry card row (web `EntryCardField`).
class VisitEntryCardField extends StatelessWidget {
  const VisitEntryCardField({required this.label, required this.child, this.flex = 1, super.key});

  final String label;
  final Widget child;
  final double flex;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Expanded(
      flex: (flex * 10).round(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(label, style: AppTypography.caption(context).copyWith(color: colors.textTertiary)),
          const SizedBox(width: AppSpacing.space2),
          Expanded(
            child: DefaultTextStyle(
              style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal row of [VisitEntryCardField]s with optional trailing actions
/// (web `EntryCardFieldsRow`).
class VisitEntryCardFieldsRow extends StatelessWidget {
  const VisitEntryCardFieldsRow({
    required this.children,
    this.actions,
    this.onEdit,
    this.onRemove,
    this.editLabel,
    this.removeLabel,
    super.key,
  });

  final List<Widget> children;
  final Widget? actions;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final String? editLabel;
  final String? removeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final resolvedActions =
        actions ??
        (onEdit != null && onRemove != null
            ? VisitEntryCardIconActions(
                onEdit: onEdit!,
                onRemove: onRemove!,
                editLabel: editLabel ?? 'Edit entry',
                removeLabel: removeLabel ?? 'Remove entry',
              )
            : null);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fieldGap = constraints.maxWidth >= 1024 ? AppSpacing.space8 : AppSpacing.space5;
              return Row(
                children: [
                  for (var index = 0; index < children.length; index++) ...[
                    if (index > 0) SizedBox(width: fieldGap),
                    children[index],
                  ],
                ],
              );
            },
          ),
        ),
        if (resolvedActions != null) ...[
          Container(
            margin: const EdgeInsetsDirectional.only(start: AppSpacing.space4),
            padding: const EdgeInsetsDirectional.only(start: AppSpacing.space4),
            decoration: BoxDecoration(
              border: BorderDirectional(start: BorderSide(color: colors.borderSubtle)),
            ),
            child: resolvedActions,
          ),
        ],
      ],
    );
  }
}

/// Standard trailing edit/remove icon buttons for entry cards.
class VisitEntryCardIconActions extends StatelessWidget {
  const VisitEntryCardIconActions({
    required this.onEdit,
    required this.onRemove,
    required this.editLabel,
    required this.removeLabel,
    super.key,
  });

  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final String editLabel;
  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final iconColor = colors.textTertiary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          icon: Icon(Icons.edit_outlined, size: 15, color: iconColor),
          label: editLabel,
          size: AppIconButtonSize.sm,
          onPressed: onEdit,
        ),
        AppIconButton(
          icon: Icon(Icons.delete_outline, size: 15, color: iconColor),
          label: removeLabel,
          size: AppIconButtonSize.sm,
          onPressed: onRemove,
        ),
      ],
    );
  }
}
