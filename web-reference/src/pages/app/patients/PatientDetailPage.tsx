import { ArrowLeft, Mail, MapPin, Phone, Sparkles } from 'lucide-react'
import { useMemo, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { Avatar } from '@/components/avatar/Avatar'
import { Badge } from '@/components/badge'
import { Card } from '@/components/card/Card'
import { MetricCard } from '@/components/card/MetricCard'
import { DescriptionList } from '@/components/description-list/DescriptionList'
import { EmptyState } from '@/components/empty-state/EmptyState'
import { PageHeader } from '@/components/layout/PageHeader'
import { MoneyDisplay } from '@/components/money/MoneyDisplay'
import { Breadcrumb } from '@/components/navigation/Breadcrumb'
import { Tabs } from '@/components/navigation/Tabs'
import { Skeleton } from '@/components/skeleton/Skeleton'
import { DataTable, type TableColumn } from '@/components/table/DataTable'
import { Timeline } from '@/components/timeline/Timeline'
import {
  formatDate,
  getInvoicesForPatient,
  getPatientById,
  invoiceStatusColor,
  patientFullName,
  patientStatusColor,
  type Diagnosis,
  type PatientInvoice,
} from '@/data/patients'

export type PatientDetailPageProps = {
  patientId: string
  onNavigate: (route: string) => void
}

const diagnosisColumns: TableColumn<Diagnosis>[] = [
  {
    id: 'code',
    header: 'Code',
    accessor: (d) => <span className="font-mono text-caption">{d.code}</span>,
  },
  { id: 'name', header: 'Diagnosis', accessor: (d) => d.name },
  {
    id: 'date',
    header: 'Date',
    accessor: (d) => <span className="tabular-nums">{formatDate(d.date)}</span>,
  },
  {
    id: 'status',
    header: 'Status',
    accessor: (d) => (
      <Badge color={d.status === 'active' ? 'info' : 'neutral'} variant="soft">
        {d.status.charAt(0).toUpperCase() + d.status.slice(1)}
      </Badge>
    ),
  },
  {
    id: 'provider',
    header: 'Provider',
    accessor: (d) => <span className="text-text-secondary">{d.provider}</span>,
  },
]

const invoiceColumns: TableColumn<PatientInvoice>[] = [
  { id: 'number', header: 'Invoice', accessor: (inv) => inv.number },
  {
    id: 'date',
    header: 'Date',
    accessor: (inv) => <span className="tabular-nums">{formatDate(inv.date)}</span>,
  },
  {
    id: 'status',
    header: 'Status',
    accessor: (inv) => (
      <Badge color={invoiceStatusColor(inv.status)} variant="soft">
        {inv.status.charAt(0).toUpperCase() + inv.status.slice(1)}
      </Badge>
    ),
  },
  {
    id: 'total',
    header: 'Amount',
    align: 'end',
    accessor: (inv) => <MoneyDisplay amount={inv.total} />,
  },
]

const TAB_ITEMS = [
  { id: 'overview', label: 'Overview' },
  { id: 'history', label: 'Medical history' },
  { id: 'diagnoses', label: 'Diagnoses' },
  { id: 'allergies', label: 'Allergies' },
  { id: 'visits', label: 'Visits' },
  { id: 'documents', label: 'Documents' },
  { id: 'billing', label: 'Billing' },
]

export function PatientDetailPage({ patientId, onNavigate }: PatientDetailPageProps) {
  const [tab, setTab] = useState('overview')
  const patient = getPatientById(patientId)
  const invoices = useMemo(
    () => (patient ? getInvoicesForPatient(patient.id) : []),
    [patient],
  )

  if (!patient) {
    return (
      <div className="space-y-6">
        <PageHeader
          title="Patient not found"
          breadcrumb={
            <Breadcrumb
              items={[
                { label: 'Patients', onClick: () => onNavigate('patients') },
                { label: 'Not found' },
              ]}
            />
          }
        />
        <EmptyState
          variant="error"
          title="Patient not found"
          description="The patient record you requested does not exist or has been removed."
          action={{ label: 'Back to patients', onClick: () => onNavigate('patients') }}
        />
      </div>
    )
  }

  const name = patientFullName(patient)
  const timelineEvents = patient.diagnoses.map((d) => ({
    id: d.id,
    timestamp: formatDate(d.date),
    title: `${d.name} (${d.code})`,
    description: `${d.provider} · ${d.status}`,
    group: d.status === 'active' ? 'Active conditions' : 'Resolved',
  }))

  return (
    <div className="space-y-6">
      <PageHeader
        breadcrumb={
          <Breadcrumb
            items={[
              { label: 'Patients', onClick: () => onNavigate('patients') },
              { label: name },
            ]}
          />
        }
        title={name}
        description={`${patient.mrn} · ${patient.gender} · DOB ${formatDate(patient.dateOfBirth)}`}
        actions={
          <>
            <Badge color={patientStatusColor(patient.status)} variant="soft">
              {patient.status.charAt(0).toUpperCase() + patient.status.slice(1)}
            </Badge>
            <Button
              variant="ghost"
              size="sm"
              leadingIcon={<ArrowLeft size={14} />}
              onClick={() => onNavigate('patients')}
            >
              Back
            </Button>
          </>
        }
        tabs={
          <Tabs
            items={TAB_ITEMS}
            value={tab}
            onChange={setTab}
            aria-label="Patient sections"
          />
        }
      />

      <div className="flex flex-col gap-6 lg:flex-row">
        <Card className="flex-1" padding="lg">
          <div className="flex items-start gap-4">
            <Avatar name={name} size="xl" />
            <div className="min-w-0 flex-1 space-y-3">
              <div className="flex flex-wrap items-center gap-3">
                <h2 className="text-h2 text-text-primary">{name}</h2>
                <Badge color={patientStatusColor(patient.status)} variant="soft">
                  {patient.status.charAt(0).toUpperCase() + patient.status.slice(1)}
                </Badge>
              </div>
              <p className="text-body-sm text-text-secondary">
                {patient.mrn} · {patient.gender} · DOB {formatDate(patient.dateOfBirth)}
              </p>
              <div className="flex flex-wrap gap-x-4 gap-y-2 text-body-sm text-text-secondary">
                <span className="inline-flex items-center gap-1.5">
                  <Phone size={14} className="text-icon-muted" aria-hidden />
                  <span className="tabular-nums">{patient.phone}</span>
                </span>
                <span className="inline-flex items-center gap-1.5">
                  <Mail size={14} className="text-icon-muted" aria-hidden />
                  {patient.email}
                </span>
                <span className="inline-flex items-center gap-1.5">
                  <MapPin size={14} className="text-icon-muted" aria-hidden />
                  {patient.address}
                </span>
              </div>
            </div>
          </div>
        </Card>

        {patient.aiSummary ? (
          <Card variant="ai" className="lg:w-80" padding="lg">
            <div className="space-y-3">
              <div className="flex items-center gap-2">
                <Sparkles size={16} className="text-text-ai" aria-hidden />
                <h3 className="text-body-strong text-text-primary">AI summary</h3>
              </div>
              <p className="text-body-sm text-text-secondary">{patient.aiSummary}</p>
            </div>
          </Card>
        ) : null}
      </div>

      {tab === 'overview' ? (
        <div className="space-y-6">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <MetricCard label="Blood type" value={patient.bloodType ?? '—'} />
            <MetricCard label="Insurance" value={patient.insuranceProvider ?? '—'} />
            <MetricCard
              label="Last visit"
              value={patient.lastVisit ? formatDate(patient.lastVisit) : '—'}
            />
            <MetricCard
              label="Next appointment"
              value={patient.nextAppointment ? formatDate(patient.nextAppointment) : '—'}
            />
          </div>
          <Card header={<span className="text-body-strong text-text-primary">Contact & details</span>}>
            <DescriptionList
              items={[
                { label: 'Phone', value: patient.phone, tabular: true },
                { label: 'Email', value: patient.email },
                { label: 'Address', value: patient.address },
                { label: 'Insurance ID', value: patient.insuranceId ?? '—', tabular: true },
                { label: 'Date of birth', value: formatDate(patient.dateOfBirth), tabular: true },
                {
                  label: 'Allergies',
                  value:
                    patient.allergies.length > 0 ? (
                      <div className="flex flex-wrap gap-1.5">
                        {patient.allergies.map((a) => (
                          <Badge key={a} color="danger" variant="soft" size="sm">
                            {a}
                          </Badge>
                        ))}
                      </div>
                    ) : (
                      'None recorded'
                    ),
                },
              ]}
            />
          </Card>
        </div>
      ) : null}

      {tab === 'history' ? (
        <Card padding="lg">
          {timelineEvents.length > 0 ? (
            <Timeline events={timelineEvents} />
          ) : (
            <p className="text-body text-text-secondary">No medical history recorded.</p>
          )}
        </Card>
      ) : null}

      {tab === 'diagnoses' ? (
        <DataTable
          columns={diagnosisColumns}
          data={patient.diagnoses}
          getRowId={(d) => d.id}
          aria-label="Patient diagnoses"
          emptyState={
            <EmptyState variant="first-run" title="No diagnoses" description="No diagnoses on file for this patient." />
          }
        />
      ) : null}

      {tab === 'allergies' ? (
        <Card padding="lg">
          {patient.allergies.length === 0 ? (
            <p className="text-body text-text-secondary">No known allergies.</p>
          ) : (
            <div className="flex flex-wrap gap-2">
              {patient.allergies.map((a) => (
                <Badge key={a} color="danger" variant="soft">
                  {a}
                </Badge>
              ))}
            </div>
          )}
        </Card>
      ) : null}

      {tab === 'visits' ? (
        <Card padding="lg">
          <p className="text-body text-text-secondary">
            Visit history will appear here. Last visit:{' '}
            {patient.lastVisit ? formatDate(patient.lastVisit) : 'None recorded'}.
          </p>
        </Card>
      ) : null}

      {tab === 'documents' ? (
        <EmptyState
          variant="first-run"
          title="No documents"
          description="No documents have been uploaded for this patient yet."
        />
      ) : null}

      {tab === 'billing' ? (
        <DataTable
          columns={invoiceColumns}
          data={invoices}
          getRowId={(inv) => inv.id}
          aria-label="Patient invoices"
          emptyState={
            <EmptyState variant="first-run" title="No invoices" description="No billing records for this patient." />
          }
        />
      ) : null}
    </div>
  )
}

/** Loading skeleton for future async data */
export function PatientDetailSkeleton() {
  return (
    <div className="space-y-6">
      <Skeleton className="h-24 w-full rounded-lg" />
      <Skeleton className="h-32 w-full rounded-lg" />
      <Skeleton className="h-96 w-full rounded-lg" />
    </div>
  )
}
