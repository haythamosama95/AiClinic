import type { ShowcaseSectionDef } from '../../registry'
import { AvatarShowcase } from './AvatarShowcase'
import { BadgeShowcase } from './BadgeShowcase'
import { ChipShowcase } from './ChipShowcase'
import { DividerShowcase } from './DividerShowcase'
import { KbdShowcase } from './KbdShowcase'
import { ProgressShowcase } from './ProgressShowcase'
import { SkeletonShowcase } from './SkeletonShowcase'
import { TooltipShowcase } from './TooltipShowcase'

/**
 * M2 Basic Display sections — register new display components here.
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
]
