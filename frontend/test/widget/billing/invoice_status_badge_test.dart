import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';

void main() {
  for (final status in InvoiceStatus.values) {
    testWidgets('InvoiceStatusBadge renders ${status.label} for ${status.name}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: InvoiceStatusBadge(status: status),
          ),
        ),
      );

      expect(find.text(status.label), findsOneWidget);
    });
  }
}
