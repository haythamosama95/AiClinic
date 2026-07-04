import type { ReactNode } from 'react'
import { ALL_NAV_ITEMS } from '@/components/navigation/nav-model'
import { PlaceholderPage } from '@/pages/app/PlaceholderPage'
import { DevPage, type DevSection } from '@/pages/app/DevPage'

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
  render: () => ReactNode
}

function placeholderRoute(id: string): RouteDefinition {
  const meta = metaForNavId(id)
  return {
    ...meta,
    render: () => <PlaceholderPage title={meta.title} description={meta.description} />,
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
  'staff',
  'shifts',
  'reports',
  'settings',
] as const

export const ROUTE_REGISTRY: Record<string, RouteDefinition> = Object.fromEntries(
  CLINIC_ROUTE_IDS.map((id) => [id, placeholderRoute(id)]),
)

export function resolveDevSection(segments: string[]): DevSection {
  if (segments[1] === 'foundations') return 'foundations'
  return 'components'
}

export function resolveRoute(segments: string[]): {
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
      fullWidth: section === 'components',
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

  return {
    content: route.render(),
    meta: { title: route.title, description: route.description },
    fullWidth: false,
  }
}

export function breadcrumbLabel(segments: string[]): string {
  const root = segments[0] ?? 'home'
  if (root === 'dev') {
    const section = resolveDevSection(segments)
    return section === 'foundations' ? 'Foundations' : 'Components'
  }
  return metaForNavId(root).title
}
