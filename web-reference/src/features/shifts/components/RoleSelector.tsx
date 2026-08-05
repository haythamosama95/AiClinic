import { FlaskConical, HeartPulse, Headset, Stethoscope } from 'lucide-react'
import { cn } from '@/lib/cn'
import { ROLES } from '../mock-data'
import type { RoleId } from '../types'

const ROLE_ICONS: Record<RoleId, React.ReactNode> = {
  doctor: <Stethoscope size={16} />,
  nurse: <HeartPulse size={16} />,
  receptionist: <Headset size={16} />,
  'lab-tech': <FlaskConical size={16} />,
}

type RoleSelectorProps = {
  selectedRoleId: RoleId
  onSelect: (roleId: RoleId) => void
}

export function RoleSelector({ selectedRoleId, onSelect }: RoleSelectorProps) {
  return (
    <div
      className="flex flex-wrap gap-1 rounded-lg border border-border-subtle bg-surface-sunken p-1"
      role="tablist"
      aria-label="Staff role"
    >
      {ROLES.map((role) => {
        const active = role.id === selectedRoleId
        return (
          <button
            key={role.id}
            type="button"
            role="tab"
            aria-selected={active}
            className={cn('shift-role-tab', role.accentClass, active && 'shift-role-tab--active')}
            onClick={() => onSelect(role.id)}
          >
            {ROLE_ICONS[role.id]}
            <span>{role.label}</span>
          </button>
        )
      })}
    </div>
  )
}
