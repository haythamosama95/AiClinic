import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_error_state.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _ErrorStateCopy {
  const _ErrorStateCopy({required this.message});

  final String message;
}

const _copyEn = _ErrorStateCopy(
  message: 'We could not load appointments. Check your connection and try again.',
);

const _copyAr = _ErrorStateCopy(
  message: 'تعذّر تحميل المواعيد. تحقق من اتصالك وحاول مرة أخرى.',
);

_ErrorStateCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Error state showcase (web `ErrorStateShowcase`).
class ErrorStateShowcaseSection extends ConsumerWidget {
  const ErrorStateShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'error-state',
      title: 'Error state',
      componentName: 'ErrorState',
      child: AppErrorState(
        message: copy.message,
        onRetry: () {},
      ),
    );
  }
}
