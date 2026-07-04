import { type ReactNode } from 'react'
import { cn } from '@/lib/cn'

export function ShowcaseSection({
  id,
  title,
  description,
  componentName,
  children,
}: {
  id: string
  title: string
  description?: string
  componentName?: string
  children: ReactNode
}) {
  return (
    <section id={id} className="scroll-mt-24">
      <div className="mb-6 border-b border-border-subtle pb-4">
        <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
          <h3 className="text-h3 text-text-primary">{title}</h3>
          {componentName ? (
            <code className="rounded-sm bg-surface-sunken px-2 py-0.5 font-mono text-caption text-text-tertiary">
              {componentName}
            </code>
          ) : null}
        </div>
        {description ? (
          <p className="mt-1 text-body text-text-secondary">{description}</p>
        ) : null}
      </div>
      {children}
    </section>
  )
}

export function ShowcaseDemoGrid({
  children,
  columns = 2,
}: {
  children: ReactNode
  columns?: 1 | 2 | 3 | 4
}) {
  const colClass =
    columns === 1
      ? 'grid-cols-1'
      : columns === 3
        ? 'sm:grid-cols-2 lg:grid-cols-3'
        : columns === 4
          ? 'sm:grid-cols-2 lg:grid-cols-4'
          : 'sm:grid-cols-2'

  return <div className={cn('grid gap-6', colClass)}>{children}</div>
}

export function ShowcaseDemo({
  label,
  propsHint,
  children,
}: {
  label: string
  propsHint?: string
  children: ReactNode
}) {
  return (
    <div className="rounded-lg border border-border-default bg-surface-default p-4">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <span className="text-body-strong text-text-primary">{label}</span>
        {propsHint ? (
          <span className="font-mono text-caption text-text-tertiary">{propsHint}</span>
        ) : null}
      </div>
      <div className="flex min-h-10 flex-wrap items-center gap-3">{children}</div>
    </div>
  )
}

export function ShowcaseVariantMatrix({
  title,
  children,
}: {
  title: string
  children: ReactNode
}) {
  return (
    <div className="space-y-3">
      <p className="text-overline text-text-tertiary">{title}</p>
      <div className="flex flex-wrap items-center gap-2">{children}</div>
    </div>
  )
}

export function PlaceholderSection({
  title,
  message,
}: {
  title: string
  message: string
}) {
  return (
    <div className="rounded-lg border border-dashed border-border-default bg-surface-sunken p-8 text-center">
      <p className="text-body-strong text-text-primary">{title}</p>
      <p className="mt-2 text-body text-text-secondary">{message}</p>
    </div>
  )
}
