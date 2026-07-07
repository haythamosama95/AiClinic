import { Plus } from 'lucide-react'
import { useMemo, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Avatar } from '@/components/avatar/Avatar'
import { Badge } from '@/components/badge'
import { Chip } from '@/components/chip'
import { EmptyState } from '@/components/empty-state/EmptyState'
import { PageHeader } from '@/components/layout/PageHeader'
import { Toolbar } from '@/components/layout/Toolbar'
import { Pagination } from '@/components/navigation/Pagination'
import { DataTable, type TableColumn } from '@/components/table/DataTable'
import { SearchInput } from '@/components/ui/search-input/SearchInput'
import { Select } from '@/components/ui/select/Select'
import {
  formatDate,
  MOCK_PATIENTS,
  patientFullName,
  patientStatusColor,
  type Patient,
  type PatientStatus,
} from '@/data/patients'

export type PatientsPageProps = {
  onNavigate: (route: string) => void
}

const columns: TableColumn<Patient>[] = [
  {
    id: 'name',
    header: 'Patient',
    accessor: (row) => (
      <div className="flex items-center gap-3">
        <Avatar name={patientFullName(row)} size="sm" />
        <div className="min-w-0">
          <p className="text-body-strong text-text-primary">{patientFullName(row)}</p>
          <p className="text-caption tabular-nums text-text-tertiary">{row.mrn}</p>
        </div>
      </div>
    ),
  },
  {
    id: 'email',
    header: 'Email',
    accessor: (row) => <span className="text-text-secondary">{row.email}</span>,
  },
  {
    id: 'phone',
    header: 'Phone',
    accessor: (row) => <span className="tabular-nums">{row.phone}</span>,
  },
  {
    id: 'dob',
    header: 'DOB',
    accessor: (row) => <span className="tabular-nums">{formatDate(row.dateOfBirth)}</span>,
  },
  {
    id: 'status',
    header: 'Status',
    accessor: (row) => (
      <Badge color={patientStatusColor(row.status)} variant="soft">
        {row.status.charAt(0).toUpperCase() + row.status.slice(1)}
      </Badge>
    ),
  },
  {
    id: 'lastVisit',
    header: 'Last visit',
    align: 'end',
    accessor: (row) => (
      <span className="tabular-nums text-text-secondary">
        {row.lastVisit ? formatDate(row.lastVisit) : '—'}
      </span>
    ),
  },
]

export function PatientsPage({ onNavigate }: PatientsPageProps) {
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState<'all' | PatientStatus>('all')
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)

  const filtered = useMemo(() => {
    let rows = MOCK_PATIENTS
    if (search) {
      const q = search.toLowerCase()
      rows = rows.filter(
        (p) =>
          patientFullName(p).toLowerCase().includes(q) ||
          p.mrn.toLowerCase().includes(q) ||
          p.email.toLowerCase().includes(q) ||
          p.phone.includes(q),
      )
    }
    if (status !== 'all') {
      rows = rows.filter((p) => p.status === status)
    }
    return rows
  }, [search, status])

  const paged = filtered.slice((page - 1) * pageSize, page * pageSize)

  return (
    <div className="space-y-6">
      <PageHeader
        title="Patients"
        description="Manage patient records, profiles, and medical history."
        actions={
          <Button variant="primary" size="sm" leadingIcon={<Plus size={16} />}>
            Add patient
          </Button>
        }
      />

      <Toolbar
        start={
          <SearchInput
            placeholder="Search patients…"
            aria-label="Search patients"
            className="w-56"
            value={search}
            onValueChange={(v) => {
              setSearch(v)
              setPage(1)
            }}
            resultCount={filtered.length}
          />
        }
        end={
          <Select
            aria-label="Filter by status"
            value={status}
            onValueChange={(v) => {
              setStatus(v as 'all' | PatientStatus)
              setPage(1)
            }}
            options={[
              { value: 'all', label: 'All statuses' },
              { value: 'active', label: 'Active' },
              { value: 'inactive', label: 'Inactive' },
              { value: 'archived', label: 'Archived' },
            ]}
          />
        }
      />

      {status !== 'all' ? (
        <div className="flex flex-wrap gap-2">
          <Chip
            removable
            onRemove={() => {
              setStatus('all')
              setPage(1)
            }}
            selected
          >
            Status: {status.charAt(0).toUpperCase() + status.slice(1)}
          </Chip>
        </div>
      ) : null}

      <DataTable
        columns={columns}
        data={paged}
        getRowId={(r) => r.id}
        onRowClick={(row) => onNavigate(`patients/${row.id}`)}
        emptyState={
          <EmptyState
            variant="no-results"
            title="No patients found"
            description="Try adjusting your search or filter criteria."
            action={
              search || status !== 'all'
                ? {
                  label: 'Clear filters',
                  onClick: () => {
                    setSearch('')
                    setStatus('all')
                    setPage(1)
                  },
                }
                : undefined
            }
          />
        }
        aria-label="Patients"
      />

      {filtered.length > 0 ? (
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
    </div>
  )
}
