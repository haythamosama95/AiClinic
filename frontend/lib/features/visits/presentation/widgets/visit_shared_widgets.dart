import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Page shell aligned with patient and appointment detail scaffolds.
class VisitPageShell extends StatelessWidget {
  const VisitPageShell({required this.onBack, required this.body, this.headerActions = const [], super.key});

  final VoidCallback onBack;
  final List<Widget> headerActions;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _VisitTopBar(onBack: onBack, headerActions: headerActions),
          const SizedBox(height: SpacingTokens.md),
          Expanded(child: SingleChildScrollView(child: body)),
        ],
      ),
    );
  }
}

class _VisitTopBar extends StatelessWidget {
  const _VisitTopBar({required this.onBack, required this.headerActions});

  final VoidCallback onBack;
  final List<Widget> headerActions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppIconButton(icon: const Icon(Icons.arrow_back_rounded), tooltip: 'Back', onPressed: onBack),
        const Spacer(),
        ...headerActions.map(
          (action) => Padding(
            padding: const EdgeInsets.only(left: SpacingTokens.sm),
            child: action,
          ),
        ),
      ],
    );
  }
}

/// Section panel with a notched header shelf for optional actions.
class VisitSectionCard extends StatelessWidget {
  const VisitSectionCard({
    required this.title,
    required this.child,
    this.description,
    this.headerActions,
    this.kind,
    super.key,
  });

  final String title;
  final String? description;
  final Widget child;
  final List<Widget>? headerActions;
  final VisitPanelKind? kind;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final icon = kind?.icon ?? Icons.folder_open_outlined;
    final tag = kind?.tag;

    return AppNotchedCard(
      titleIcon: icon,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tag != null) Text(tag, style: theme.eyebrow(color: theme.pulseDeep, size: 10)),
          if (tag != null) const SizedBox(height: 3),
          Text(title, style: theme.title()),
        ],
      ),
      description: description != null ? Text(description!, style: theme.caption()) : null,
      actions: headerActions,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(SpacingTokens.md, 0, SpacingTokens.md, SpacingTokens.md),
        child: child,
      ),
    );
  }
}

/// Read-only label/value pair for visit detail sections.
class VisitDetailField extends StatelessWidget {
  const VisitDetailField({required this.label, required this.value, this.abbr, super.key});

  final String label;
  final String value;
  final String? abbr;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final display = value.trim().isEmpty ? '—' : value.trim();
    final isEmpty = value.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (abbr != null) ...[VisitMarginAbbr(letter: abbr!), const SizedBox(width: SpacingTokens.md)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: theme.eyebrow(size: 10).copyWith(letterSpacing: 1.2)),
                const SizedBox(height: SpacingTokens.xs + 1),
                Text(display, style: theme.body(color: isEmpty ? theme.mutedInk : theme.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Clinical chart margin abbreviation.
class VisitMarginAbbr extends StatelessWidget {
  const VisitMarginAbbr({required this.letter, super.key});

  final String letter;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: theme.pulse.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(theme.tileRadius - 2),
        border: Border.all(color: theme.pulse.withValues(alpha: 0.28)),
      ),
      alignment: Alignment.center,
      child: Text(letter, style: theme.readout(color: theme.pulseDeep, size: 13)),
    );
  }
}

/// Empty state hint for visit sections.
class VisitEmptyHint extends StatelessWidget {
  const VisitEmptyHint({required this.message, this.icon = Icons.inbox_outlined, super.key});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: theme.tile, shape: BoxShape.circle),
              child: Icon(icon, size: 17, color: theme.mutedInk.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: SpacingTokens.sm),
            Text(message, textAlign: TextAlign.center, style: theme.caption()),
          ],
        ),
      ),
    );
  }
}

/// Responsive two-column grid for visit ancillary sections.
class VisitSectionGrid extends StatelessWidget {
  const VisitSectionGrid({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 720;

        if (!useTwoColumns) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _withGaps(children));
        }

        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += 2) {
          final left = children[i];
          final right = i + 1 < children.length ? children[i + 1] : const SizedBox.shrink();
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                const SizedBox(width: VisitPageTokens.sectionGap),
                Expanded(child: right),
              ],
            ),
          );
          if (i + 2 < children.length) {
            rows.add(const SizedBox(height: VisitPageTokens.sectionGap));
          }
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      },
    );
  }

  List<Widget> _withGaps(List<Widget> items) {
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);
      if (i < items.length - 1) {
        result.add(const SizedBox(height: VisitPageTokens.sectionGap));
      }
    }
    return result;
  }
}
