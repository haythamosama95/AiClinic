import type { LucideIcon } from 'lucide-react'
import {
  BarChart3,
  Calendar,
  ClipboardList,
  FileText,
  FlaskConical,
  Home,
  LayoutGrid,
  Receipt,
  Settings,
  Stethoscope,
  UserRound,
  Users,
} from 'lucide-react'

export type NavItem = {
  id: string
  label: string
  icon: LucideIcon
  count?: number
}

export type NavGroup = {
  id: string
  label?: string
  items: NavItem[]
}

export type Branch = {
  id: string
  name: string
  org: string
}

export const MOCK_ORG = 'AiClinic Health Group'

export const MOCK_BRANCHES: Branch[] = [
  { id: 'downtown', name: 'Downtown Clinic', org: MOCK_ORG },
  { id: 'nasr-city', name: 'Nasr City', org: MOCK_ORG },
  { id: 'alexandria', name: 'Alexandria', org: MOCK_ORG },
]

export const MOCK_USER = {
  name: 'Dr. Sarah Ali',
  role: 'Physician',
  email: 'sarah.ali@aiclinic.health',
}

export const MOCK_NOTIFICATION_COUNT = 3

export const CLINIC_NAV_GROUPS: NavGroup[] = [
  {
    id: 'main',
    items: [
      { id: 'home', label: 'Home', icon: Home },
      { id: 'dashboard', label: 'Dashboard', icon: LayoutGrid },
    ],
  },
  {
    id: 'clinical',
    label: 'Clinical',
    items: [
      { id: 'patients', label: 'Patients', icon: Users, count: 128 },
      { id: 'appointments', label: 'Appointments', icon: Calendar, count: 12 },
      { id: 'encounters', label: 'Encounters', icon: Stethoscope },
      { id: 'workspace', label: 'Workspace', icon: ClipboardList },
    ],
  },
  {
    id: 'operations',
    label: 'Operations',
    items: [
      { id: 'billing', label: 'Billing', icon: Receipt },
      { id: 'invoices', label: 'Invoices', icon: FileText, count: 5 },
      { id: 'services', label: 'Services', icon: LayoutGrid },
      { id: 'staff', label: 'Staff', icon: UserRound },
      { id: 'shifts', label: 'Shifts', icon: Calendar },
      { id: 'reports', label: 'Reports', icon: BarChart3 },
    ],
  },
]

export const CLINIC_NAV_FOOTER: NavItem[] = [
  { id: 'settings', label: 'Settings', icon: Settings },
  { id: 'dev', label: 'Dev', icon: FlaskConical },
]

export const ALL_NAV_ITEMS: NavItem[] = [
  ...CLINIC_NAV_GROUPS.flatMap((g) => g.items),
  ...CLINIC_NAV_FOOTER,
]
