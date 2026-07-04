import { useState } from 'react'
import { buildDefaultCommandItems, CommandBar } from '@/components/navigation/CommandBar'
import { FoundationsContent } from '@/pages/FoundationsPage'
import { ComponentsPage, ComponentsSubNav } from '@/pages/ComponentsPage'
import { ShowcaseShell, type ShowcaseArea } from '@/showcase/ShowcaseShell'

function FoundationsArea() {
  return (
    <div className="space-y-16">
      <div>
        <p className="text-overline text-text-tertiary">Milestone 1</p>
        <h2 className="text-h2 text-text-primary">Foundations</h2>
        <p className="mt-2 max-w-2xl text-body-lg text-text-secondary">
          Tokens, typography, spacing, motion, and The Signal.
        </p>
      </div>
      <FoundationsContent />
    </div>
  )
}

export function ShowcaseApp() {
  const [area, setArea] = useState<ShowcaseArea>('components')

  return (
    <>
      <ShowcaseShell
        area={area}
        onAreaChange={setArea}
        subNav={area === 'components' ? <ComponentsSubNav /> : undefined}
      >
        {area === 'foundations' ? <FoundationsArea /> : <ComponentsPage />}
      </ShowcaseShell>
      <CommandBar items={buildDefaultCommandItems()} />
    </>
  )
}
