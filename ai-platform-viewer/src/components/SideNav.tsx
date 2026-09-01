import { useSession } from '@/context/SessionContext'
import type { NavSection } from '@/types'

const NAV_ITEMS: Array<{
  id: Exclude<NavSection, 'secrets'>
  label: string
  note: string
}> = [
    {
      id: 'stage-1',
      label: 'Stage 1',
      note: 'Token contract baseline',
    },
    {
      id: 'stage-2',
      label: 'Stage 2',
      note: 'Clinic keypair enrollment',
    },
  ]

export function SideNav() {
  const { activeSection, setActiveSection } = useSession()

  return (
    <nav className="side-nav" aria-label="Primary">
      <p className="side-nav__heading">Data journey</p>
      <ul className="side-nav__list">
        {NAV_ITEMS.map((item) => {
          const active = activeSection === item.id
          return (
            <li key={item.id}>
              <button
                type="button"
                className={`side-nav__item${active ? ' side-nav__item--active' : ''}${item.id === 'stage-2' ? ' side-nav__item--clinic' : ''}`}
                aria-current={active ? 'page' : undefined}
                onClick={() => setActiveSection(item.id)}
              >
                <span className="side-nav__label">{item.label}</span>
                <span className="side-nav__note">{item.note}</span>
              </button>
            </li>
          )
        })}
      </ul>
    </nav>
  )
}
