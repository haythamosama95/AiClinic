export interface CreditGaugeModel {
  credits_used: number
  credit_budget: number
}

const FORBIDDEN_KEY_PATTERN = /token|cost|price/i

export function parseCreditGaugeFromUsage(payload: unknown): CreditGaugeModel {
  if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) {
    throw new Error('Usage payload must be an object')
  }

  const currentPeriod = (payload as { current_period?: unknown }).current_period
  if (currentPeriod === null || typeof currentPeriod !== 'object' || Array.isArray(currentPeriod)) {
    throw new Error('Usage payload must include current_period')
  }

  const period = currentPeriod as Record<string, unknown>
  const creditsUsed = period.credits_used
  const creditBudget = period.credit_budget

  if (typeof creditsUsed !== 'number' || typeof creditBudget !== 'number') {
    throw new Error('current_period must include numeric credits_used and credit_budget')
  }

  const model: CreditGaugeModel = {
    credits_used: creditsUsed,
    credit_budget: creditBudget,
  }

  for (const key of Object.keys(model)) {
    if (FORBIDDEN_KEY_PATTERN.test(key)) {
      throw new Error(`Gauge model must not include ${key}`)
    }
  }

  return model
}
