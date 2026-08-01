export const IDLE_TIMEOUT_PRESETS = [5, 10, 15, 20, 30, 45, 60] as const
export const IDLE_TIMEOUT_MIN = 1
export const IDLE_TIMEOUT_MAX = 120
export const IDLE_TIMEOUT_DEFAULT = 15
export const IDLE_TIMEOUT_STORAGE_KEY = 'aiclinic:idle-timeout-minutes'

export const DATE_FORMAT_OPTIONS = [
  { value: 'mdy', label: 'MM/DD/YYYY' },
  { value: 'dmy', label: 'DD/MM/YYYY' },
  { value: 'ymd', label: 'YYYY-MM-DD' },
] as const

export type DateFormat = (typeof DATE_FORMAT_OPTIONS)[number]['value']

export const TIME_FORMAT_OPTIONS = [
  { value: '12h', label: '12-hour (3:30 PM)' },
  { value: '24h', label: '24-hour (15:30)' },
] as const

export type TimeFormat = (typeof TIME_FORMAT_OPTIONS)[number]['value']

export const DATE_FORMAT_STORAGE_KEY = 'aiclinic:date-format'
export const TIME_FORMAT_STORAGE_KEY = 'aiclinic:time-format'
export const DATE_FORMAT_DEFAULT: DateFormat = 'mdy'
export const TIME_FORMAT_DEFAULT: TimeFormat = '12h'

export const NOTIFICATION_PREFS_STORAGE_KEY = 'aiclinic:notification-prefs'

export type NotificationPrefs = {
  appointmentReminders: boolean
  billingAlerts: boolean
  labResults: boolean
  shiftHandoffs: boolean
  productUpdates: boolean
}

export const NOTIFICATION_PREFS_DEFAULT: NotificationPrefs = {
  appointmentReminders: true,
  billingAlerts: true,
  labResults: true,
  shiftHandoffs: false,
  productUpdates: false,
}

export const SETTINGS_SCREENS = [
  { id: 'appearance', label: 'Appearance', description: 'Theme, language, and display formats' },
  { id: 'notifications', label: 'Notifications', description: 'Alerts and delivery preferences' },
  { id: 'security', label: 'Security', description: 'Workstation idle sign-out' },
] as const

export type SettingsScreenId = (typeof SETTINGS_SCREENS)[number]['id']
