import type { ShowcaseSectionDef } from '../../registry'
import { AvatarShowcase } from './AvatarShowcase'
import { BadgeShowcase } from './BadgeShowcase'
import { ChipShowcase } from './ChipShowcase'
import { DividerShowcase } from './DividerShowcase'
import { KbdShowcase } from './KbdShowcase'
import { ProgressShowcase } from './ProgressShowcase'
import { SkeletonShowcase } from './SkeletonShowcase'
import { TooltipShowcase } from './TooltipShowcase'
import {
  CalendarShowcase,
  CardShowcase,
  ChartShowcase,
  CodeBlockShowcase,
  DataTableShowcase,
  DescriptionListShowcase,
  EntityCardsShowcase,
  ListShowcase,
  MetricCardShowcase,
  MoneyDisplayShowcase,
  ResizablePanelsShowcase,
  ScrollAreaShowcase,
  TimelineShowcase,
} from './DataDisplayShowcase'

/**
 * M2 Basic Display + M4 Data Display sections.
 */
export const displaySections: ShowcaseSectionDef[] = [
  {
    id: 'badge',
    title: 'Badge / Status pill',
    group: 'display',
    component: BadgeShowcase,
    status: 'ready',
  },
  {
    id: 'chip',
    title: 'Chip / Tag',
    group: 'display',
    component: ChipShowcase,
    status: 'ready',
  },
  {
    id: 'avatar',
    title: 'Avatar / Group',
    group: 'display',
    component: AvatarShowcase,
    status: 'ready',
  },
  {
    id: 'tooltip',
    title: 'Tooltip',
    group: 'display',
    component: TooltipShowcase,
    status: 'ready',
  },
  {
    id: 'kbd',
    title: 'Kbd',
    group: 'display',
    component: KbdShowcase,
    status: 'ready',
  },
  {
    id: 'divider',
    title: 'Divider',
    group: 'display',
    component: DividerShowcase,
    status: 'ready',
  },
  {
    id: 'skeleton',
    title: 'Skeleton',
    group: 'display',
    component: SkeletonShowcase,
    status: 'ready',
  },
  {
    id: 'progress',
    title: 'Progress',
    group: 'display',
    component: ProgressShowcase,
    status: 'ready',
  },
  { id: 'data-table', title: 'Table / Data grid', group: 'display', component: DataTableShowcase, status: 'ready' },
  { id: 'card', title: 'Card', group: 'display', component: CardShowcase, status: 'ready' },
  { id: 'metric-card', title: 'Metric card', group: 'display', component: MetricCardShowcase, status: 'ready' },
  { id: 'entity-cards', title: 'Entity cards', group: 'display', component: EntityCardsShowcase, status: 'ready' },
  { id: 'list', title: 'List', group: 'display', component: ListShowcase, status: 'ready' },
  { id: 'description-list', title: 'Description list', group: 'display', component: DescriptionListShowcase, status: 'ready' },
  { id: 'timeline', title: 'Timeline', group: 'display', component: TimelineShowcase, status: 'ready' },
  { id: 'calendar', title: 'Calendar', group: 'display', component: CalendarShowcase, status: 'ready' },
  { id: 'chart', title: 'Chart primitives', group: 'display', component: ChartShowcase, status: 'ready' },
  { id: 'money-display', title: 'Money display', group: 'display', component: MoneyDisplayShowcase, status: 'ready' },
  { id: 'code-block', title: 'Code block', group: 'display', component: CodeBlockShowcase, status: 'ready' },
  { id: 'scroll-area', title: 'Scroll area', group: 'display', component: ScrollAreaShowcase, status: 'ready' },
  { id: 'resizable-panels', title: 'Resizable panels', group: 'display', component: ResizablePanelsShowcase, status: 'ready' },
]
