import 'package:ai_clinic/app/app_routes.dart';

/// Shared query-parameter contract for [AppRoutes.login].
///
/// [LoginPage] should read [forgotPasswordQueryKey] to auto-show the forgot-password
/// message when users arrive via [AppRoutes.forgotPassword] or [goForgotPassword].
abstract final class LoginQueryParams {
  /// Query key set by the forgot-password redirect (`?forgot=1`).
  static const forgotPasswordQueryKey = 'forgot';

  /// Value that signals forgot-password intent on the login route.
  static const forgotPasswordQueryValue = '1';

  /// Login location that preserves forgot-password intent for [LoginPage].
  static String loginWithForgotPasswordIntent() =>
      '${AppRoutes.login}?$forgotPasswordQueryKey=$forgotPasswordQueryValue';

  /// Whether [queryParameters] request the forgot-password message on login.
  static bool isForgotPasswordIntent(Map<String, String> queryParameters) =>
      queryParameters[forgotPasswordQueryKey] == forgotPasswordQueryValue;
}
