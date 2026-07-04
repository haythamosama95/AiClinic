import type { ReactNode } from 'react'

export function DevSectionLayout({
  nav,
  children,
}: {
  nav: ReactNode
  children: ReactNode
}) {
  return (
    <div className="flex gap-8 lg:gap-12">
      <aside className="hidden w-52 shrink-0 lg:block xl:w-56">
        <nav
          aria-label="Page sections"
          className="sticky top-6 max-h-[calc(100dvh-var(--shell-topbar-height)-3rem)] overflow-y-auto pe-2"
        >
          {nav}
        </nav>
      </aside>
      <div className="min-w-0 flex-1">{children}</div>
    </div>
  )
}
