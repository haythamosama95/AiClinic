import { useState } from 'react'
import { useSession } from '@/context/SessionContext'
import { pathForSection } from '@/lib/routes'
import type { NavSection } from '@/types'

const NAV_ITEMS: Array<{
  id: Exclude<NavSection, 'secrets'>
  label: string
  short: string
  note: string
  accentClass?: string
}> = [
    {
      id: 'stage-0',
      label: 'Stage 0',
      short: '0',
      note: 'Platform configuration and boot',
      accentClass: 'side-nav__item--boot',
    },
    {
      id: 'stage-1',
      label: 'Stage 1',
      short: '1',
      note: 'Token contract baseline',
    },
    {
      id: 'stage-2',
      label: 'Stage 2',
      short: '2',
      note: 'Clinic keypair enrollment',
      accentClass: 'side-nav__item--clinic',
    },
    {
      id: 'stage-3',
      label: 'Stage 3',
      short: '3',
      note: 'Platform installation enrollment',
      accentClass: 'side-nav__item--platform',
    },
    {
      id: 'stage-4',
      label: 'Stage 4',
      short: '4',
      note: 'Entitlement and capability grants',
      accentClass: 'side-nav__item--entitlement',
    },
    {
      id: 'stage-5',
      label: 'Stage 5',
      short: '5',
      note: 'Routing policy',
      accentClass: 'side-nav__item--routing',
    },
    {
      id: 'stage-6',
      label: 'Stage 6',
      short: '6',
      note: 'Minting an AAT',
      accentClass: 'side-nav__item--mint',
    },
    {
      id: 'stage-7',
      label: 'Stage 7',
      short: '7',
      note: 'Discovery',
      accentClass: 'side-nav__item--discovery',
    },
    {
      id: 'stage-8',
      label: 'Stage 8',
      short: '8',
      note: 'Request ingress',
      accentClass: 'side-nav__item--ingress',
    },
    {
      id: 'stage-9',
      label: 'Stage 9',
      short: '9',
      note: 'The guard',
      accentClass: 'side-nav__item--guard',
    },
    {
      id: 'stage-10',
      label: 'Stage 10',
      short: '10',
      note: 'Accept, route, invoke, stream',
      accentClass: 'side-nav__item--stream',
    },
    {
      id: 'stage-11',
      label: 'Stage 11',
      short: '11',
      note: 'Terminal settlement',
      accentClass: 'side-nav__item--settlement',
    },
    {
      id: 'stage-12',
      label: 'Stage 12',
      short: '12',
      note: 'Lookup and support',
      accentClass: 'side-nav__item--lookup',
    },
  ]

export function SideNav() {
  const { activeSection, setActiveSection } = useSession()
  const [collapsed, setCollapsed] = useState(true)

  return (
    <nav
      className={`side-nav${collapsed ? ' side-nav--collapsed' : ''}`}
      aria-label="Primary"
    >
      <div className="side-nav__toolbar">
        <p className="side-nav__heading">Data journey</p>
        <button
          type="button"
          className="side-nav__collapse"
          aria-expanded={!collapsed}
          aria-controls="side-nav-list"
          aria-label={collapsed ? 'Expand navigation' : 'Collapse navigation'}
          title={collapsed ? 'Expand navigation' : 'Collapse navigation'}
          onClick={() => setCollapsed((value) => !value)}
        >
          <svg
            className="side-nav__collapse-icon"
            width="16"
            height="16"
            viewBox="0 0 16 16"
            fill="none"
            aria-hidden="true"
          >
            <path
              d="M10 3.5 5.5 8 10 12.5"
              stroke="currentColor"
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </button>
      </div>
      <ul id="side-nav-list" className="side-nav__list">
        {NAV_ITEMS.map((item) => {
          const active = activeSection === item.id
          return (
            <li key={item.id}>
              <a
                href={pathForSection(item.id)}
                className={`side-nav__item${active ? ' side-nav__item--active' : ''}${item.accentClass ? ` ${item.accentClass}` : ''}`}
                aria-current={active ? 'page' : undefined}
                aria-label={`${item.label}: ${item.note}`}
                title={collapsed ? `${item.label} — ${item.note}` : undefined}
                onClick={(event) => {
                  if (
                    event.metaKey ||
                    event.ctrlKey ||
                    event.shiftKey ||
                    event.altKey ||
                    event.button !== 0
                  ) {
                    return
                  }
                  event.preventDefault()
                  setActiveSection(item.id)
                }}
              >
                <span className="side-nav__short" aria-hidden="true">{item.short}</span>
                <span className="side-nav__label">{item.label}</span>
                <span className="side-nav__note">{item.note}</span>
              </a>
            </li>
          )
        })}
      </ul>
    </nav>
  )
}
