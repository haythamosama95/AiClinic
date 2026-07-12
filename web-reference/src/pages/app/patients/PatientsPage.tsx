import {
  Calendar,
  Edit,
  ExternalLink,
  Plus,
  SearchX,
  UserX,
} from 'lucide-react'
import { motion } from 'motion/react'
import { useCallback, useMemo, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Avatar } from '@/components/avatar/Avatar'
import { Badge } from '@/components/badge'
import { EmptyState } from '@/components/empty-state/EmptyState'
import { FilterMenuPanel } from '@/components/layout/FilterMenuPanel'
import { ListControlBar } from '@/components/layout/ListControlBar'
import { PageHeader } from '@/components/layout/PageHeader'
import type { MenuEntry } from '@/components/navigation/Menu'
import { Pagination } from '@/components/navigation/Pagination'
import { DataTable, type TableColumn } from '@/components/table/DataTable'
import {
  formatDate,
  patientFullName,
  patientStatusColor,
  type Patient,
} from '@/data/patients'
import { AddPatientDialog } from './AddPatientDialog'
import {
  ALL_PATIENTS,
  DEFAULT_PATIENT_CONTROLS,
  filterAndSortPatients,
  PATIENT_SORT_OPTIONS,
  STATUS_OPTIONS,
  type PatientListControls,
  type PatientStatusFilter,
} from './patient-list-controls'

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
  const [controls, setControls] = useState<PatientListControls>(DEFAULT_PATIENT_CONTROLS)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [addPatientDialogOpen, setAddPatientDialogOpen] = useState(false)

  const filtered = useMemo(
    () => filterAndSortPatients(ALL_PATIENTS, controls),
    [controls],
  )

  const paged = filtered.slice((page - 1) * pageSize, page * pageSize)

  const activeFilters = useMemo(() => {
    const chips: { id: string; label: string; onRemove: () => void }[] = []
    if (controls.status !== 'all') {
      chips.push({
        id: 'status',
        label: controls.status.charAt(0).toUpperCase() + controls.status.slice(1),
        onRemove: () => {
          setControls((c) => ({ ...c, status: 'all' }))
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
  }, [controls.search, controls.status])

  const filterActiveCount = controls.status !== 'all' ? 1 : 0
  const clearFilters = () => {
    setControls((c) => ({ ...c, status: 'all' }))
    setPage(1)
  }
  const clearAll = () => {
    setControls(DEFAULT_PATIENT_CONTROLS)
    setPage(1)
  }

  const hasPatients = ALL_PATIENTS.length > 0
  const hasResults = filtered.length > 0
  const isFiltered =
    controls.search !== '' ||
    controls.status !== 'all' ||
    controls.sort !== DEFAULT_PATIENT_CONTROLS.sort

  const rowContextMenu = useCallback(
    (patient: Patient): MenuEntry[] => [
      {
        id: 'open',
        label: 'Open patient details',
        icon: <ExternalLink size={16} strokeWidth={1.5} />,
        onSelect: () => onNavigate(`patients/${patient.id}`),
      },
      {
        id: 'book',
        label: 'Book appointment',
        icon: <Calendar size={16} strokeWidth={1.5} />,
        onSelect: () => onNavigate('appointments'),
      },
      {
        id: 'edit',
        label: 'Edit patient',
        icon: <Edit size={16} strokeWidth={1.5} />,
        onSelect: () => onNavigate(`patients/${patient.id}`),
      },
      { type: 'separator' },
      {
        id: 'deactivate',
        label: 'Deactivate',
        icon: <UserX size={16} strokeWidth={1.5} />,
        destructive: true,
        disabled: patient.status !== 'active',
        disabledReason: patient.status !== 'active' ? 'Patient is already inactive' : undefined,
        onSelect: () => undefined,
      },
    ],
    [onNavigate],
  )

  return (
    <motion.div
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.22 }}
      className="space-y-6"
    >
      <PageHeader
        title="Patients"
        description="Manage patient records, profiles, and medical history."
        actions={
          <Button
            variant="primary"
            size="sm"
            leadingIcon={<Plus size={16} />}
            onClick={() => setAddPatientDialogOpen(true)}
          >
            Add patient
          </Button>
        }
      />

      {hasPatients ? (
        <ListControlBar
          searchPlaceholder="Search patients by name, MRN, email, or phone…"
          searchAriaLabel="Search patients"
          search={controls.search}
          onSearchChange={(search) => {
            setControls((c) => ({ ...c, search }))
            setPage(1)
          }}
          sortValue={controls.sort}
          defaultSortValue={DEFAULT_PATIENT_CONTROLS.sort}
          sortOptions={[...PATIENT_SORT_OPTIONS]}
          onSortChange={(sort) => {
            setControls((c) => ({ ...c, sort: sort as PatientListControls['sort'] }))
            setPage(1)
          }}
          sortAriaLabel="Sort patients"
          filterActiveCount={filterActiveCount}
          onClearFilters={filterActiveCount > 0 ? clearFilters : undefined}
          filterMenu={
            <FilterMenuPanel
              sections={[
                {
                  id: 'status',
                  label: 'Status',
                  value: controls.status,
                  options: [...STATUS_OPTIONS],
                  onChange: (status) => {
                    setControls((c) => ({
                      ...c,
                      status: status as PatientStatusFilter,
                    }))
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

      {!hasPatients ? (
        <EmptyState
          variant="first-run"
          title="No patients yet"
          description="Add your first patient to start building records."
          action={{
            label: 'Add patient',
            onClick: () => setAddPatientDialogOpen(true),
          }}
        />
      ) : !hasResults ? (
        <div className="rounded-2xl border border-border-subtle bg-surface-default px-6 py-14 text-center shadow-elevation-1">
          <SearchX size={32} className="mx-auto text-icon-muted" strokeWidth={1.25} />
          <p className="mt-4 text-body-strong text-text-primary">No patients match</p>
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
          onRowClick={(row) => onNavigate(`patients/${row.id}`)}
          rowContextMenu={rowContextMenu}
          animateRows
          aria-label="Patients"
        />
      )}

      <AddPatientDialog
        open={addPatientDialogOpen}
        onOpenChange={setAddPatientDialogOpen}
        onSuccess={(patientId) => onNavigate(`patients/${patientId}`)}
      />

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
