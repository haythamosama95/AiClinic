/// Tooltip descriptions for clinic setup form fields.
abstract final class SetupFieldHints {
  static const organizationName = 'The legal or trading name of your clinic, shown across all branches.';
  static const timezone = 'Regional timezone for appointments, schedules, and reports.';
  static const currency = 'Used for invoices, services, and financial reports.';

  static const branchName = 'Display name for this location.';
  static const branchCode = 'Short identifier used in reports.';
  static const branchMobile = 'Branch contact number for patients and staff.';
  static const branchMapLocation =
      'Patients use this to find your branch on the map. Paste a Google Maps link or street address.';
  static const branchWorkingHours = 'Appointment availability for this branch. Enable each day and set open hours.';

  static const staffName = 'Full name as shown in the clinic app.';
  static const staffMobile = 'Contact number for this staff member.';
  static const staffUsername = 'Sign-in username for the clinic app.';
  static const staffPassword = 'At least 8 characters with one letter. Used to sign in to the clinic app.';
  static const staffRole = 'Controls what features and data this person can access.';
  static const staffBranches = 'Branches this person can work at and view.';

  static const serviceName = 'Procedure or treatment name as shown on invoices.';
  static const servicePrice = 'Default price in your organization currency.';
}
