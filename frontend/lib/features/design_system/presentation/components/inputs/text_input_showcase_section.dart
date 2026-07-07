import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _TextInputCopy {
  const _TextInputCopy({
    required this.small,
    required this.medium,
    required this.large,
    required this.email,
    required this.moneyPlaceholder,
    required this.percentPlaceholder,
    required this.defaultPlaceholder,
    required this.clearValue,
    required this.disabledValue,
    required this.readOnlyValue,
    required this.invalidValue,
    required this.filterTerm,
  });

  final String small;
  final String medium;
  final String large;
  final String email;
  final String moneyPlaceholder;
  final String percentPlaceholder;
  final String defaultPlaceholder;
  final String clearValue;
  final String disabledValue;
  final String readOnlyValue;
  final String invalidValue;
  final String filterTerm;
}

const _copyEn = _TextInputCopy(
  small: 'Small',
  medium: 'Medium',
  large: 'Large',
  email: 'Email address',
  moneyPlaceholder: '0.00',
  percentPlaceholder: '0',
  defaultPlaceholder: 'e.g. Consultation',
  clearValue: 'General checkup',
  disabledValue: 'Disabled',
  readOnlyValue: 'Read only',
  invalidValue: 'Invalid value',
  filterTerm: 'Filter term',
);

const _copyAr = _TextInputCopy(
  small: 'صغير',
  medium: 'متوسط',
  large: 'كبير',
  email: 'البريد الإلكتروني',
  moneyPlaceholder: '0.00',
  percentPlaceholder: '0',
  defaultPlaceholder: 'مثال: استشارة',
  clearValue: 'فحص عام',
  disabledValue: 'معطّل',
  readOnlyValue: 'للقراءة فقط',
  invalidValue: 'قيمة غير صالحة',
  filterTerm: 'مصطلح التصفية',
);

_TextInputCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Text input showcase (web `TextInputShowcase`).
class TextInputShowcaseSection extends ConsumerStatefulWidget {
  const TextInputShowcaseSection({super.key});

  @override
  ConsumerState<TextInputShowcaseSection> createState() => _TextInputShowcaseSectionState();
}

class _TextInputShowcaseSectionState extends ConsumerState<TextInputShowcaseSection> {
  late TextEditingController _clearController;
  late TextEditingController _matrixController;

  @override
  void initState() {
    super.initState();
    final copy = _copyFor(ref.read(devPreviewProvider).locale);
    _clearController = TextEditingController(text: copy.clearValue);
    _matrixController = TextEditingController(text: copy.filterTerm);
  }

  @override
  void dispose() {
    _clearController.dispose();
    _matrixController.dispose();
    super.dispose();
  }

  void _syncLocale(String locale) {
    final copy = _copyFor(locale);
    _clearController.text = copy.clearValue;
    _matrixController.text = copy.filterTerm;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(devPreviewProvider.select((state) => state.locale), (previous, next) {
      if (previous != next) _syncLocale(next);
    });
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'text-input',
      title: 'Text input',
      description: 'Default, affix, icon, clear, sizes, and universal states.',
      componentName: 'TextInput',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShowcaseDemoGrid(
            columns: 3,
            children: [
              ShowcaseDemo(
                label: 'Sizes',
                propsHint: 'sm · md · lg',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppTextInput(size: AppInputSize.sm, placeholder: copy.small),
                    const SizedBox(height: AppSpacing.space3),
                    AppTextInput(size: AppInputSize.md, placeholder: copy.medium),
                    const SizedBox(height: AppSpacing.space3),
                    AppTextInput(size: AppInputSize.lg, placeholder: copy.large),
                  ],
                ),
              ),
              ShowcaseDemo(
                label: 'Variants',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppTextInput(
                      leadingIcon: const Icon(Icons.mail_outline),
                      placeholder: copy.email,
                    ),
                    const SizedBox(height: AppSpacing.space3),
                    AppTextInput(prefix: 'EGP', placeholder: copy.moneyPlaceholder),
                    const SizedBox(height: AppSpacing.space3),
                    AppTextInput(
                      suffix: '%',
                      trailingIcon: const Icon(Icons.percent),
                      placeholder: copy.percentPlaceholder,
                    ),
                  ],
                ),
              ),
              ShowcaseDemo(
                label: 'States',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppTextInput(placeholder: copy.defaultPlaceholder),
                    const SizedBox(height: AppSpacing.space3),
                    AppTextInput(
                      controller: _clearController,
                      showClear: true,
                      onClear: () => _clearController.clear(),
                    ),
                    const SizedBox(height: AppSpacing.space3),
                    AppTextInput(disabled: true, initialValue: copy.disabledValue),
                    const SizedBox(height: AppSpacing.space3),
                    AppTextInput(readOnly: true, initialValue: copy.readOnlyValue),
                    const SizedBox(height: AppSpacing.space3),
                    AppTextInput(invalid: true, initialValue: copy.invalidValue),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space8),
          ShowcaseVariantMatrix(
            title: 'With value + clear',
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: AppTextInput(
                  controller: _matrixController,
                  showClear: true,
                  onClear: () => _matrixController.clear(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
