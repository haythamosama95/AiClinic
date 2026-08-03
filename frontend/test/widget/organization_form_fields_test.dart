import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/presentation/forms/organization_form_fields.dart';

void main() {
  testWidgets('OrganizationFormFields displays fetched organization values in read-only mode', (tester) async {
    const organization = OrganizationProfile(
      id: 'org-1',
      name: 'Downtown Clinic',
      logoUrl: 'https://cdn.example/logo.png',
      currencyCode: 'EGP',
      timezone: 'Africa/Cairo',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: OrganizationFormFields(
            values: organizationToFormValues(organization),
            onChanged: (_) {},
            disabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Downtown Clinic'), findsOneWidget);
    expect(find.text('https://cdn.example/logo.png'), findsOneWidget);
    expect(find.text('EGP'), findsOneWidget);
    expect(find.text('Africa/Cairo'), findsOneWidget);
  });
}
