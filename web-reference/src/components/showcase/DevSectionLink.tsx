import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'

export function scrollToDevSection(sectionId: string): boolean {
  const element = document.getElementById(sectionId)
  if (!element) {
    if (import.meta.env.DEV) {
      console.warn(`[dev-nav] Section not found: #${sectionId}`)
    }
    return false
  }

  element.scrollIntoView({ behavior: 'smooth', block: 'start' })
  return true
}

type DevSectionLinkProps = {
  sectionId: string
  className?: string
  children: ReactNode
}

export function DevSectionLink({ sectionId, className, children }: DevSectionLinkProps) {
  return (
    <a
      href={`#${sectionId}`}
      className={cn(className)}
      onClick={(event) => {
        event.preventDefault()
        scrollToDevSection(sectionId)
      }}
    >
      {children}
    </a>
  )
}
