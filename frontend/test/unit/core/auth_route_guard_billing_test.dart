import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  group('AuthRouteGuard billing', () {
    test('isBillingRoute matches static and invoice detail paths', () {
      expect(AuthRouteGuard.isBillingRoute(AppRoutes.billingInvoices), isTrue);
      expect(AuthRouteGuard.isBillingRoute(AppRoutes.billingInsuranceProviders), isTrue);
      expect(AuthRouteGuard.isBillingRoute(AppRoutes.settingsBilling), isTrue);
      expect(AuthRouteGuard.isBillingRoute(AppRoutes.billingInvoiceDetail('inv-1')), isTrue);
      expect(AuthRouteGuard.isBillingRoute(AppRoutes.billingInvoiceEdit('inv-1')), isTrue);
      expect(AuthRouteGuard.isBillingRoute(AppRoutes.home), isFalse);
    });

    test('receptionist with invoices.view can access invoice list and detail', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.receptionist, permissions: {PermissionKeys.invoicesView}),
      );

      expect(AuthRouteGuard.canAccessInvoiceList(auth), isTrue);
      expect(AuthRouteGuard.canAccessInvoiceDetail(auth), isTrue);
      expect(AuthRouteGuard.billingRouteRedirect(location: AppRoutes.billingInvoices, auth: auth), isNull);
      expect(
        AuthRouteGuard.billingRouteRedirect(location: AppRoutes.billingInvoiceDetail('inv-1'), auth: auth),
        isNull,
      );
    });

    test('doctor without billing permissions redirected from invoice routes', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.doctor, permissions: {PermissionKeys.patientsView}),
      );

      expect(AuthRouteGuard.canAccessInvoiceList(auth), isFalse);
      expect(AuthRouteGuard.billingRouteRedirect(location: AppRoutes.billingInvoices, auth: auth), AppRoutes.home);
    });

    test('insurance providers require insurance.manage', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.receptionist, permissions: {PermissionKeys.invoicesView}),
      );

      expect(AuthRouteGuard.canAccessInsuranceProviders(auth), isFalse);
      expect(
        AuthRouteGuard.billingRouteRedirect(location: AppRoutes.billingInsuranceProviders, auth: auth),
        AppRoutes.home,
      );
    });

    test('owner with insurance.manage can open insurance providers', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.administrator, permissions: RolePermissionSeed.administrator),
      );

      expect(AuthRouteGuard.billingRouteRedirect(location: AppRoutes.billingInsuranceProviders, auth: auth), isNull);
    });

    test('billing settings accessible with invoices.view or payments.record', () {
      final viewOnly = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(permissions: {PermissionKeys.invoicesView}),
      );
      final recordOnly = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(permissions: {PermissionKeys.paymentsRecord}),
      );
      final denied = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(permissions: {PermissionKeys.patientsView}),
      );

      expect(AuthRouteGuard.canAccessBillingSettings(viewOnly), isTrue);
      expect(AuthRouteGuard.canAccessBillingSettings(recordOnly), isTrue);
      expect(AuthRouteGuard.canAccessBillingSettings(denied), isFalse);
      expect(AuthRouteGuard.billingRouteRedirect(location: AppRoutes.settingsBilling, auth: denied), AppRoutes.home);
    });

    test('unauthenticated billing URL redirects to login', () {
      const auth = AuthSessionState(status: AuthSessionStatus.unauthenticated);
      expect(AuthRouteGuard.billingRouteRedirect(location: AppRoutes.billingInvoices, auth: auth), AppRoutes.login);
    });

    test('setup_required billing URL redirects to bootstrap', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(setupRequired: true, permissions: RolePermissionSeed.administrator),
      );

      expect(AuthRouteGuard.billingRouteRedirect(location: AppRoutes.billingInvoices, auth: auth), AppRoutes.bootstrap);
    });
  });
}
