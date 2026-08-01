import { Copy, Edit, Trash2 } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { ContextMenu, Menu } from '@/components/navigation/Menu'
import { ShowcaseDemo, ShowcaseDemoGrid, ShowcaseSection } from '../../ShowcasePrimitives'

const MENU_ENTRIES = [
  {
    type: 'section' as const,
    label: 'Patient',
    items: [
      { id: 'edit', label: 'Edit profile', icon: <Edit size={16} strokeWidth={1.5} />, shortcut: ['⌘', 'E'], onSelect: () => undefined },
      { id: 'copy', label: 'Copy MRN', icon: <Copy size={16} strokeWidth={1.5} />, onSelect: () => undefined },
    ],
  },
  { type: 'separator' as const },
  {
    id: 'delete',
    label: 'Delete record',
    icon: <Trash2 size={16} strokeWidth={1.5} />,
    destructive: true,
    onSelect: () => undefined,
  },
]

export function MenuShowcase() {
  return (
    <ShowcaseSection
      id="menu"
      title="Menu / Context menu"
      description="Dropdown and right-click menus with icons, shortcuts, and destructive items."
      componentName="Menu"
    >
      <ShowcaseDemoGrid columns={2}>
        <ShowcaseDemo label="Dropdown menu" propsHint="Menu + entries">
          <Menu
            trigger={<Button variant="secondary">Open menu</Button>}
            entries={MENU_ENTRIES}
          />
        </ShowcaseDemo>
        <ShowcaseDemo label="Context menu" propsHint="right-click target">
          <ContextMenu entries={MENU_ENTRIES}>
            <div className="rounded-md border border-dashed border-border-default px-8 py-6 text-body-sm text-text-secondary">
              Right-click here
            </div>
          </ContextMenu>
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
