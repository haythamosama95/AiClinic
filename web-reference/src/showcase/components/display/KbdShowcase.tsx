import { Kbd, KbdKey } from '@/components/kbd'
import {
  ShowcaseDemo,
  ShowcaseDemoGrid,
  ShowcaseSection,
} from '../../ShowcasePrimitives'

export function KbdShowcase() {
  return (
    <ShowcaseSection
      id="kbd"
      title="Kbd / Shortcut hint"
      description="Keyboard shortcut chips for menus, tooltips, and empty states."
      componentName="Kbd · KbdKey"
    >
      <ShowcaseDemoGrid columns={3}>
        <ShowcaseDemo label="Single key" propsHint="<KbdKey>">
          <KbdKey>Enter</KbdKey>
          <KbdKey>Esc</KbdKey>
          <KbdKey>/</KbdKey>
        </ShowcaseDemo>

        <ShowcaseDemo label="Chord" propsHint='keys={["⌘", "K"]}'>
          <Kbd keys={['⌘', 'K']} />
        </ShowcaseDemo>

        <ShowcaseDemo label="Search hint" propsHint="menu / Command Bar">
          <span className="inline-flex items-center gap-2 text-body-sm text-text-secondary">
            Press <Kbd keys={['⌘', 'F']} /> to search
          </span>
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
