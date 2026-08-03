import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_code_block.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';

const _sampleCode = '''{
  "patientId": "10482",
  "mrn": "MRN-10482"
}''';

/// Code block showcase (web `CodeBlockShowcase`).
class CodeBlockShowcaseSection extends ConsumerWidget {
  const CodeBlockShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ShowcaseSection(
      id: 'code-block',
      title: 'Code block',
      componentName: 'CodeBlock',
      child: AppCodeBlock(
        language: 'json',
        code: _sampleCode,
      ),
    );
  }
}
