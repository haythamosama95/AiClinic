import { MetricCard } from '@/components/card/MetricCard'
import { AppChart, chartPalette } from '@/components/chart/Chart'
import { SectionHeader } from '@/components/layout/SectionHeader'
import { MoneyDisplay } from '@/components/money/MoneyDisplay'
import { DataTable, type TableColumn } from '@/components/table/DataTable'
import { Badge } from '@/components/badge'
import { ShowcaseSection } from '../ShowcasePrimitives'
import { MOCK_APPOINTMENTS } from './mock-data'
import { PatternFrame } from './PatternFrame'

type Appt = (typeof MOCK_APPOINTMENTS)[number]

const columns: TableColumn<Appt>[] = [
  { id: 'time', header: 'Time', accessor: (r) => <span className="tabular-nums">{r.time}</span> },
  { id: 'patient', header: 'Patient', accessor: (r) => r.patient },
  { id: 'doctor', header: 'Doctor', accessor: (r) => r.doctor },
  {
    id: 'status',
    header: 'Status',
    accessor: (r) => {
      const color = r.status === 'confirmed' ? 'success' : r.status === 'pending' ? 'warning' : 'danger'
      return <Badge color={color} variant="soft" className="capitalize">{r.status}</Badge>
    },
  },
]

export function DashboardPattern() {
  return (
    <ShowcaseSection
      id="pattern-dashboard"
      title="Dashboard"
      componentName="05 §2 Dashboard / Analytics"
      description="Metric cards, charts grid, and detail table for operational overview."
    >
      <PatternFrame>
        <div className="space-y-8 p-4 sm:p-6">
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <MetricCard
              label="Today's appointments"
              value="24"
              delta={{ value: '12%', direction: 'up', positive: true }}
              caption="vs yesterday"
            />
            <MetricCard
              label="Revenue today"
              value="18,420"
              delta={{ value: '3%', direction: 'down', positive: false }}
              caption="EGP"
            />
            <MetricCard
              label="Patients seen"
              value="19"
              delta={{ value: '5%', direction: 'up', positive: true }}
            />
            <MetricCard
              label="Outstanding"
              value="4,280"
              caption="EGP unpaid"
            />
          </div>

          <div className="grid gap-6 lg:grid-cols-2">
            <div className="rounded-lg border border-border-default bg-surface-default p-4">
              <SectionHeader title="Weekly revenue" />
              <AppChart
                type="bar"
                height={180}
                labels={['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']}
                series={[{ label: 'Revenue', data: [12, 15, 14, 18, 16, 8, 6], color: chartPalette[0] }]}
                aria-label="Weekly revenue chart"
                className="mt-4"
              />
            </div>
            <div className="rounded-lg border border-border-default bg-surface-default p-4">
              <SectionHeader title="Appointments by status" />
              <AppChart
                type="donut"
                height={180}
                series={[
                  { label: 'Confirmed', data: [65], color: chartPalette[2] },
                  { label: 'Pending', data: [20], color: chartPalette[3] },
                  { label: 'Cancelled', data: [15], color: chartPalette[4] },
                ]}
                aria-label="Appointment status breakdown"
                className="mt-4"
              />
            </div>
          </div>

          <div>
            <SectionHeader title="Upcoming appointments" />
            <DataTable
              columns={columns}
              data={MOCK_APPOINTMENTS}
              getRowId={(r) => r.id}
              footer={
                <span className="text-end text-body-sm text-text-secondary">
                  Total expected revenue: <MoneyDisplay amount={2840} emphasis />
                </span>
              }
              aria-label="Upcoming appointments"
              className="mt-4"
            />
          </div>
        </div>
      </PatternFrame>
    </ShowcaseSection>
  )
}
