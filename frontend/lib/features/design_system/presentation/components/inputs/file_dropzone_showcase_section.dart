import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_file_dropzone.dart';
import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _FileDropzoneCopy {
  const _FileDropzoneCopy({
    required this.label,
    required this.helper,
    required this.description,
  });

  final String label;
  final String helper;
  final String description;
}

const _copyEn = _FileDropzoneCopy(
  label: 'Patient attachments',
  helper: 'PDF, JPG, or PNG lab reports and scans.',
  description: 'Drag-over, browse, per-file progress, success/error, and remove.',
);

const _copyAr = _FileDropzoneCopy(
  label: 'مرفقات المريض',
  helper: 'تقارير ومسحات مختبر بصيغة PDF أو JPG أو PNG.',
  description: 'سحب وإفلات، تصفح، تقدم لكل ملف، نجاح/خطأ، وإزالة.',
);

_FileDropzoneCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// File dropzone showcase (web `FileDropzoneShowcase`).
class FileDropzoneShowcaseSection extends ConsumerStatefulWidget {
  const FileDropzoneShowcaseSection({super.key});

  @override
  ConsumerState<FileDropzoneShowcaseSection> createState() => _FileDropzoneShowcaseSectionState();
}

class _FileDropzoneShowcaseSectionState extends ConsumerState<FileDropzoneShowcaseSection> {
  List<AppFileItem> _files = [];

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    const fieldId = 'file-dropzone-patient-attachments';

    return ShowcaseSection(
      id: 'file-dropzone',
      title: 'File dropzone',
      componentName: 'FileDropzone',
      description: copy.description,
      child: AppFormField(
        id: fieldId,
        label: copy.label,
        helperText: copy.helper,
        child: AppFileDropzone(
          id: fieldId,
          files: _files,
          onFilesChange: (next) => setState(() => _files = next),
        ),
      ),
    );
  }
}
