import { useState } from 'react'
import {
  AppointmentCard,
  Card,
  InvoiceCard,
  MetricCard,
  PatientCard,
  ServiceCard,
} from '@/components/card'
import { AppChart, ChartSparkline } from '@/components/chart'
import { CodeBlock } from '@/components/code-block'
import { DescriptionList } from '@/components/description-list'
import { List, ListItem } from '@/components/list'
import { Avatar } from '@/components/avatar'
import { Badge } from '@/components/badge'
import { Calendar } from '@/components/calendar'
import { BulkActionBar } from '@/components/layout/BulkActionBar'
import { EmptyState } from '@/components/empty-state'
import { ErrorState } from '@/components/error-state'
import { ResizablePanels } from '@/components/resizable'
import { ScrollArea } from '@/components/scroll-area'
import { DataTable } from '@/components/table'
import { Timeline } from '@/components/timeline'
import { MoneyDisplay } from '@/components/money'
import {
  ShowcaseDemo,
  ShowcaseDemoGrid,
  ShowcaseSection,
} from '../../ShowcasePrimitives'

type Patient = { id: string; name: string; phone: string; balance: number }

const MOCK_PATIENTS: Patient[] = [
  { id: '1', name: 'Layla Hassan', phone: '+20 100 234 5678', balance: 1250 },
  { id: '2', name: 'Omar Farouk', phone: '+20 101 345 6789', balance: 0 },
  { id: '3', name: 'Nadia El-Sayed', phone: '+20 102 456 7890', balance: -320 },
]

const MOCK_EVENTS = [
  {
    id: 'e1',
    title: 'Consultation',
    start: new Date(2026, 6, 4, 9, 0),
    end: new Date(2026, 6, 4, 9, 30),
    patient: 'Layla Hassan',
    doctor: 'Dr. Ahmed',
  },
  {
    id: 'e2',
    title: 'Follow-up',
    start: new Date(2026, 6, 4, 10, 0),
    end: new Date(2026, 6, 4, 10, 30),
    patient: 'Omar Farouk',
    doctor: 'Dr. Sara',
    conflict: true,
  },
]

export function CardShowcase() {
  return (
    <ShowcaseSection id="card" title="Card" componentName="Card" description="Grouped surfaces with flat, raised, interactive, and AI variants.">
      <ShowcaseDemoGrid columns={2}>
        {(['flat', 'raised', 'interactive', 'ai'] as const).map((variant) => (
          <ShowcaseDemo key={variant} label={variant} propsHint={`variant="${variant}"`}>
            <Card variant={variant} className="w-full p-4">
              <p className="text-body-strong text-text-primary">Card title</p>
              <p className="mt-1 text-body-sm text-text-secondary">Supporting content for the {variant} variant.</p>
            </Card>
          </ShowcaseDemo>
        ))}
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}

export function MetricCardShowcase() {
  return (
    <ShowcaseSection id="metric-card" title="Metric card" componentName="MetricCard">
      <ShowcaseDemoGrid columns={2}>
        <MetricCard
          label="Revenue today"
          value="12,450.00"
          delta={{ value: '+8.2%', direction: 'up', positive: true }}
          caption="vs. yesterday"
          sparkline={<ChartSparkline data={[4, 6, 5, 8, 7, 9, 12]} color="var(--action-primary)" />}
        />
        <MetricCard
          label="Outstanding"
          value="3,200.00"
          delta={{ value: '−2.1%', direction: 'down', positive: true }}
        />
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}

export function EntityCardsShowcase() {
  return (
    <ShowcaseSection id="entity-cards" title="Entity cards" componentName="PatientCard / AppointmentCard / …">
      <ShowcaseDemoGrid columns={2}>
        <PatientCard name="Layla Hassan" mrn="10482" phone="+20 100 234 5678" tags={['Insurance', 'VIP']} />
        <AppointmentCard time="9:30 AM" patient="Omar Farouk" doctor="Dr. Sara Mahmoud" status="confirmed" branch="Downtown" />
        <InvoiceCard number="INV-2026-0842" patient="Nadia El-Sayed" amount={1850} status="pending" date="Jul 2, 2026" />
        <ServiceCard name="General consultation" price={350} globalStatus="active" branchSummary="Available at 3 of 4 branches" />
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}

export function DataTableShowcase() {
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [sortCol, setSortCol] = useState('name')
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc')
  const [demo, setDemo] = useState<'default' | 'loading' | 'empty' | 'error'>('default')

  const data = demo === 'default' ? MOCK_PATIENTS : []

  return (
    <ShowcaseSection id="data-table" title="Table / Data grid" componentName="DataTable">
      <div className="mb-4 flex flex-wrap gap-2">
        {(['default', 'loading', 'empty', 'error'] as const).map((s) => (
          <button
            key={s}
            type="button"
            onClick={() => setDemo(s)}
            className="focus-ring rounded-md border border-border-default px-3 py-1.5 text-body-sm capitalize hover:bg-surface-hover"
          >
            {s}
          </button>
        ))}
      </div>
      {selected.size > 0 ? (
        <BulkActionBar
          count={selected.size}
          itemLabel="patients selected"
          onClear={() => setSelected(new Set())}
          actions={<button type="button" className="text-body-sm text-text-link">Export</button>}
          className="mb-4"
        />
      ) : null}
      <DataTable
        columns={[
          { id: 'name', header: 'Patient', accessor: (r) => r.name, sortable: true },
          { id: 'phone', header: 'Phone', accessor: (r) => r.phone, align: 'end' },
          {
            id: 'balance',
            header: 'Balance',
            accessor: (r) => <MoneyDisplay amount={r.balance} negative={r.balance < 0} />,
            align: 'end',
            sortable: true,
          },
          {
            id: 'status',
            header: 'Status',
            accessor: () => <Badge color="success" variant="soft">Active</Badge>,
          },
        ]}
        data={data}
        density="default"
        zebra
        selectable
        selectedIds={selected}
        onSelectionChange={setSelected}
        getRowId={(r) => r.id}
        sortColumn={sortCol}
        sortDirection={sortDir}
        onSort={(col) => {
          if (sortCol === col) setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'))
          else { setSortCol(col); setSortDir('asc') }
        }}
        loading={demo === 'loading'}
        emptyState={<EmptyState variant="no-results" />}
        errorState={<ErrorState message="Could not load patients. Check your connection." onRetry={() => setDemo('default')} />}
        footer={<span className="text-body-sm text-text-secondary">Total balance: <MoneyDisplay amount={1250} emphasis /></span>}
      />
    </ShowcaseSection>
  )
}

export function ListShowcase() {
  return (
    <ShowcaseSection id="list" title="List" componentName="List / ListItem">
      <List aria-label="Recent patients">
        {MOCK_PATIENTS.map((p) => (
          <ListItem
            key={p.id}
            leading={<Avatar name={p.name} size="sm" />}
            primary={p.name}
            secondary={p.phone}
            trailing={<MoneyDisplay amount={p.balance} />}
          />
        ))}
      </List>
    </ShowcaseSection>
  )
}

export function DescriptionListShowcase() {
  return (
    <ShowcaseSection id="description-list" title="Description list" componentName="DescriptionList">
      <DescriptionList
        items={[
          { label: 'MRN', value: '10482', tabular: true },
          { label: 'Date of birth', value: 'Mar 14, 1988' },
          { label: 'Phone', value: '+20 100 234 5678', tabular: true },
          { label: 'Insurance', value: 'AXA Egypt' },
        ]}
      />
    </ShowcaseSection>
  )
}

export function TimelineShowcase() {
  return (
    <ShowcaseSection id="timeline" title="Timeline" componentName="Timeline">
      <Timeline
        events={[
          { id: '1', group: 'Jul 4, 2026', timestamp: '10:30 AM', title: 'Visit completed', description: 'General consultation with Dr. Ahmed' },
          { id: '2', group: 'Jul 4, 2026', timestamp: '10:15 AM', title: 'Vitals recorded', description: 'BP 120/80, temp 37.1°C' },
          { id: '3', group: 'Jul 2, 2026', timestamp: '2:00 PM', title: 'Invoice paid', description: 'EGP 850.00 via card' },
        ]}
      />
    </ShowcaseSection>
  )
}

export function CalendarShowcase() {
  return (
    <ShowcaseSection id="calendar" title="Calendar" componentName="Calendar">
      <Calendar events={MOCK_EVENTS} />
    </ShowcaseSection>
  )
}

export function ChartShowcase() {
  const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']
  const series = [{ label: 'Appointments', data: [12, 18, 15, 22, 19] }]
  return (
    <ShowcaseSection id="chart" title="Chart primitives" componentName="AppChart">
      <ShowcaseDemoGrid columns={2}>
        <ShowcaseDemo label="Line" propsHint='type="line"'>
          <AppChart type="line" series={series} labels={labels} aria-label="Weekly appointments" />
        </ShowcaseDemo>
        <ShowcaseDemo label="Bar" propsHint='type="bar"'>
          <AppChart type="bar" series={series} aria-label="Weekly appointments bar" />
        </ShowcaseDemo>
        <ShowcaseDemo label="Stacked bar" propsHint='type="stacked-bar"'>
          <AppChart
            type="stacked-bar"
            series={[
              { label: 'New', data: [5, 8, 6, 10, 7] },
              { label: 'Follow-up', data: [7, 10, 9, 12, 12] },
            ]}
            aria-label="Appointment types"
          />
        </ShowcaseDemo>
        <ShowcaseDemo label="Donut" propsHint='type="donut"'>
          <AppChart
            type="donut"
            series={[{ label: 'Services', data: [40, 30, 20, 10] }]}
            aria-label="Revenue by service"
          />
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}

export function MoneyDisplayShowcase() {
  return (
    <ShowcaseSection id="money-display" title="Money display" componentName="MoneyDisplay">
      <ShowcaseDemo label="Variants">
        <MoneyDisplay amount={1250.5} />
        <MoneyDisplay amount={1250.5} emphasis />
        <MoneyDisplay amount={-320} negative />
      </ShowcaseDemo>
    </ShowcaseSection>
  )
}

export function CodeBlockShowcase() {
  return (
    <ShowcaseSection id="code-block" title="Code block" componentName="CodeBlock">
      <CodeBlock language="json" code={`{\n  "patientId": "10482",\n  "mrn": "MRN-10482"\n}`} />
    </ShowcaseSection>
  )
}

export function ScrollAreaShowcase() {
  return (
    <ShowcaseSection id="scroll-area" title="Scroll area" componentName="ScrollArea">
      <ScrollArea maxHeight={160} className="rounded-lg border border-border-default">
        <div className="space-y-2 p-4">
          {Array.from({ length: 12 }).map((_, i) => (
            <p key={i} className="text-body-sm text-text-secondary">Scrollable row {i + 1}</p>
          ))}
        </div>
      </ScrollArea>
    </ShowcaseSection>
  )
}

export function ResizablePanelsShowcase() {
  return (
    <ShowcaseSection id="resizable-panels" title="Resizable panels" componentName="ResizablePanels">
      <ResizablePanels
        start={<div className="p-4 text-body-sm text-text-secondary">Master list pane</div>}
        end={<div className="p-4 text-body-sm text-text-secondary">Detail pane — drag the divider or use arrow keys</div>}
      />
    </ShowcaseSection>
  )
}
