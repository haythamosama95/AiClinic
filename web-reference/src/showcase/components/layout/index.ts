import type { ShowcaseSectionDef } from '../../registry'
import { AppShellShowcase } from './AppShellShowcase'
import { PageHeaderShowcase } from './PageHeaderShowcase'
import {
  BulkActionBarShowcase,
  ResizablePanelsLayoutShowcase,
  ScrollAreaLayoutShowcase,
  SectionHeaderShowcase,
  ToolbarShowcase,
} from './LayoutUtilityShowcase'

export const layoutSections: ShowcaseSectionDef[] = [
  {
    id: 'app-shell',
    title: 'App shell',
    group: 'layout',
    component: AppShellShowcase,
    status: 'ready',
  },
  {
    id: 'page-header',
    title: 'Page header',
    group: 'layout',
    component: PageHeaderShowcase,
    status: 'ready',
  },
  { id: 'section-header', title: 'Section header', group: 'layout', component: SectionHeaderShowcase, status: 'ready' },
  { id: 'toolbar', title: 'Toolbar / filter bar', group: 'layout', component: ToolbarShowcase, status: 'ready' },
  { id: 'bulk-action-bar', title: 'Bulk action bar', group: 'layout', component: BulkActionBarShowcase, status: 'ready' },
  { id: 'layout-scroll-area', title: 'Scroll area', group: 'layout', component: ScrollAreaLayoutShowcase, status: 'ready' },
  { id: 'layout-resizable', title: 'Resizable panels', group: 'layout', component: ResizablePanelsLayoutShowcase, status: 'ready' },
]
