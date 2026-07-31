import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'

function getScrollContainer(element: HTMLElement): HTMLElement | null {
  let parent = element.parentElement
  while (parent) {
    const { overflowY } = getComputedStyle(parent)
    if (overflowY === 'auto' || overflowY === 'scroll' || overflowY === 'overlay') {
      return parent
    }
    parent = parent.parentElement
  }
  return null
}

export function scrollToDevSection(sectionId: string): boolean {
  const element = document.getElementById(sectionId)
  if (!element) {
    if (import.meta.env.DEV) {
      console.warn(`[dev-nav] Section not found: #${sectionId}`)
    }
    return false
  }

  const scrollContainer = document.getElementById('main') ?? getScrollContainer(element)
  if (scrollContainer && scrollContainer !== document.documentElement && scrollContainer !== document.body) {
    const scrollMargin = Number.parseFloat(getComputedStyle(element).scrollMarginTop) || 0
    const top =
      scrollContainer.scrollTop +
      element.getBoundingClientRect().top -
      scrollContainer.getBoundingClientRect().top -
      scrollMargin

    scrollContainer.scrollTo({ top: Math.max(0, top), behavior: 'smooth' })
    return true
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
