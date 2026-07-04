import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/shell/chrome/app_ai_mode_toggle.dart';
import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/patterns/pattern_scaffold.dart';
import 'package:ai_clinic/core/ui/state/ai_mode_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/dev/presentation/widgets/showcase_section.dart';

/// Components tab — variant and state matrices for shared primitives.
class ComponentsShowcaseSection extends StatefulWidget {
  const ComponentsShowcaseSection({super.key});

  @override
  State<ComponentsShowcaseSection> createState() => _ComponentsShowcaseSectionState();
}

class _ComponentsShowcaseSectionState extends State<ComponentsShowcaseSection> {
  var _loadingDemo = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Milestone 4',
          style: typography.overline.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.s1),
        Text(
          'Components',
          style: typography.h2.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          'Shared primitives with full variant and state matrices. Toggle theme, direction, language, density, and AI mode from the controls above.',
          style: typography.bodyLg.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        _group(
          title: 'Actions',
          description: 'Buttons, icon buttons, split buttons, and segmented controls.',
          children: [
            ShowcaseSection(
              title: 'Buttons',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final variant in AppButtonVariant.values) ...[
                    Text(
                      variant.name,
                      style: typography.overline.copyWith(color: colors.textTertiary),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Wrap(
                      spacing: AppSpacing.s2,
                      runSpacing: AppSpacing.s2,
                      children: [
                        for (final size in AppButtonSize.values)
                          AppButton(
                            label: 'Label',
                            variant: variant,
                            size: size,
                            onPressed: () {},
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s4),
                  ],
                  Wrap(
                    spacing: AppSpacing.s2,
                    runSpacing: AppSpacing.s2,
                    children: [
                      AppButton(
                        label: _loadingDemo ? 'Saving…' : 'Simulate loading',
                        loading: _loadingDemo,
                        onPressed: _loadingDemo
                            ? null
                            : () {
                                setState(() => _loadingDemo = true);
                                Future<void>.delayed(const Duration(milliseconds: 1500), () {
                                  if (mounted) setState(() => _loadingDemo = false);
                                });
                              },
                      ),
                      const AppButton(label: 'Disabled', disabled: true, onPressed: null),
                    ],
                  ),
                ],
              ),
            ),
            ShowcaseSection(
              title: 'Icon buttons',
              child: Wrap(
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s2,
                children: [
                  for (final variant in AppIconButtonVariant.values)
                    AppIconButton(
                      icon: LucideIcons.plus,
                      semanticLabel: variant.name,
                      variant: variant,
                      onPressed: () {},
                    ),
                ],
              ),
            ),
            ShowcaseSection(
              title: 'Segmented control',
              child: _SegmentedDemo(),
            ),
          ],
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        _group(
          title: 'Inputs & forms',
          description: 'Form fields, text inputs, pickers, and validation states.',
          children: [
            ShowcaseSection(
              title: 'Text field',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppFormField(
                    label: 'Patient name',
                    child: AppTextField(hintText: 'Enter full name', onChanged: (_) {}),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  AppFormField(
                    label: 'With error',
                    error: 'This field is required',
                    child: const AppTextField(
                      hintText: 'Required',
                      invalid: true,
                    ),
                  ),
                ],
              ),
            ),
            ShowcaseSection(
              title: 'Choice controls',
              child: _ChoiceControlsDemo(),
            ),
          ],
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        _group(
          title: 'Data display',
          description: 'Badges, chips, avatars, progress, and read-only primitives.',
          children: [
            ShowcaseSection(
              title: 'Badges & chips',
              child: Wrap(
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final color in AppBadgeColor.values)
                    AppBadge(label: color.name, color: color),
                  const AppChip(child: Text('Tag')),
                  const AppAvatar(name: 'Haytham Kamal'),
                ],
              ),
            ),
            ShowcaseSection(
              title: 'Progress & skeleton',
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppProgress(value: 0.62),
                  SizedBox(height: AppSpacing.s4),
                  AppSkeleton(height: AppSpacing.s10, width: double.infinity),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        _group(
          title: 'Feedback & overlays',
          description: 'Alerts, empty states, and dialog triggers.',
          children: [
            ShowcaseSection(
              title: 'Alerts',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final variant in AppAlertVariant.values)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s2),
                      child: AppAlert(
                        variant: variant,
                        title: variant.name,
                        body: 'Supporting message for the ${variant.name} alert.',
                      ),
                    ),
                ],
              ),
            ),
            ShowcaseSection(
              title: 'Empty state',
              child: AppEmptyState(
                title: 'No patients yet',
                description: 'Register your first patient to begin scheduling visits.',
                actionLabel: 'Register patient',
                onAction: () {},
              ),
            ),
            ShowcaseSection(
              title: 'Dialog',
              child: AppButton(
                label: 'Open confirmation',
                variant: AppButtonVariant.secondary,
                onPressed: () {
                  showAppConfirmationDialog(
                    context,
                    title: 'Delete service?',
                    message: 'This action cannot be undone.',
                    confirmLabel: 'Delete',
                    destructive: true,
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        _group(
          title: 'AI',
          description: 'AI mode, panels, proposed actions, and thinking indicators.',
          children: [
            ShowcaseSection(
              title: 'AI mode toggle',
              child: Consumer(
                builder: (context, ref, _) {
                  final aiMode = ref.watch(aiModeProvider);
                  return Wrap(
                    spacing: AppSpacing.s3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const AppAiModeToggle(),
                      Text(
                        aiMode ? 'AI mode on' : 'AI mode off',
                        style: typography.bodySm.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  );
                },
              ),
            ),
            const ShowcaseSection(
              title: 'Thinking indicator',
              child: AppAiThinkingIndicator(),
            ),
            ShowcaseSection(
              title: 'Message bubble',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppAiMessageBubble(
                    role: AppAiMessageRole.user,
                    content: 'Summarize today\'s queue.',
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  AppAiMessageBubble(
                    role: AppAiMessageRole.assistant,
                    content: 'You have 4 patients checked in and 2 appointments starting within the hour.',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: PatternScaffold.sectionGap),
        _group(
          title: 'Layout & utility',
          description: 'Cards, dividers, keyboard hints, and page structure.',
          children: [
            ShowcaseSection(
              title: 'Card',
              child: AppCard(
                title: 'Branch settings',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configure hours, services, and staff assignments.',
                      style: typography.bodySm.copyWith(color: colors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    Text(
                      'Card body content uses familiar surface, border, and typography tokens.',
                      style: typography.body.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            ShowcaseSection(
              title: 'Divider & kbd',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppDivider(),
                  const SizedBox(height: AppSpacing.s4),
                  const AppKbd(keys: ['⌘', 'K']),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _group({
    required String title,
    required String description,
    required List<Widget> children,
  }) {
    final colors = context.colors;
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: typography.h2.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.s1),
        Text(description, style: typography.body.copyWith(color: colors.textSecondary)),
        const SizedBox(height: AppSpacing.s8),
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1) const SizedBox(height: AppSpacing.s8),
        ],
      ],
    );
  }
}

class _SegmentedDemo extends StatefulWidget {
  @override
  State<_SegmentedDemo> createState() => _SegmentedDemoState();
}

class _SegmentedDemoState extends State<_SegmentedDemo> {
  var _value = 'day';

  @override
  Widget build(BuildContext context) {
    return AppSegmentedControl<String>(
      value: _value,
      onChanged: (value) => setState(() => _value = value),
      semanticLabel: 'Calendar view',
      options: const [
        AppSegmentedOption(value: 'day', label: 'Day'),
        AppSegmentedOption(value: 'week', label: 'Week'),
        AppSegmentedOption(value: 'month', label: 'Month'),
      ],
    );
  }
}

class _ChoiceControlsDemo extends StatefulWidget {
  @override
  State<_ChoiceControlsDemo> createState() => _ChoiceControlsDemoState();
}

class _ChoiceControlsDemoState extends State<_ChoiceControlsDemo> {
  var _checked = true;
  var _radio = 'a';
  var _switched = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCheckbox(
          label: 'Send reminders',
          value: _checked,
          onChanged: (value) => setState(() => _checked = value ?? false),
        ),
        const SizedBox(height: AppSpacing.s2),
        AppRadioGroup<String>(
          value: _radio,
          onChanged: (value) => setState(() => _radio = value),
          options: const [
            AppRadioOption(value: 'a', label: 'Option A'),
            AppRadioOption(value: 'b', label: 'Option B'),
          ],
        ),
        const SizedBox(height: AppSpacing.s2),
        AppSwitch(
          label: 'Notifications',
          value: _switched,
          onChanged: (value) => setState(() => _switched = value),
        ),
      ],
    );
  }
}
