import type { ShowcaseSectionDef } from '../../registry'
import { AppShellShowcase } from './AppShellShowcase'
import { PageHeaderShowcase } from './PageHeaderShowcase'

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
]
