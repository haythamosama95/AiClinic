import { ExternalLink, SearchX, UserRound } from 'lucide-react'
import { motion } from 'motion/react'
import { useMemo, useState } from 'react'
import { Avatar } from '@/components/avatar/Avatar'
import { Badge } from '@/components/badge'
import { Button } from '@/components/actions/Button'
import { EmptyState } from '@/components/empty-state/EmptyState'
import { FilterMenuPanel } from '@/components/layout/FilterMenuPanel'
import { ListControlBar } from '@/components/layout/ListControlBar'
import { PageHeader } from '@/components/layout/PageHeader'
import type { MenuEntry } from '@/components/navigation/Menu'
import { Pagination } from '@/components/navigation/Pagination'
import { MoneyDisplay } from '@/components/money/MoneyDisplay'
import { DataTable, type TableColumn } from '@/components/table/DataTable'
import {
  invoiceStatusColor,
  invoiceStatusLabel,
  type InvoiceListRow,
  formatDate,
} from '@/data/invoices'
import {
  DEFAULT_INVOICE_CONTROLS,
  INVOICE_BRANCH_FILTER_OPTIONS,
  INVOICE_SORT_OPTIONS,
  INVOICE_STATUS_FILTER_OPTIONS,
  ALL_INVOICES,
  filterAndSortInvoices,
  type InvoiceBranchFilter,
  type InvoiceListControls,
  type InvoiceStatusFilter,
} from './invoice-list-controls'

export type InvoicesPageProps = {
  onNavigate: (route: string) => void
}

const columns: TableColumn<InvoiceListRow>[] = [
  {
    id: 'number',
    header: 'Invoice',
    accessor: (row) => (
      <div className="min-w-0">
        <p className="truncate font-mono text-body-sm font-medium tracking-[0.04em] text-text-primary">
          {row.invoiceNumber ?? 'Not issued'}
        </p>
        <p className="text-caption tabular-nums text-text-tertiary">{formatDate(row.createdAt)}</p>
      </div>
    ),
  },
  {
    id: 'patient',
    header: 'Patient',
    accessor: (row) => (
      <div className="flex items-center gap-3">
        <Avatar name={row.patientName} size="sm" />
        <div className="min-w-0">
          <p className="truncate text-body-strong text-text-primary">{row.patientName}</p>
          <p className="text-caption tabular-nums text-text-tertiary">{row.patientMrn}</p>
        </div>
      </div>
    ),
  },
  {
    id: 'status',
    header: 'Status',
    accessor: (row) => (
      <Badge color={invoiceStatusColor(row.status)} variant="soft">
        {invoiceStatusLabel(row.status)}
      </Badge>
    ),
  },
  {
    id: 'subtotal',
    header: 'Subtotal',
    align: 'end',
    accessor: (row) => <MoneyDisplay amount={row.subtotal} />,
  },
  {
    id: 'payments',
    header: 'Total payments',
    align: 'end',
    accessor: (row) => (
      <MoneyDisplay
        amount={row.paidAmount}
        className={row.paidAmount <= 0 ? 'text-text-tertiary' : 'text-text-secondary'}
      />
    ),
  },
  {
    id: 'remaining',
    header: 'Remaining',
    align: 'end',
    accessor: (row) => (
      <MoneyDisplay
        amount={row.balance}
        emphasis={row.balance > 0 && row.status !== 'voided'}
        className={row.balance <= 0 ? 'text-status-success-fg' : undefined}
      />
    ),
  },
]

export function InvoicesPage({ onNavigate }: InvoicesPageProps) {
  const [controls, setControls] = useState<InvoiceListControls>(DEFAULT_INVOICE_CONTROLS)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)

  const filtered = useMemo(() => filterAndSortInvoices(ALL_INVOICES, controls), [controls])
  const paged = filtered.slice((page - 1) * pageSize, page * pageSize)

  const activeFilters = useMemo(() => {
    const chips: { id: string; label: string; onRemove: () => void }[] = []
    if (controls.status !== 'all') {
      chips.push({
        id: 'status',
        label: invoiceStatusLabel(controls.status),
        onRemove: () => {
          setControls((c) => ({ ...c, status: 'all' }))
          setPage(1)
        },
      })
    }
    if (controls.branch !== 'all') {
      const branch = INVOICE_BRANCH_FILTER_OPTIONS.find((o) => o.value === controls.branch)
      chips.push({
        id: 'branch',
        label: branch?.label ?? 'Branch',
        onRemove: () => {
          setControls((c) => ({ ...c, branch: 'all' }))
          setPage(1)
        },
      })
    }
    if (controls.search) {
      chips.push({
        id: 'search',
        label: `Search: ${controls.search}`,
        onRemove: () => {
          setControls((c) => ({ ...c, search: '' }))
          setPage(1)
        },
      })
    }
    return chips
  }, [controls.branch, controls.search, controls.status])

  const filterActiveCount =
    (controls.status !== 'all' ? 1 : 0) + (controls.branch !== 'all' ? 1 : 0)
  const clearFilters = () => {
    setControls((c) => ({ ...c, status: 'all', branch: 'all' }))
    setPage(1)
  }
  const clearAll = () => {
    setControls(DEFAULT_INVOICE_CONTROLS)
    setPage(1)
  }

  const hasInvoices = ALL_INVOICES.length > 0
  const hasResults = filtered.length > 0
  const isFiltered =
    controls.search !== '' ||
    controls.status !== 'all' ||
    controls.branch !== 'all' ||
    controls.sort !== DEFAULT_INVOICE_CONTROLS.sort

  const rowContextMenu = (row: InvoiceListRow): MenuEntry[] => [
    {
      id: 'open',
      label: 'Open invoice',
      icon: <ExternalLink size={16} strokeWidth={1.5} />,
      onSelect: () => onNavigate(`invoices/${row.id}`),
    },
    {
      id: 'patient',
      label: 'View patient',
      icon: <UserRound size={16} strokeWidth={1.5} />,
      onSelect: () => onNavigate(`patients/${row.patientId}`),
    },
  ]

  return (
    <motion.div
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.22 }}
      className="space-y-6"
    >
      <PageHeader
        title="Invoices"
        description="Every invoice for this branch — status, payments collected, and what's still owed."
      />

      {hasInvoices ? (
        <ListControlBar
          searchPlaceholder="Search by invoice number, patient, or MRN…"
          searchAriaLabel="Search invoices"
          search={controls.search}
          onSearchChange={(search) => {
            setControls((c) => ({ ...c, search }))
            setPage(1)
          }}
          sortValue={controls.sort}
          defaultSortValue={DEFAULT_INVOICE_CONTROLS.sort}
          sortOptions={[...INVOICE_SORT_OPTIONS]}
          onSortChange={(sort) => {
            setControls((c) => ({ ...c, sort: sort as InvoiceListControls['sort'] }))
            setPage(1)
          }}
          sortAriaLabel="Sort invoices"
          filterActiveCount={filterActiveCount}
          onClearFilters={filterActiveCount > 0 ? clearFilters : undefined}
          filterMenu={
            <FilterMenuPanel
              sections={[
                {
                  id: 'status',
                  label: 'Status',
                  value: controls.status,
                  options: [...INVOICE_STATUS_FILTER_OPTIONS],
                  onChange: (status) => {
                    setControls((c) => ({ ...c, status: status as InvoiceStatusFilter }))
                    setPage(1)
                  },
                },
                {
                  id: 'branch',
                  label: 'Branch',
                  value: controls.branch,
                  options: [...INVOICE_BRANCH_FILTER_OPTIONS],
                  onChange: (branch) => {
                    setControls((c) => ({ ...c, branch: branch as InvoiceBranchFilter }))
                    setPage(1)
                  },
                },
              ]}
            />
          }
          activeFilters={activeFilters}
          onClearAll={isFiltered ? clearAll : undefined}
        />
      ) : null}

      {!hasInvoices ? (
        <EmptyState
          variant="first-run"
          title="No invoices yet"
          description="Invoices appear here once a completed visit is billed."
        />
      ) : !hasResults ? (
        <div className="rounded-2xl border border-border-subtle bg-surface-default px-6 py-14 text-center shadow-elevation-1">
          <SearchX size={32} className="mx-auto text-icon-muted" strokeWidth={1.25} />
          <p className="mt-4 text-body-strong text-text-primary">No invoices match</p>
          <p className="mt-1 text-body-sm text-text-secondary">
            Try a different search term or clear your filters.
          </p>
          <Button className="mt-6" variant="secondary" onClick={clearAll}>
            Clear filters
          </Button>
        </div>
      ) : (
        <DataTable
          columns={columns}
          data={paged}
          getRowId={(r) => r.id}
          onRowClick={(row) => onNavigate(`invoices/${row.id}`)}
          rowContextMenu={rowContextMenu}
          animateRows
          aria-label="Invoices"
          emptyState={
            <EmptyState
              variant="no-results"
              title="No invoices match"
              description="Try a different search term or clear your filters."
            />
          }
        />
      )}

      {hasResults ? (
        <Pagination
          page={page}
          pageSize={pageSize}
          total={filtered.length}
          onPageChange={setPage}
          onPageSizeChange={(s) => {
            setPageSize(s)
            setPage(1)
          }}
        />
      ) : null}
    </motion.div>
  )
}