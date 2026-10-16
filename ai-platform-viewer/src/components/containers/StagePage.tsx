import type { ReactNode } from 'react'

interface StagePageProps {
  accentClass?: string
  children: ReactNode
}

export function StagePage({ accentClass, children }: StagePageProps) {
  return (
    <section className={`stage-page${accentClass ? ` ${accentClass}` : ''}`}>
      {children}
    </section>
  )
}
