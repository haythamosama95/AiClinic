import type { ReactNode } from 'react'

interface StagePageSeedProps {
  label: string
  variant?: string
  children: ReactNode
}

export function StagePageSeed({ label, variant, children }: StagePageSeedProps) {
  return (
    <div
      className={`stage-page__seed${variant ? ` stage-page__seed--${variant}` : ''}`}
    >
      <p className="stage-page__seed-label">{label}</p>
      {children}
    </div>
  )
}
