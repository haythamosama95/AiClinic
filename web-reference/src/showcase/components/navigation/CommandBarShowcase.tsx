import { Button } from '@/components/actions/Button'
import { useCommandBar } from '@/providers/CommandBarProvider'
import { ShowcaseDemo, ShowcaseSection } from '../../ShowcasePrimitives'

function CommandBarTrigger() {
  const { openCommandBar } = useCommandBar()
  return (
    <Button variant="secondary" onClick={openCommandBar}>
      Open command bar
    </Button>
  )
}

export function CommandBarShowcase() {
  return (
    <ShowcaseSection
      id="command-bar"
      title="Command bar"
      description="Global ⌘K overlay with grouped results, keyboard navigation, and AI entry transition."
      componentName="CommandBar"
    >
      <ShowcaseDemo label="Hero overlay" propsHint="⌘K or trigger · Esc closes">
        <CommandBarTrigger />
        <p className="text-body-sm text-text-secondary">
          Press <kbd className="rounded-sm border border-border-default bg-surface-sunken px-1 font-mono text-caption">⌘K</kbd> anywhere in the showcase.
        </p>
      </ShowcaseDemo>
    </ShowcaseSection>
  )
}
