import { useCallback, useState } from 'react'

export const BILLING_STORAGE_KEY = 'aiclinic:billing-settings'

export type BillingSettings = {
  allowPartialPayments: boolean
}

export const DEFAULT_BILLING_SETTINGS: BillingSettings = {
  allowPartialPayments: false,
}

function loadBillingSettings(): BillingSettings {
  if (typeof window === 'undefined') return DEFAULT_BILLING_SETTINGS
  try {
    const raw = localStorage.getItem(BILLING_STORAGE_KEY)
    if (!raw) return DEFAULT_BILLING_SETTINGS
    const parsed = JSON.parse(raw) as Partial<BillingSettings>
    return {
      allowPartialPayments: parsed.allowPartialPayments ?? DEFAULT_BILLING_SETTINGS.allowPartialPayments,
    }
  } catch {
    return DEFAULT_BILLING_SETTINGS
  }
}

export function useBillingSettings() {
  const [settings, setSettingsState] = useState<BillingSettings>(loadBillingSettings)

  const updateSettings = useCallback((patch: Partial<BillingSettings>) => {
    setSettingsState((prev) => {
      const next = { ...prev, ...patch }
      localStorage.setItem(BILLING_STORAGE_KEY, JSON.stringify(next))
      return next
    })
  }, [])

  return { settings, updateSettings }
}
