import { useState } from 'react'
import { Alert } from '@/components/alert/Alert'
import { EmptyState } from '@/components/empty-state/EmptyState'
import { ErrorState } from '@/components/error-state/ErrorState'
import { LoadingOverlay } from '@/components/loading-overlay/LoadingOverlay'
import { SegmentedControl } from '@/components/actions/SegmentedControl'
import { DataTable, type TableColumn } from '@/components/table/DataTable'
import { Skeleton } from '@/components/skeleton/Skeleton'
import { ShowcaseSection } from '../ShowcasePrimitives'
import { MOCK_SERVICES, type ServiceRow } from './mock-data'
import { PatternFrame } from './PatternFrame'

type SurfaceState = 'loading' | 'empty-first' | 'empty-results' | 'error' | 'no-access' | 'degraded' | 'ready'

const STATE_OPTIONS: { value: SurfaceState; label: string }[] = [
  { value: 'loading', label: 'Loading' },
  { value: 'empty-first', label: 'First-run' },
  { value: 'empty-results', label: 'No results' },
  { value: 'error', label: 'Error' },
  { value: 'no-access', label: 'No access' },
  { value: 'degraded', label: 'Degraded' },
  { value: 'ready', label: 'Ready' },
]

const columns: TableColumn<ServiceRow>[] = [
  { id: 'name', header: 'Service', accessor: (r) => r.name },
  {
    id: 'price',
    header: 'Price',
    align: 'end',
    accessor: (r) => <span className="tabular-nums">{r.defaultPrice.toFixed(2)}</span>,
  },
]

export function StateGalleryPattern() {
  const [state, setState] = useState<SurfaceState>('ready')

  return (
    <ShowcaseSection
      id="pattern-state-gallery"
      title="State gallery"
      componentName="05 §6 Content states"
      description="Loading, empty, error, no-access, and degraded treatments on a representative list surface."
    >
      <div className="mb-4">
        <SegmentedControl
          aria-label="Preview content state"
          size="sm"
          value={state}
          onChange={setState}
          options={STATE_OPTIONS}
        />
      </div>

      <PatternFrame minHeight="320px" className="relative">
        {state === 'degraded' ? (
          <Alert variant="warning" title="Read-only mode" className="m-4 rounded-none border-x-0 border-t-0">
            Your subscription limits edits. You can still view all records.
          </Alert>
        ) : null}

        {state === 'loading' ? (
          <LoadingOverlay scoped label="Loading services…">
            <div className="space-y-3 p-4">
              <Skeleton className="h-8 w-48" />
              <Skeleton className="h-10 w-full" />
              {Array.from({ length: 4 }).map((_, i) => (
                <Skeleton key={i} className="h-10 w-full" />
              ))}
            </div>
          </LoadingOverlay>
        ) : null}

        {state === 'empty-first' ? (
          <EmptyState
            variant="first-run"
            title="No services yet"
            description="Add your first service to start billing."
            action={{ label: 'Add service', onClick: () => undefined }}
          />
        ) : null}

        {state === 'empty-results' ? (
          <EmptyState
            variant="no-results"
            title="No matches"
            description="Try adjusting your search or filters."
            action={{ label: 'Clear filters', onClick: () => undefined }}
          />
        ) : null}

        {state === 'error' ? (
          <ErrorState
            message="Can't reach the server. Check your connection and try again."
            onRetry={() => undefined}
          />
        ) : null}

        {state === 'no-access' ? (
          <EmptyState
            variant="no-access"
            title="No access"
            description="You need the services.view permission to see this catalog."
          />
        ) : null}

        {(state === 'ready' || state === 'degraded') ? (
          <div className="p-4">
            <DataTable
              columns={columns}
              data={MOCK_SERVICES.slice(0, 5)}
              getRowId={(r) => r.id}
              aria-label="Services preview"
            />
          </div>
        ) : null}
      </PatternFrame>
    </ShowcaseSection>
  )
}
