import { useState } from 'react'
import { Badge } from '@/components/badge'
import { Drawer } from '@/components/drawer/Drawer'
import { DescriptionList } from '@/components/description-list/DescriptionList'
import { ResizablePanels } from '@/components/resizable/ResizablePanels'
import { DataTable, type TableColumn } from '@/components/table/DataTable'
import { SearchInput } from '@/components/ui/search-input/SearchInput'
import { ShowcaseSection } from '../ShowcasePrimitives'
import { MOCK_PATIENTS, type PatientRow } from './mock-data'
import { PatternFrame } from './PatternFrame'

const columns: TableColumn<PatientRow>[] = [
  {
    id: 'name',
    header: 'Patient',
    accessor: (row) => (
      <div>
        <p className="text-body-strong text-text-primary">{row.name}</p>
        <p className="text-caption tabular-nums text-text-tertiary">{row.mrn}</p>
      </div>
    ),
  },
  {
    id: 'phone',
    header: 'Phone',
    accessor: (row) => <span className="tabular-nums">{row.phone}</span>,
  },
  {
    id: 'lastVisit',
    header: 'Last visit',
    align: 'end',
    accessor: (row) => <span className="tabular-nums">{row.lastVisit}</span>,
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

export function MasterDetailPattern() {
  const [search, setSearch] = useState('')
  const [selected, setSelected] = useState<PatientRow | null>(MOCK_PATIENTS[0])
  const [drawerOpen, setDrawerOpen] = useState(true)

  const filtered = MOCK_PATIENTS.filter((p) =>
    !search || p.name.toLowerCase().includes(search.toLowerCase()) || p.mrn.toLowerCase().includes(search.toLowerCase()),
  )

  return (
    <ShowcaseSection
      id="pattern-master-detail"
      title="Master–Detail"
      componentName="05 §2 Master–Detail"
      description="Patient list with inline-start panel and detail drawer on selection."
    >
      <PatternFrame minHeight="420px">
        <ResizablePanels
          defaultStartPercent={45}
          start={
            <div className="flex h-full flex-col gap-3 border-e border-border-subtle p-4">
              <SearchInput
                placeholder="Search patients…"
                aria-label="Search patients"
                value={search}
                onValueChange={setSearch}
              />
              <DataTable
                columns={columns}
                data={filtered}
                getRowId={(r) => r.id}
                onRowClick={(row) => {
                  setSelected(row)
                  setDrawerOpen(true)
                }}
                aria-label="Patients"
              />
            </div>
          }
          end={
            <div className="flex h-full items-center justify-center p-6 text-body text-text-secondary">
              {selected ? (
                <p>
                  Selected: <span className="text-body-strong text-text-primary">{selected.name}</span>
                  {' — '}detail opens in drawer
                </p>
              ) : (
                <p>Select a patient to view details</p>
              )}
            </div>
          }
        />
      </PatternFrame>

      <Drawer
        open={drawerOpen && !!selected}
        onOpenChange={setDrawerOpen}
        title={selected?.name ?? 'Patient'}
        description={selected?.mrn}
        size="md"
      >
        {selected ? (
          <DescriptionList
            items={[
              { label: 'Phone', value: selected.phone, tabular: true },
              { label: 'Last visit', value: selected.lastVisit, tabular: true },
              {
                label: 'Status',
                value: (
                  <Badge color={selected.status === 'active' ? 'success' : 'neutral'} variant="soft">
                    {selected.status === 'active' ? 'Active' : 'Inactive'}
                  </Badge>
                ),
              },
              { label: 'Primary branch', value: 'Downtown' },
              { label: 'Allergies', value: 'Penicillin' },
              { label: 'Insurance', value: 'Not on file' },
            ]}
          />
        ) : null}
      </Drawer>
    </ShowcaseSection>
  )
}
