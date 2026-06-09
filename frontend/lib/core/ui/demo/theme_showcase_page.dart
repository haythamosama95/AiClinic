import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Interactive gallery of design tokens, typography, and Material components.
class ThemeShowcasePage extends ConsumerStatefulWidget {
  const ThemeShowcasePage({super.key});

  @override
  ConsumerState<ThemeShowcasePage> createState() => _ThemeShowcasePageState();
}

class _ThemeShowcasePageState extends ConsumerState<ThemeShowcasePage> {
  var _switchValue = true;
  var _checkboxValue = true;
  var _radioValue = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final themeMode = ref.watch(themeModeProvider);
    final brightness = theme.brightness;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Theme Showcase'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        children: [
          _Section(
            title: 'Appearance',
            child: Wrap(
              spacing: SpacingTokens.sm,
              runSpacing: SpacingTokens.sm,
              children: ThemeMode.values.map((mode) {
                return ChoiceChip(
                  label: Text(themeModeLabel(mode)),
                  selected: themeMode == mode,
                  onSelected: (_) => setAppThemeMode(ref, mode),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          _Section(
            title: 'Brightness',
            child: Text(
              brightness == Brightness.dark ? 'Dark palette active' : 'Light palette active',
              style: theme.textTheme.bodyLarge,
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          _Section(
            title: 'Color tokens',
            child: Wrap(
              spacing: SpacingTokens.sm,
              runSpacing: SpacingTokens.sm,
              children: [
                _ColorSwatch(label: 'Primary', color: colors.primary, foreground: colors.primaryForeground),
                _ColorSwatch(label: 'Secondary', color: colors.secondary, foreground: colors.secondaryForeground),
                _ColorSwatch(label: 'Accent', color: colors.accent, foreground: colors.accentForeground),
                _ColorSwatch(label: 'Destructive', color: colors.destructive, foreground: colors.destructiveForeground),
                _ColorSwatch(label: 'Background', color: colors.background, foreground: colors.foreground),
                _ColorSwatch(label: 'Card', color: colors.card, foreground: colors.cardForeground),
                _ColorSwatch(label: 'Muted', color: colors.muted, foreground: colors.mutedForeground),
                _ColorSwatch(label: 'Border', color: colors.border, foreground: colors.foreground),
                _ColorSwatch(label: 'Sidebar', color: colors.sidebar, foreground: colors.sidebarForeground),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          _Section(
            title: 'Chart palette',
            child: Row(
              children: [for (final color in colors.chartPalette) Expanded(child: Container(height: 48, color: color))],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          _Section(
            title: 'Typography',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Display Large', style: theme.textTheme.displayLarge),
                Text('Headline Medium', style: theme.textTheme.headlineMedium),
                Text('Title Large', style: theme.textTheme.titleLarge),
                Text('Body Large', style: theme.textTheme.bodyLarge),
                Text('Body Small (muted)', style: theme.textTheme.bodySmall),
                Text('Label Small', style: theme.textTheme.labelSmall),
                const SizedBox(height: SpacingTokens.sm),
                Text(
                  'Serif sample',
                  style: TypographyTokens.serif(fontSize: 18, fontWeight: FontWeight.w600, color: colors.foreground),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          _Section(
            title: 'Buttons',
            child: Wrap(
              spacing: SpacingTokens.sm,
              runSpacing: SpacingTokens.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Filled')),
                ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
                OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
                TextButton(onPressed: () {}, child: const Text('Text')),
                FilledButton(onPressed: null, child: const Text('Disabled')),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          _Section(
            title: 'Form controls',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TextField(
                  decoration: InputDecoration(labelText: 'Text field', hintText: 'Placeholder'),
                ),
                const SizedBox(height: SpacingTokens.md),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Switch'),
                  value: _switchValue,
                  onChanged: (value) => setState(() => _switchValue = value),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Checkbox'),
                  value: _checkboxValue,
                  onChanged: (value) => setState(() => _checkboxValue = value ?? false),
                ),
                const SizedBox(height: SpacingTokens.md),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Option A')),
                    ButtonSegment(value: 1, label: Text('Option B')),
                  ],
                  selected: {_radioValue},
                  onSelectionChanged: (selection) => setState(() => _radioValue = selection.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          _Section(
            title: 'Cards & feedback',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(SpacingTokens.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Card title', style: theme.textTheme.titleMedium),
                        const SizedBox(height: SpacingTokens.xs),
                        Text(
                          'Cards use tokenized radius, border, and surface colors.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: SpacingTokens.md),
                Wrap(
                  spacing: SpacingTokens.sm,
                  runSpacing: SpacingTokens.sm,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Dialog'),
                            content: const Text('Themed dialog surface and actions.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                            ],
                          ),
                        );
                      },
                      child: const Text('Show dialog'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Themed snackbar')));
                      },
                      child: const Text('Show snackbar'),
                    ),
                  ],
                ),
                const SizedBox(height: SpacingTokens.md),
                const LinearProgressIndicator(),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          _Section(
            title: 'Spacing & radius',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Spacing scale: xs=${SpacingTokens.xs}, sm=${SpacingTokens.sm}, md=${SpacingTokens.md}, lg=${SpacingTokens.lg}',
                ),
                const SizedBox(height: SpacingTokens.sm),
                Wrap(
                  spacing: SpacingTokens.sm,
                  children: [
                    _RadiusSample(label: 'sm', radius: RadiusTokens.sm),
                    _RadiusSample(label: 'md', radius: RadiusTokens.md),
                    _RadiusSample(label: 'lg', radius: RadiusTokens.lg),
                    _RadiusSample(label: 'xl', radius: RadiusTokens.xl),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: SpacingTokens.md),
        child,
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.label, required this.color, required this.foreground});

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final hex = '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

    return SizedBox(
      width: 140,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 56,
              color: color,
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(color: foreground, fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(SpacingTokens.sm),
              child: Text(hex, style: Theme.of(context).textTheme.labelSmall),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadiusSample extends StatelessWidget {
  const _RadiusSample({required this.label, required this.radius});

  final String label;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colors.accent,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: colors.border),
          ),
        ),
        const SizedBox(height: SpacingTokens.xs),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
