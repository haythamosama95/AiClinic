import type { CreditGaugeModel } from '@/lib/credit-gauge'

interface CreditGaugeProps {
  model: CreditGaugeModel | null
}

export function CreditGauge({ model }: CreditGaugeProps) {
  if (!model) {
    return (
      <section className="credit-gauge credit-gauge--empty" aria-label="Credit gauge">
        <p className="credit-gauge__hint">
          Send GET /v1/usage to render consumed credits versus budget.
        </p>
      </section>
    )
  }

  const ratio =
    model.credit_budget > 0 ? model.credits_used / model.credit_budget : 0
  const percent = Math.min(100, Math.round(ratio * 100))

  return (
    <section className="credit-gauge" aria-label="Credit gauge">
      <div className="credit-gauge__header">
        <h2 className="credit-gauge__title">Current period credits</h2>
        <p className="credit-gauge__values">
          <span className="credit-gauge__used">{model.credits_used}</span>
          <span className="credit-gauge__sep">/</span>
          <span className="credit-gauge__budget">{model.credit_budget}</span>
        </p>
      </div>
      <div
        className="credit-gauge__bar"
        role="meter"
        aria-valuenow={model.credits_used}
        aria-valuemin={0}
        aria-valuemax={model.credit_budget}
        aria-label="Credits consumed versus budget"
      >
        <div className="credit-gauge__fill" style={{ width: `${percent}%` }} />
      </div>
    </section>
  )
}
