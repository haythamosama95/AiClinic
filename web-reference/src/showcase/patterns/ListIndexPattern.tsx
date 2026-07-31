import { Plus } from 'lucide-react'
import { useMemo, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Badge } from '@/components/badge'
import { BulkActionBar } from '@/components/layout/BulkActionBar'
import { PageHeader } from '@/components/layout/PageHeader'
import { Toolbar } from '@/components/layout/Toolbar'
import { MoneyDisplay } from '@/components/money/MoneyDisplay'
import { Pagination } from '@/components/navigation/Pagination'
import { DataTable, type TableColumn } from '@/components/table/DataTable'
import { Chip } from '@/components/chip'
import { SearchInput } from '@/components/ui/search-input/SearchInput'
import { Select } from '@/components/ui/select/Select'
import { ShowcaseSection } from '../ShowcasePrimitives'
import { MOCK_SERVICES, type ServiceRow } from './mock-data'
import { PatternFrame } from './PatternFrame'

const columns: TableColumn<ServiceRow>[] = [
  {
    id: 'name',
    header: 'Service',
    accessor: (row) => (
      <div>
        <p className="text-body-strong text-text-primary">{row.name}</p>
        <p className="text-caption text-text-tertiary">{row.category}</p>
      </div>
    ),
  },
  {
    id: 'price',
    header: 'Default price',
    align: 'end',
    sortable: true,
    accessor: (row) => <MoneyDisplay amount={row.defaultPrice} />,
  },
  {
    id: 'branches',
    header: 'Branches',
    align: 'end',
    accessor: (row) => <span className="tabular-nums">{row.branches}</span>,
  },
  {
    id: 'status',
    header: 'Status',
    accessor: (row) => (
      <Badge color={row.status === 'active' ? 'success' : 'neutral'} variant="soft">
        {row.status === 'active' ? 'Active' : 'Inactive'}
      </Badge>
    ),
  },
]

export function ListIndexPattern() {
  const [search, setSearch] = useState('')
  const [category, setCategory] = useState('all')
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(5)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [sortCol, setSortCol] = useState<string | undefined>('price')
  const [sortDir, setSortDir] = useState<'asc' | 'desc' | null>('asc')

  const filtered = useMemo(() => {
    let rows = MOCK_SERVICES
    if (search) {
      const q = search.toLowerCase()
      rows = rows.filter((r) => r.name.toLowerCase().includes(q) || r.category.toLowerCase().includes(q))
    }
    if (category !== 'all') {
      rows = rows.filter((r) => r.category.toLowerCase() === category)
    }
    if (sortCol === 'price' && sortDir) {
      rows = [...rows].sort((a, b) =>
        sortDir === 'asc' ? a.defaultPrice - b.defaultPrice : b.defaultPrice - a.defaultPrice,
      )
    }
    return rows
  }, [search, category, sortCol, sortDir])

  const paged = filtered.slice((page - 1) * pageSize, page * pageSize)

  const handleSort = (col: string) => {
    if (sortCol === col) {
      setSortDir((d) => (d === 'asc' ? 'desc' : d === 'desc' ? null : 'asc'))
    } else {
      setSortCol(col)
      setSortDir('asc')
    }
  }

  return (
    <ShowcaseSection
      id="pattern-list-index"
      title="List / Index"
      componentName="05 §2 List / Index"
      description="Services catalog with toolbar, filters, selectable table, pagination, and bulk actions."
    >
      <PatternFrame minHeight="520px">
        <div className="space-y-4 p-4 sm:p-6">
          <PageHeader
            title="Services"
            description="Organization catalog with per-branch configuration."
            actions={
              <Button variant="primary" size="sm" leadingIcon={<Plus size={16} />}>
                Add service
              </Button>
            }
          />

          <Toolbar
            start={
              <SearchInput
                placeholder="Search services…"
                aria-label="Search services"
                className="w-56"
                value={search}
                onValueChange={setSearch}
                resultCount={filtered.length}
              />
            }
            end={
              <Select
                aria-label="Filter by category"
                value={category}
                onValueChange={setCategory}
                options={[
                  { value: 'all', label: 'All categories' },
                  { value: 'consultation', label: 'Consultation' },
                  { value: 'dental', label: 'Dental' },
                  { value: 'lab', label: 'Lab' },
                  { value: 'imaging', label: 'Imaging' },
                ]}
              />
            }
          />

          {category !== 'all' ? (
            <div className="flex flex-wrap gap-2">
              <Chip removable onRemove={() => setCategory('all')} selected>
                Category: {category}
              </Chip>
            </div>
          ) : null}

          {selected.size > 0 ? (
            <BulkActionBar
              count={selected.size}
              itemLabel="services selected"
              onClear={() => setSelected(new Set())}
              actions={
                <>
                  <Button variant="secondary" size="sm">
                    Set inactive
                  </Button>
                  <Button variant="ghost" size="sm">
                    Export
                  </Button>
                </>
              }
            />
          ) : null}

          <DataTable
            columns={columns}
            data={paged}
            getRowId={(r) => r.id}
            selectable
            selectedIds={selected}
            onSelectionChange={setSelected}
            sortColumn={sortCol}
            sortDirection={sortDir}
            onSort={handleSort}
            aria-label="Services catalog"
          />

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
        </div>
      </PatternFrame>
    </ShowcaseSection>
  )
}
