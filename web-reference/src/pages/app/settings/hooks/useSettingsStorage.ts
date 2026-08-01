import { useCallback, useState } from 'react'
import {
  DATE_FORMAT_DEFAULT,
  DATE_FORMAT_STORAGE_KEY,
  type DateFormat,
  IDLE_TIMEOUT_DEFAULT,
  IDLE_TIMEOUT_MAX,
  IDLE_TIMEOUT_MIN,
  IDLE_TIMEOUT_STORAGE_KEY,
  NOTIFICATION_PREFS_DEFAULT,
  NOTIFICATION_PREFS_STORAGE_KEY,
  type NotificationPrefs,
  TIME_FORMAT_DEFAULT,
  TIME_FORMAT_STORAGE_KEY,
  type TimeFormat,
} from '@/data/settings'

export function clampIdleTimeout(minutes: number): number {
  return Math.min(IDLE_TIMEOUT_MAX, Math.max(IDLE_TIMEOUT_MIN, Math.round(minutes)))
}

export function loadIdleTimeout(): number {
  if (typeof window === 'undefined') return IDLE_TIMEOUT_DEFAULT
  try {
    const raw = localStorage.getItem(IDLE_TIMEOUT_STORAGE_KEY)
    if (raw) {
      const parsed = Number.parseInt(raw, 10)
      if (!Number.isNaN(parsed)) return clampIdleTimeout(parsed)
    }
  } catch {
    /* use default */
  }
  return IDLE_TIMEOUT_DEFAULT
}

export function useIdleTimeout() {
  const [minutes, setMinutesState] = useState(loadIdleTimeout)

  const setMinutes = useCallback((value: number) => {
    const clamped = clampIdleTimeout(value)
    setMinutesState(clamped)
    localStorage.setItem(IDLE_TIMEOUT_STORAGE_KEY, String(clamped))
  }, [])

  return { minutes, setMinutes }
}

function loadDateFormat(): DateFormat {
  if (typeof window === 'undefined') return DATE_FORMAT_DEFAULT
  try {
    const raw = localStorage.getItem(DATE_FORMAT_STORAGE_KEY)
    if (raw === 'mdy' || raw === 'dmy' || raw === 'ymd') return raw
  } catch {
    /* use default */
  }
  return DATE_FORMAT_DEFAULT
}

function loadTimeFormat(): TimeFormat {
  if (typeof window === 'undefined') return TIME_FORMAT_DEFAULT
  try {
    const raw = localStorage.getItem(TIME_FORMAT_STORAGE_KEY)
    if (raw === '12h' || raw === '24h') return raw
  } catch {
    /* use default */
  }
  return TIME_FORMAT_DEFAULT
}

export function useFormatPreferences() {
  const [dateFormat, setDateFormatState] = useState<DateFormat>(loadDateFormat)
  const [timeFormat, setTimeFormatState] = useState<TimeFormat>(loadTimeFormat)

  const setDateFormat = useCallback((value: DateFormat) => {
    setDateFormatState(value)
    localStorage.setItem(DATE_FORMAT_STORAGE_KEY, value)
  }, [])

  const setTimeFormat = useCallback((value: TimeFormat) => {
    setTimeFormatState(value)
    localStorage.setItem(TIME_FORMAT_STORAGE_KEY, value)
  }, [])

  return { dateFormat, setDateFormat, timeFormat, setTimeFormat }
}

function loadNotificationPrefs(): NotificationPrefs {
  if (typeof window === 'undefined') return NOTIFICATION_PREFS_DEFAULT
  try {
    const raw = localStorage.getItem(NOTIFICATION_PREFS_STORAGE_KEY)
    if (raw) {
      const parsed = JSON.parse(raw) as Partial<NotificationPrefs>
      return { ...NOTIFICATION_PREFS_DEFAULT, ...parsed }
    }
  } catch {
    /* use default */
  }
  return NOTIFICATION_PREFS_DEFAULT
}

export function useNotificationPrefs() {
  const [prefs, setPrefsState] = useState<NotificationPrefs>(loadNotificationPrefs)

  const setPref = useCallback(<K extends keyof NotificationPrefs>(key: K, value: NotificationPrefs[K]) => {
    setPrefsState((prev) => {
      const next = { ...prev, [key]: value }
      localStorage.setItem(NOTIFICATION_PREFS_STORAGE_KEY, JSON.stringify(next))
      return next
    })
  }, [])

  return { prefs, setPref }
}
