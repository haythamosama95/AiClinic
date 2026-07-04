/// Administrator-mediated recovery copy (US7) — shown inline on the login form.
abstract final class LoginForgotPasswordInfo {
  static const title = 'Password recovery is administrator-mediated';

  static const body =
      'AiClinic does not offer self-service password reset. Contact your clinic '
      'administrator to set a new password for your staff account.\n\n'
      'If you are the clinic administrator, sign in with your administrator account, open '
      'Settings → Staff, select the staff member, and use Reset password.';
}
