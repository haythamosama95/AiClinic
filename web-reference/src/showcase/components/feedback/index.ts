import type { ShowcaseSectionDef } from '../../registry'
import {
  AlertShowcase,
  DialogShowcase,
  DrawerShowcase,
  EmptyStateShowcase,
  ErrorStateShowcase,
  LoadingOverlayShowcase,
  PopoverShowcase,
  ToastShowcase,
} from './FeedbackShowcase'

export const feedbackSections: ShowcaseSectionDef[] = [
  { id: 'toast', title: 'Toast', group: 'feedback', component: ToastShowcase, status: 'ready' },
  { id: 'alert', title: 'Inline alert', group: 'feedback', component: AlertShowcase, status: 'ready' },
  { id: 'dialog', title: 'Dialog', group: 'feedback', component: DialogShowcase, status: 'ready' },
  { id: 'drawer', title: 'Drawer / sheet', group: 'feedback', component: DrawerShowcase, status: 'ready' },
  { id: 'popover', title: 'Popover', group: 'feedback', component: PopoverShowcase, status: 'ready' },
  { id: 'loading-overlay', title: 'Loading overlay', group: 'feedback', component: LoadingOverlayShowcase, status: 'ready' },
  { id: 'empty-state', title: 'Empty states', group: 'feedback', component: EmptyStateShowcase, status: 'ready' },
  { id: 'error-state', title: 'Error state', group: 'feedback', component: ErrorStateShowcase, status: 'ready' },
]
