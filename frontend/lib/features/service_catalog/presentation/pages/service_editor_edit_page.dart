import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/service_catalog/presentation/widgets/service_form.dart';

/// Edit service editor (`/settings/services/:serviceId/edit`, 015 US1).
class ServiceEditorEditPage extends ConsumerWidget {
  const ServiceEditorEditPage({required this.serviceId, super.key});

  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ServiceForm(serviceId: serviceId);
  }
}
