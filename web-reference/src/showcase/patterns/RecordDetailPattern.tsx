import { useState } from 'react'
import { Pencil } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { Badge } from '@/components/badge'
import { DescriptionList } from '@/components/description-list/DescriptionList'
import { PageHeader } from '@/components/layout/PageHeader'
import { MoneyDisplay } from '@/components/money/MoneyDisplay'
import { Tabs } from '@/components/navigation/Tabs'
import { Timeline } from '@/components/timeline/Timeline'
import { DataTable, type TableColumn } from '@/components/table/DataTable'
import { ShowcaseSection } from '../ShowcasePrimitives'
import { MOCK_INVOICES } from './mock-data'
import { PatternFrame } from './PatternFrame'

type Invoice = (typeof MOCK_INVOICES)[number]

const invoiceColumns: TableColumn<Invoice>[] = [
  { id: 'date', header: 'Date', accessor: (r) => <span className="tabular-nums">{r.date}</span> },
  { id: 'amount', header: 'Amount', align: 'end', accessor: (r) => <MoneyDisplay amount={r.amount} /> },
  {
    id: 'status',
    header: 'Status',
    accessor: (r) => {
      const color = r.status === 'paid' ? 'success' : r.status === 'partial' ? 'warning' : 'danger'
      const label = r.status === 'paid' ? 'Paid' : r.status === 'partial' ? 'Partially paid' : 'Unpaid'
      return <Badge color={color} variant="soft">{label}</Badge>
    },
  },
]

const timelineEvents = [
  { id: 't1', timestamp: '04 Jul 2026, 2:30 PM', title: 'Invoice created', description: 'INV-2026-0842 · 420.00 EGP', group: 'Today' },
  { id: 't2', timestamp: '03 Jul 2026, 11:00 AM', title: 'Visit completed', description: 'General consultation with Dr. Ahmed', group: 'Yesterday' },
  { id: 't3', timestamp: '28 Jun 2026, 9:15 AM', title: 'Appointment confirmed', description: 'Follow-up visit scheduled', group: 'Last week' },
]

export function RecordDetailPattern() {
  const [tab, setTab] = useState('overview')

  return (
    <ShowcaseSection
      id="pattern-record-detail"
      title="Record Detail"
      componentName="05 §2 Record Detail"
      description="Patient record with tabs, description lists, related table, and timeline."
    >
      <PatternFrame>
        <div className="space-y-6 p-4 sm:p-6">
          <PageHeader
            title="Layla Hassan"
            description="MRN-10482 · Downtown branch"
            actions={
              <>
                <Badge color="success" variant="soft">Active</Badge>
                <Button variant="secondary" size="sm" leadingIcon={<Pencil size={14} />}>
                  Edit patient
                </Button>
              </>
            }
            tabs={
              <Tabs
                items={[
                  { id: 'overview', label: 'Overview' },
                  { id: 'visits', label: 'Visits' },
                  { id: 'billing', label: 'Billing' },
                ]}
                value={tab}
                onChange={setTab}
                aria-label="Patient sections"
              />
            }
          />

          {tab === 'overview' ? (
            <DescriptionList
              items={[
                { label: 'Phone', value: '+20 100 234 5678', tabular: true },
                { label: 'Date of birth', value: '12 Mar 1988', tabular: true },
                { label: 'Allergies', value: 'Penicillin' },
                { label: 'Insurance', value: 'Not on file' },
                { label: 'Primary doctor', value: 'Dr. Ahmed Hassan' },
                { label: 'Last visit', value: '28 Jun 2026', tabular: true },
              ]}
            />
          ) : null}

          {tab === 'billing' ? (
            <div className="space-y-6">
              <DataTable
                columns={invoiceColumns}
                data={MOCK_INVOICES}
                getRowId={(r) => r.id}
                aria-label="Patient invoices"
              />
            </div>
          ) : null}

          {tab === 'visits' ? (
            <Timeline events={timelineEvents} />
          ) : null}
        </div>
      </PatternFrame>
    </ShowcaseSection>
  )
}
