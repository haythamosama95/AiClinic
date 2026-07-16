import type { ReactNode } from 'react'
import { ALL_NAV_ITEMS } from '@/components/navigation/nav-model'
import { getPatientById, patientFullName } from '@/data/patients'
import { PlaceholderPage } from '@/pages/app/PlaceholderPage'
import { DevPage, type DevSection } from '@/pages/app/DevPage'
import { AppointmentsPage } from '@/features/appointments/AppointmentsPage'
import { ClinicManagementPage } from '@/features/clinic-management/ClinicManagementPage'
import { VisitPage } from '@/features/visits/VisitPage'
import { PatientDetailPage } from '@/pages/app/patients/PatientDetailPage'
import { PatientsPage } from '@/pages/app/patients/PatientsPage'
import { SettingsPage } from '@/pages/app/settings/SettingsPage'
import { SETTINGS_SCREENS } from '@/data/settings'

export type RouteMeta = {
  title: string
  description: string
}

const ROUTE_DESCRIPTIONS: Record<string, string> = {
  home: 'Your clinic workspace overview and quick actions.',
  dashboard: 'Key metrics, activity, and operational insights at a glance.',
  patients: 'Manage patient records, demographics, and care history.',
  appointments: 'Schedule, confirm, and track patient appointments.',
  encounters: 'Document visits, diagnoses, and clinical notes.',
  workspace: 'Your active tasks, drafts, and in-progress clinical work.',
  billing: 'Charges, payments, and revenue cycle management.',
  invoices: 'Create, send, and reconcile patient invoices.',
  services: 'Catalog procedures, packages, and billable services.',
  'clinic-management': 'Organization profile, branches, staff accounts, and role permissions.',
  staff: 'Team directory, roles, and provider profiles.',
  shifts: 'Staff scheduling, coverage, and shift assignments.',
  reports: 'Operational and clinical reports across your organization.',
  settings: 'Clinic preferences, integrations, and account configuration.',
  dev: 'Design system foundations and component reference.',
}

function metaForNavId(id: string): RouteMeta {
  const item = ALL_NAV_ITEMS.find((nav) => nav.id === id)
  return {
    title: item?.label ?? id,
    description: ROUTE_DESCRIPTIONS[id] ?? `The ${item?.label ?? id} area of AiClinic.`,
  }
}

export type RouteDefinition = RouteMeta & {
  render: (ctx: RouteRenderContext) => ReactNode
}

export type RouteRenderContext = {
  segments: string[]
  navigate: (route: string) => void
}

function placeholderRoute(id: string): RouteDefinition {
  const meta = metaForNavId(id)
  return {
    ...meta,
    render: () => <PlaceholderPage title={meta.title} description={meta.description} />,
  }
}

function patientsRoute(): RouteDefinition {
  const meta = metaForNavId('patients')
  return {
    ...meta,
    render: ({ segments, navigate }) => {
      const patientId = segments[1]
      if (patientId) {
        return <PatientDetailPage patientId={patientId} onNavigate={navigate} />
      }
      return <PatientsPage onNavigate={navigate} />
    },
  }
}

const CLINIC_ROUTE_IDS = [
  'home',
  'dashboard',
  'patients',
  'appointments',
  'encounters',
  'workspace',
  'billing',
  'invoices',
  'services',
  'clinic-management',
  'staff',
  'shifts',
  'reports',
  'settings',
] as const

function settingsRoute(): RouteDefinition {
  const meta = metaForNavId('settings')
  return {
    ...meta,
    render: ({ segments, navigate }) => (
      <SettingsPage screen={segments[1]} onNavigate={navigate} />
    ),
  }
}

export const ROUTE_REGISTRY: Record<string, RouteDefinition> = {
  ...Object.fromEntries(
    CLINIC_ROUTE_IDS.filter(
      (id) =>
        id !== 'patients' &&
        id !== 'settings' &&
        id !== 'clinic-management' &&
        id !== 'appointments' &&
        id !== 'encounters',
    ).map((id) => [id, placeholderRoute(id)]),
  ),
  patients: patientsRoute(),
  appointments: {
    ...metaForNavId('appointments'),
    render: () => <AppointmentsPage />,
  },
  encounters: {
    ...metaForNavId('encounters'),
    render: ({ segments, navigate }) => (
      <VisitPage
        patientId={segments[1]}
        summaryView={segments[2] === 'chronicle' ? 'chronicle' : 'card'}
        onNavigate={navigate}
      />
    ),
  },
  settings: settingsRoute(),
  'clinic-management': {
    title: 'Clinic Management',
    description: ROUTE_DESCRIPTIONS['clinic-management'],
    render: () => <ClinicManagementPage />,
  },
}

export function resolveDevSection(segments: string[]): DevSection {
  const section = segments[1]
  if (section === 'foundations') return 'foundations'
  if (section === 'patterns') return 'patterns'
  if (section === 'guidelines') return 'guidelines'
  return 'components'
}

export function resolveRoute(
  segments: string[],
  navigate: (route: string) => void,
): {
  content: ReactNode
  meta: RouteMeta
  fullWidth: boolean
} {
  const root = segments[0] ?? 'home'

  if (root === 'dev') {
    const section = resolveDevSection(segments)
    const meta: RouteMeta = {
      title: 'Design System',
      description: ROUTE_DESCRIPTIONS.dev,
    }
    return {
      content: <DevPage section={section} />,
      meta,
      fullWidth: section === 'components' || section === 'patterns',
    }
  }

  const route = ROUTE_REGISTRY[root]
  if (!route) {
    return {
      content: (
        <PlaceholderPage
          title="Page not found"
          description="The page you requested does not exist or has been moved."
        />
      ),
      meta: { title: 'Not found', description: '' },
      fullWidth: false,
    }
  }

  const ctx: RouteRenderContext = { segments, navigate }
  let meta: RouteMeta = { title: route.title, description: route.description }

  if (root === 'patients' && segments[1]) {
    const patient = getPatientById(segments[1])
    meta = {
      title: patient ? patientFullName(patient) : 'Patient',
      description: patient?.mrn ?? meta.description,
    }
  }

  if (root === 'settings' && segments[1]) {
    const screen = SETTINGS_SCREENS.find((s) => s.id === segments[1])
    if (screen) {
      meta = {
        title: screen.label,
        description: screen.description,
      }
    }
  }

  return {
    content: route.render(ctx),
    meta,
    fullWidth: root === 'encounters',
  }
}

export function breadcrumbLabel(segments: string[]): string {
  const root = segments[0] ?? 'home'
  if (root === 'dev') {
    const section = resolveDevSection(segments)
    if (section === 'foundations') return 'Foundations'
    if (section === 'patterns') return 'Patterns'
    if (section === 'guidelines') return 'Guidelines'
    return 'Components'
  }
  if (root === 'patients' && segments[1]) {
    const patient = getPatientById(segments[1])
    return patient ? patientFullName(patient) : 'Patient'
  }
  if (root === 'settings' && segments[1]) {
    const screen = SETTINGS_SCREENS.find((s) => s.id === segments[1])
    if (screen) return screen.label
  }
  return metaForNavId(root).title
}
