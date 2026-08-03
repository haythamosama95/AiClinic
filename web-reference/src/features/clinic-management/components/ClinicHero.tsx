import { motion } from 'motion/react'
import { Building2, MapPin, Shield, Users } from 'lucide-react'
import { cn } from '@/lib/cn'
import { getReducedMotion, motionPresets, resolveTransition } from '@/lib/motion'
import type { OrganizationProfile } from '../types'

export type ClinicHeroProps = {
  organization: OrganizationProfile
  branchCount: number
  staffCount: number
  activeBranchCount: number
}

function orgInitials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return '?'
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase()
  return (parts[0][0] + parts[1][0]).toUpperCase()
}

const stats = [
  { key: 'branches', icon: MapPin, label: 'Branches' },
  { key: 'staff', icon: Users, label: 'Team members' },
  { key: 'active', icon: Shield, label: 'Active locations' },
] as const

export function ClinicHero({
  organization,
  branchCount,
  staffCount,
  activeBranchCount,
}: ClinicHeroProps) {
  const values: Record<(typeof stats)[number]['key'], number> = {
    branches: branchCount,
    staff: staffCount,
    active: activeBranchCount,
  }

  return (
    <div className="relative overflow-hidden rounded-2xl border border-border-subtle">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 bg-[linear-gradient(125deg,var(--color-teal-500)_0%,var(--color-violet-500)_48%,var(--color-teal-600)_100%)] opacity-[0.07]"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -end-24 -top-24 size-64 rounded-full bg-[radial-gradient(circle,var(--color-violet-400)_0%,transparent_70%)] opacity-20 blur-2xl"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -bottom-16 -start-16 size-48 rounded-full bg-[radial-gradient(circle,var(--color-teal-400)_0%,transparent_70%)] opacity-25 blur-2xl"
      />

      <div className="relative flex flex-col gap-6 p-6 sm:flex-row sm:items-center sm:justify-between sm:p-8">
        <div className="flex min-w-0 items-center gap-5">
          <motion.div
            initial={getReducedMotion() ? false : { scale: 0.92, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={resolveTransition(motionPresets.fade)}
            className={cn(
              'relative flex size-16 shrink-0 items-center justify-center rounded-2xl',
              'bg-[linear-gradient(145deg,var(--color-teal-500),var(--color-violet-600))]',
              'text-h2 font-semibold tracking-tight text-white shadow-elevation-2',
            )}
          >
            {organization.logoUrl ? (
              <img
                src={organization.logoUrl}
                alt=""
                className="size-full rounded-2xl object-cover"
              />
            ) : (
              orgInitials(organization.name)
            )}
            <span
              aria-hidden
              className="absolute inset-0 rounded-2xl bg-white/10 opacity-0 transition-opacity hover:opacity-100"
            />
          </motion.div>

          <div className="min-w-0 space-y-1">
            <div className="flex items-center gap-2 text-caption font-medium uppercase tracking-widest text-text-tertiary">
              <Building2 size={14} strokeWidth={1.75} />
              Clinic identity
            </div>
            <h2 className="truncate font-[family-name:var(--font-display)] text-h2 text-text-primary">
              {organization.name}
            </h2>
            <p className="text-body-sm text-text-secondary">
              {organization.currencyCode} · {organization.timezone.replace(/_/g, ' ')}
            </p>
          </div>
        </div>

        <div className="grid grid-cols-3 gap-3 sm:gap-4">
          {stats.map(({ key, icon: Icon, label }, index) => (
            <motion.div
              key={key}
              initial={getReducedMotion() ? false : { y: 8, opacity: 0 }}
              animate={{ y: 0, opacity: 1 }}
              transition={{
                ...resolveTransition(motionPresets.fade),
                delay: getReducedMotion() ? 0 : index * 0.06,
              }}
              className="rounded-xl border border-white/40 bg-surface-default/80 px-4 py-3 backdrop-blur-sm"
            >
              <div className="flex items-center gap-2 text-text-tertiary">
                <Icon size={14} strokeWidth={1.75} />
                <span className="text-caption">{label}</span>
              </div>
              <p className="mt-1 font-[family-name:var(--font-display)] text-h3 tabular-nums text-text-primary">
                {values[key]}
              </p>
            </motion.div>
          ))}
        </div>
      </div>
    </div>
  )
}
