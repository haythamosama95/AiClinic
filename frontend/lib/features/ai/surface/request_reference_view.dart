import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Displays the support request reference on failure (§13.2; FR-006).
const kAiRequestReferenceKey = Key('ai_request_reference');

class RequestReferenceView extends StatelessWidget {
  const RequestReferenceView({
    super.key,
    required this.requestReference,
  });

  final String requestReference;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Request reference $requestReference',
      child: Text(
        key: kAiRequestReferenceKey,
        'Reference: $requestReference',
        style: AppTypography.body(context),
      ),
    );
  }
}
