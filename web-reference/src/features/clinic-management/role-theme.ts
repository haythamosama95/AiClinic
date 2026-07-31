import type { StaffRole } from './types'

export const ROLE_ACCENTS: Record<StaffRole, string> = {
  administrator: 'from-[var(--color-violet-500)] to-[var(--color-violet-700)]',
  doctor: 'from-[var(--color-teal-500)] to-[var(--color-teal-700)]',
  receptionist: 'from-[var(--color-neutral-500)] to-[var(--color-neutral-700)]',
  lab_staff: 'from-[var(--color-neutral-400)] to-[var(--color-neutral-600)]',
}

export const ROLE_BADGE_COLORS: Record<StaffRole, 'ai' | 'teal' | 'info' | 'neutral'> = {
  administrator: 'ai',
  doctor: 'teal',
  receptionist: 'info',
  lab_staff: 'neutral',
}

/** One-line scope from settings role definitions (RBAC catalog). */
export const ROLE_SUMMARIES: Record<StaffRole, string> = {
  administrator:
    'Organization admin — staff, branches, billing, and the permission matrix.',
  doctor: 'Clinical staff — patients, appointments, visits, attachments, and AI.',
  receptionist: 'Front desk — patients, appointments, invoices, and payments.',
  lab_staff: 'Laboratory — view patients and upload visit attachments.',
}
