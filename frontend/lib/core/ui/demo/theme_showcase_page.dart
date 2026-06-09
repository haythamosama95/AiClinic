import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Interactive gallery of design tokens, typography, and forui wrapper components.
class ThemeShowcasePage extends ConsumerStatefulWidget {
  const ThemeShowcasePage({super.key});

  @override
  ConsumerState<ThemeShowcasePage> createState() => _ThemeShowcasePageState();
}

class _ThemeShowcasePageState extends ConsumerState<ThemeShowcasePage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  var _buttonLoading = false;
  var _checkboxValue = true;
  var _switchValue = false;
  var _progressValue = 0.65;
  String? _selectedRole;
  final _selectedTags = <String>{'billing'};
  var _selectedPlan = <String>{'standard'};
  String? _autocompleteValue;
  DateTime? _shiftDate;
  Set<String> _notificationPrefs = {'email'};

  static const _roles = {'Owner': 'owner', 'Administrator': 'admin', 'Staff': 'staff'};
  static const _tags = {'Front desk': 'front_desk', 'Billing': 'billing', 'Clinical': 'clinical'};
  static const _doctors = {'Dr. Ahmed': 'ahmed', 'Dr. Sara': 'sara', 'Dr. Omar': 'omar'};

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final themeMode = ref.watch(themeModeProvider);
    final themeVariant = ref.watch(themeVariantProvider);
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
            title: 'Theme variant',
            child: Wrap(
              spacing: SpacingTokens.sm,
              runSpacing: SpacingTokens.sm,
              children: AppThemeVariant.values.map((variant) {
                return ChoiceChip(
                  label: Text(appThemeVariantLabel(variant)),
                  selected: themeVariant == variant,
                  onSelected: (_) => setAppThemeVariant(ref, variant),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
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
                AppButton(label: 'Primary', onPressed: () {}),
                AppButton(label: 'Secondary', variant: AppButtonVariant.secondary, onPressed: () {}),
                AppButton(label: 'Outline', variant: AppButtonVariant.outline, onPressed: () {}),
                AppButton(label: 'Ghost', variant: AppButtonVariant.ghost, onPressed: () {}),
                AppButton(label: 'Destructive', variant: AppButtonVariant.destructive, onPressed: () {}),
                AppButton(label: 'With icon', icon: const Icon(Icons.mail_outline, size: 18), onPressed: () {}),
                AppButton(
                  label: 'Loading',
                  isLoading: _buttonLoading,
                  onPressed: () {
                    setState(() => _buttonLoading = true);
                    Future<void>.delayed(const Duration(seconds: 2), () {
                      if (mounted) setState(() => _buttonLoading = false);
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          _Section(
            title: 'Form inputs',
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    label: 'Username',
                    hintText: 'Enter a username',
                    controller: _usernameController,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Username is required.';
                      return null;
                    },
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  AppAutocomplete<String>(
                    label: 'Assignee',
                    items: _doctors,
                    value: _autocompleteValue,
                    hintText: 'Search staff…',
                    onChanged: (value) => setState(() => _autocompleteValue = value),
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  AppDateField(
                    label: 'Shift date',
                    value: _shiftDate,
                    onChanged: (value) => setState(() => _shiftDate = value),
                    firstDate: DateTime.now().subtract(const Duration(days: 7)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  AppSelect<String>(
                    label: 'Role',
                    items: _roles,
                    value: _selectedRole,
                    hintText: 'Select a role',
                    onChanged: (value) => setState(() => _selectedRole = value),
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  AppMultiSelect<String>(
                    label: 'Tags',
                    items: _tags,
                    values: _selectedTags,
                    onChanged: (values) => setState(() {
                      _selectedTags
                        ..clear()
                        ..addAll(values);
                    }),
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  AppLabel(
                    label: 'Notes',
                    description: 'Optional context shown below the label.',
                    child: AppTextInput(hintText: 'Add a note…'),
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppButton(label: 'Validate form', onPressed: () => _formKey.currentState?.validate()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          _Section(
            title: 'Selectors',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCheckbox(
                  label: 'Accept terms',
                  value: _checkboxValue,
                  onChanged: (value) => setState(() => _checkboxValue = value),
                ),
                const SizedBox(height: SpacingTokens.sm),
                AppSwitch(
                  label: 'Enable notifications',
                  value: _switchValue,
                  onChanged: (value) => setState(() => _switchValue = value),
                ),
                const SizedBox(height: SpacingTokens.md),
                AppSelectGroup<String>(
                  label: 'Notification channels',
                  mode: AppSelectGroupMode.checkbox,
                  options: const [
                    AppSelectOption(value: 'email', label: 'Email'),
                    AppSelectOption(value: 'sms', label: 'SMS'),
                    AppSelectOption(value: 'push', label: 'Push'),
                  ],
                  values: _notificationPrefs,
                  onChanged: (values) => setState(() => _notificationPrefs = values),
                ),
                const SizedBox(height: SpacingTokens.md),
                AppSelectTileGroup<String>(
                  label: 'Plan',
                  mode: AppSelectGroupMode.radio,
                  options: const [
                    AppSelectOption(value: 'basic', label: 'Basic', description: 'Single branch'),
                    AppSelectOption(value: 'standard', label: 'Standard', description: 'Up to 5 branches'),
                    AppSelectOption(value: 'enterprise', label: 'Enterprise', description: 'Unlimited branches'),
                  ],
                  values: _selectedPlan,
                  onChanged: (values) => setState(() => _selectedPlan = values),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          _Section(
            title: 'Tiles & items',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTileGroup(
                  label: 'Quick actions',
                  tiles: [
                    AppTileSpec(
                      title: 'View schedule',
                      subtitle: 'Weekly calendar',
                      prefix: const Icon(Icons.calendar_month_outlined, size: 20),
                      suffix: const Icon(Icons.chevron_right, size: 20),
                      onPressed: () {},
                    ),
                    AppTileSpec(
                      title: 'Manage staff',
                      subtitle: 'Roles and permissions',
                      prefix: const Icon(Icons.people_outline, size: 20),
                      onPressed: () {},
                    ),
                  ],
                ),
                const SizedBox(height: SpacingTokens.md),
                AppItemGroup(
                  items: [
                    AppItemSpec(
                      title: 'Export report',
                      details: 'CSV',
                      prefix: const Icon(Icons.download_outlined, size: 18),
                      onPressed: () {},
                    ),
                    AppItemSpec(title: 'Delete draft', variant: AppTileVariant.destructive, onPressed: () {}),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          _Section(
            title: 'Feedback',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppAlert(title: 'Shift saved', subtitle: 'The calendar will refresh automatically.'),
                const SizedBox(height: SpacingTokens.sm),
                const AppAlert(
                  title: 'Conflict detected',
                  subtitle: 'This staff member is already assigned to an overlapping shift.',
                  variant: AppAlertVariant.destructive,
                ),
                const SizedBox(height: SpacingTokens.md),
                const AppLinearProgress(),
                const SizedBox(height: SpacingTokens.sm),
                Row(
                  children: [
                    const AppCircularProgress(),
                    const SizedBox(width: SpacingTokens.md),
                    Expanded(child: AppDeterminateProgress(value: _progressValue)),
                  ],
                ),
                const SizedBox(height: SpacingTokens.sm),
                Slider(value: _progressValue, onChanged: (value) => setState(() => _progressValue = value)),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          _Section(
            title: 'Overlays',
            child: Wrap(
              spacing: SpacingTokens.sm,
              runSpacing: SpacingTokens.sm,
              children: [
                AppButton(
                  label: 'Dialog',
                  variant: AppButtonVariant.secondary,
                  onPressed: () {
                    AppDialog.showConfirmation(
                      context: context,
                      title: 'Discard changes?',
                      message: 'You have unsaved changes. This action cannot be undone.',
                      confirmLabel: 'Discard',
                      cancelLabel: 'Keep editing',
                      confirmVariant: AppButtonVariant.destructive,
                      onConfirm: () {},
                    );
                  },
                ),
                AppButton(
                  label: 'Success toast',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => AppToast.success(context, message: 'Shift created successfully.'),
                ),
                AppButton(
                  label: 'Error toast',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => AppToast.error(context, message: 'Unable to save shift.'),
                ),
                AppButton(
                  label: 'Bottom sheet',
                  variant: AppButtonVariant.secondary,
                  onPressed: () {
                    AppSheets.showModal(
                      context: context,
                      builder: (context) => Padding(
                        padding: const EdgeInsets.all(SpacingTokens.lg),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Filter shifts', style: theme.textTheme.titleMedium),
                            const SizedBox(height: SpacingTokens.md),
                            AppSelect<String>(
                              label: 'Branch',
                              items: const {'Main': 'main', 'North': 'north'},
                              onChanged: (_) {},
                            ),
                            const SizedBox(height: SpacingTokens.md),
                            AppButton(label: 'Apply', onPressed: () => Navigator.of(context).pop()),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                AppPopoverMenu(
                  items: const [
                    AppPopoverMenuItem(label: 'Edit', icon: Icon(Icons.edit_outlined, size: 18)),
                    AppPopoverMenuItem(label: 'Duplicate', icon: Icon(Icons.copy_outlined, size: 18)),
                    AppPopoverMenuItem(label: 'Delete', icon: Icon(Icons.delete_outline, size: 18), destructive: true),
                  ],
                  child: AppButton(label: 'Popover menu', variant: AppButtonVariant.outline, onPressed: () {}),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpacingTokens.lg),
          _Section(
            title: 'Card',
            child: AppCard(
              title: Text('Panel title', style: theme.textTheme.titleMedium),
              description: Text(
                'Dense dashboard card using tokenized background and border.',
                style: theme.textTheme.bodyMedium,
              ),
              actions: [
                AppButton(label: 'Action', variant: AppButtonVariant.secondary, onPressed: () {}),
                AppButton(label: 'Save', onPressed: () {}),
              ],
              child: Text('Card body content for metrics, lists, or forms.', style: theme.textTheme.bodyMedium),
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
