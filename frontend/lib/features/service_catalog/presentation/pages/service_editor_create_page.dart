import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/service_catalog/presentation/widgets/service_form.dart';

/// Create service editor (`/settings/services/new`, 015 US1).
class ServiceEditorCreatePage extends ConsumerWidget {
  const ServiceEditorCreatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ServiceForm();
  }
}
