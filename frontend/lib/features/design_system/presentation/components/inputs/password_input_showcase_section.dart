import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_password_input.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _PasswordInputCopy {
  const _PasswordInputCopy({
    required this.passwordLabel,
    required this.passwordHelper,
    required this.passwordPlaceholder,
  });

  final String passwordLabel;
  final String passwordHelper;
  final String passwordPlaceholder;
}

const _copyEn = _PasswordInputCopy(
  passwordLabel: 'Password',
  passwordHelper: 'At least 8 characters.',
  passwordPlaceholder: 'Enter password',
);

const _copyAr = _PasswordInputCopy(
  passwordLabel: 'كلمة المرور',
  passwordHelper: 'ثمانية أحرف على الأقل.',
  passwordPlaceholder: 'أدخل كلمة المرور',
);

_PasswordInputCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Password input showcase (web `PasswordInputShowcase`).
class PasswordInputShowcaseSection extends ConsumerWidget {
  const PasswordInputShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    const passwordId = 'password-input-demo';

    return ShowcaseSection(
      id: 'password-input',
      title: 'Password input',
      description: 'Masked with reveal toggle and caps-lock hint.',
      componentName: 'PasswordInput',
      child: ShowcaseDemoGrid(
        children: [
          AppFormField(
            id: passwordId,
            label: copy.passwordLabel,
            helperText: copy.passwordHelper,
            child: AppPasswordInput(id: passwordId, placeholder: copy.passwordPlaceholder),
          ),
          ShowcaseDemo(
            label: 'Invalid',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: AppPasswordInput(invalid: true, initialValue: 'short'),
            ),
          ),
        ],
      ),
    );
  }
}
