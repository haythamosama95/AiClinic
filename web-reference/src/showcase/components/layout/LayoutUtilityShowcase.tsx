import { Search } from 'lucide-react'
import { Button } from '@/components/actions/Button'
import { Chip } from '@/components/chip'
import { BulkActionBar } from '@/components/layout/BulkActionBar'
import { ResizablePanels } from '@/components/resizable'
import { ScrollArea } from '@/components/scroll-area'
import { SectionHeader } from '@/components/layout/SectionHeader'
import { Toolbar } from '@/components/layout/Toolbar'
import { SearchInput } from '@/components/ui/search-input/SearchInput'
import {
  ShowcaseSection,
} from '../../ShowcasePrimitives'

export function SectionHeaderShowcase() {
  return (
    <ShowcaseSection id="section-header" title="Section header" componentName="SectionHeader">
      <SectionHeader
        title="Branch configuration"
        description="Manage services and pricing per branch."
        actions={<Button size="sm">Add service</Button>}
      />
    </ShowcaseSection>
  )
}

export function ToolbarShowcase() {
  return (
    <ShowcaseSection id="toolbar" title="Toolbar / filter bar" componentName="Toolbar">
      <Toolbar
        start={
          <>
            <SearchInput placeholder="Search patients…" className="w-56" />
            <Chip selectable selected>Active</Chip>
            <Chip removable onRemove={() => undefined}>Downtown</Chip>
          </>
        }
        end={
          <Button variant="secondary" size="sm" leadingIcon={<Search size={14} />}>
            Filters
          </Button>
        }
      />
    </ShowcaseSection>
  )
}

export function BulkActionBarShowcase() {
  return (
    <ShowcaseSection id="bulk-action-bar" title="Bulk action bar" componentName="BulkActionBar">
      <BulkActionBar
        count={3}
        itemLabel="invoices selected"
        onClear={() => undefined}
        actions={
          <>
            <Button size="sm" variant="secondary">Export</Button>
            <Button size="sm" variant="danger">Void</Button>
          </>
        }
      />
    </ShowcaseSection>
  )
}

export function ScrollAreaLayoutShowcase() {
  return (
    <ShowcaseSection id="layout-scroll-area" title="Scroll area" componentName="ScrollArea">
      <ScrollArea maxHeight={120} className="rounded-lg border border-border-default">
        <div className="space-y-2 p-4">
          {Array.from({ length: 8 }).map((_, i) => (
            <p key={i} className="text-body-sm">Layout scroll item {i + 1}</p>
          ))}
        </div>
      </ScrollArea>
    </ShowcaseSection>
  )
}

export function ResizablePanelsLayoutShowcase() {
  return (
    <ShowcaseSection id="layout-resizable" title="Resizable panels" componentName="ResizablePanels">
      <ResizablePanels
        start={<div className="p-4 text-body-sm">Patient list</div>}
        end={<div className="p-4 text-body-sm">Patient detail</div>}
      />
    </ShowcaseSection>
  )
}
