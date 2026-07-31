import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_textarea.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _TextareaCopy {
  const _TextareaCopy({
    required this.clinicalNotes,
    required this.notesHelper,
    required this.notesPlaceholder,
    required this.autoGrowValue,
  });

  final String clinicalNotes;
  final String notesHelper;
  final String notesPlaceholder;
  final String autoGrowValue;
}

const _copyEn = _TextareaCopy(
  clinicalNotes: 'Clinical notes',
  notesHelper: 'Visible to care team only.',
  notesPlaceholder: 'Document findings and plan…',
  autoGrowValue: 'Auto-growing textarea with character counter.',
);

const _copyAr = _TextareaCopy(
  clinicalNotes: 'ملاحظات سريرية',
  notesHelper: 'مرئية لفريق الرعاية فقط.',
  notesPlaceholder: 'وثّق النتائج والخطة…',
  autoGrowValue: 'منطقة نص متوسعة تلقائياً مع عداد أحرف.',
);

_TextareaCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Textarea showcase (web `TextareaShowcase`).
class TextareaShowcaseSection extends ConsumerWidget {
  const TextareaShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    const notesId = 'textarea-notes-demo';

    return ShowcaseSection(
      id: 'textarea',
      title: 'Textarea',
      componentName: 'Textarea',
      child: ShowcaseDemoGrid(
        children: [
          AppFormField(
            id: notesId,
            label: copy.clinicalNotes,
            helperText: copy.notesHelper,
            child: AppTextarea(id: notesId, placeholder: copy.notesPlaceholder, rows: 4),
          ),
          ShowcaseDemo(
            label: 'Auto-grow + counter',
            propsHint: 'autoGrow showCounter maxLength',
            child: AppTextarea(autoGrow: true, showCounter: true, maxLength: 200, initialValue: copy.autoGrowValue),
          ),
        ],
      ),
    );
  }
}
