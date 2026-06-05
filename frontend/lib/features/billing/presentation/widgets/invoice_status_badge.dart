import 'package:flutter/material.dart';

import 'package:ai_clinic/features/billing/domain/invoice_status.dart';

/// Compact status chip for invoice list and detail surfaces (V1-6).
class InvoiceStatusBadge extends StatelessWidget {
  const InvoiceStatusBadge({super.key, required this.status});

  final InvoiceStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colorsFor(status);

    return DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          status.label,
          key: Key('invoice_status_badge_${status.wireValue}'),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground),
        ),
      ),
    );
  }

  (Color, Color) _colorsFor(InvoiceStatus status) {
    return switch (status) {
      InvoiceStatus.draft => (Colors.blueGrey.shade100, Colors.blueGrey.shade900),
      InvoiceStatus.issued => (Colors.orange.shade100, Colors.orange.shade900),
      InvoiceStatus.partiallyPaid => (Colors.amber.shade100, Colors.amber.shade900),
      InvoiceStatus.paid => (Colors.green.shade100, Colors.green.shade900),
      InvoiceStatus.voided => (Colors.red.shade100, Colors.red.shade900),
    };
  }
}
