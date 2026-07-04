import type { ReactNode } from 'react'
import { PageHeader } from '@/components/layout/PageHeader'
import { Skeleton } from '@/components/skeleton'

export type PlaceholderPageProps = {
  title: string
  description?: string
  breadcrumb?: ReactNode
  actions?: ReactNode
}

export function PlaceholderPage({
  title,
  description,
  breadcrumb,
  actions,
}: PlaceholderPageProps) {
  return (
    <>
      <PageHeader
        title={title}
        description={description}
        breadcrumb={breadcrumb}
        actions={actions}
      />
      <div className="mt-8 space-y-6">
        <div className="rounded-xl border border-dashed border-border-default bg-surface-default p-8 text-center">
          <p className="text-body-lg font-medium text-text-primary">Coming soon</p>
          <p className="mx-auto mt-2 max-w-md text-body-sm text-text-secondary">
            This area is scaffolded for the application shell. Feature content will land here in a
            future milestone.
          </p>
        </div>
        <div className="grid gap-4 sm:grid-cols-3">
          <Skeleton className="h-24 rounded-lg" />
          <Skeleton className="h-24 rounded-lg" />
          <Skeleton className="h-24 rounded-lg" />
        </div>
        <Skeleton className="h-48 w-full rounded-lg" />
      </div>
    </>
  )
}
