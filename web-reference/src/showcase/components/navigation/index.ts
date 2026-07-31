import type { ShowcaseSectionDef } from '../../registry'
import { BreadcrumbShowcase } from './BreadcrumbShowcase'
import { TabsShowcase } from './TabsShowcase'
import { MenuShowcase } from './MenuShowcase'
import { PaginationShowcase } from './PaginationShowcase'
import { StepperShowcase } from './StepperShowcase'
import { SidebarShowcase } from './SidebarShowcase'
import { TopBarShowcase } from './TopBarShowcase'
import { CommandBarShowcase } from './CommandBarShowcase'
import { BranchSwitcherShowcase } from './BranchSwitcherShowcase'
import { UserMenuShowcase } from './UserMenuShowcase'

export const navigationSections: ShowcaseSectionDef[] = [
  {
    id: 'breadcrumb',
    title: 'Breadcrumb',
    group: 'navigation',
    component: BreadcrumbShowcase,
    status: 'ready',
  },
  {
    id: 'tabs',
    title: 'Tabs',
    group: 'navigation',
    component: TabsShowcase,
    status: 'ready',
  },
  {
    id: 'menu',
    title: 'Menu',
    group: 'navigation',
    component: MenuShowcase,
    status: 'ready',
  },
  {
    id: 'pagination',
    title: 'Pagination',
    group: 'navigation',
    component: PaginationShowcase,
    status: 'ready',
  },
  {
    id: 'stepper',
    title: 'Stepper',
    group: 'navigation',
    component: StepperShowcase,
    status: 'ready',
  },
  {
    id: 'app-sidebar',
    title: 'App sidebar',
    group: 'navigation',
    component: SidebarShowcase,
    status: 'ready',
  },
  {
    id: 'app-topbar',
    title: 'App top bar',
    group: 'navigation',
    component: TopBarShowcase,
    status: 'ready',
  },
  {
    id: 'command-bar',
    title: 'Command bar',
    group: 'navigation',
    component: CommandBarShowcase,
    status: 'ready',
  },
  {
    id: 'branch-switcher',
    title: 'Branch switcher',
    group: 'navigation',
    component: BranchSwitcherShowcase,
    status: 'ready',
  },
  {
    id: 'user-menu',
    title: 'User menu',
    group: 'navigation',
    component: UserMenuShowcase,
    status: 'ready',
  },
]
