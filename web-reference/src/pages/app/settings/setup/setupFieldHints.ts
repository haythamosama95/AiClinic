/** Tooltip descriptions for clinic setup form fields. */
export const SETUP_FIELD_HINTS = {
  organizationName:
    'The legal or trading name of your clinic, shown across all branches.',
  timezone: 'Regional timezone for appointments, schedules, and reports.',
  currency: 'Used for invoices, services, and financial reports.',

  branchName: 'Display name for this location.',
  branchCode: 'Short identifier used in reports.',
  branchMobile: 'Branch contact number for patients and staff.',
  branchMapLocation:
    'Patients use this to find your branch on the map. Paste a Google Maps link or street address.',
  branchWorkingHours:
    'Appointment availability for this branch. Enable each day and set open hours.',

  staffName: 'Full name as shown in the clinic app.',
  staffMobile: 'Contact number for this staff member.',
  staffUsername: 'Sign-in username for the clinic app.',
  staffPassword: 'At least 8 characters with one letter. Used to sign in to the clinic app.',
  staffRole: 'Controls what features and data this person can access.',
  staffBranches: 'Branches this person can work at and view.',

  serviceName: 'Procedure or treatment name as shown on invoices.',
  servicePrice: 'Default price in your organization currency.',
} as const
