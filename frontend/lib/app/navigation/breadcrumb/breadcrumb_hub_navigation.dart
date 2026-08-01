import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';

/// Pops to the invoices list when stacked; otherwise navigates to the hub.
void popOrGoInvoicesHub(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(AppRoutes.billingInvoices);
  }
}
