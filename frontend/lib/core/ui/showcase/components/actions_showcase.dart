import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

class ActionsShowcase extends StatefulWidget {
  const ActionsShowcase({super.key});

  @override
  State<ActionsShowcase> createState() => _ActionsShowcaseState();
}

class _ActionsShowcaseState extends State<ActionsShowcase> {
  String _segment = 'day';
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShowcaseSection(
          title: 'Button',
          description:
              'Primary actions with variants, sizes, loading, error, and disabled states.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.s3,
                runSpacing: AppSpacing.s3,
                children: AppButtonVariant.values.map((variant) {
                  return AppButton(
                    onPressed: () {},
                    variant: variant,
                    leadingIcon: variant == AppButtonVariant.ai
                        ? Icons.auto_awesome
                        : null,
                    child: Text(variant.name),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.s6),
              Wrap(
                spacing: AppSpacing.s3,
                runSpacing: AppSpacing.s3,
                children: AppButtonSize.values.map((size) {
                  return AppButton(
                    onPressed: () {},
                    size: size,
                    child: Text(size.name),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.s6),
              Wrap(
                spacing: AppSpacing.s3,
                runSpacing: AppSpacing.s3,
                children: [
                  AppButton(
                    onPressed: () {
                      setState(() => _loading = true);
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) setState(() => _loading = false);
                      });
                    },
                    loading: _loading,
                    child: Text(_loading ? 'Saving…' : 'Save'),
                  ),
                  AppButton(
                    onPressed: null,
                    disabled: true,
                    child: const Text('Disabled'),
                  ),
                  AppButton(
                    onPressed: null,
                    error: true,
                    child: const Text('Error'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Icon button',
          child: Wrap(
            spacing: AppSpacing.s3,
            runSpacing: AppSpacing.s3,
            children: [
              for (final variant in AppIconButtonVariant.values)
                AppIconButton(
                  icon: Icons.more_horiz,
                  semanticLabel: '${variant.name} menu',
                  variant: variant,
                  onPressed: () {},
                ),
              AppIconButton(
                icon: Icons.delete_outline,
                semanticLabel: 'Delete',
                variant: AppIconButtonVariant.danger,
                error: true,
                disabled: true,
                onPressed: null,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Segmented control',
          child: SizedBox(
            width: 360,
            child: AppSegmentedControl<String>(
              semanticLabel: 'Time range',
              options: [
                AppSegmentedOption(value: 'day', label: Text('Day')),
                AppSegmentedOption(value: 'week', label: Text('Week')),
                AppSegmentedOption(value: 'month', label: Text('Month')),
              ],
              selected: _segment,
              onChanged: (v) => setState(() => _segment = v),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s10),
        ShowcaseSection(
          title: 'Split button',
          child: AppSplitButton(
            label: 'Publish',
            onPrimaryAction: () {},
            items: const [
              AppSplitButtonMenuItem(id: 'draft', label: 'Save draft'),
              AppSplitButtonMenuItem(id: 'schedule', label: 'Schedule'),
              AppSplitButtonMenuItem(
                id: 'discard',
                label: 'Discard',
                destructive: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
