import type { ShowcaseSectionDef } from '../../registry'
import { ButtonShowcase } from './ButtonShowcase'
import { IconButtonShowcase } from './IconButtonShowcase'
import { SegmentedControlShowcase } from './SegmentedControlShowcase'
import { SplitButtonShowcase } from './SplitButtonShowcase'

export const actionsSections: ShowcaseSectionDef[] = [
  {
    id: 'button',
    title: 'Button',
    description: 'Primary, secondary, ghost, danger, AI, and link variants.',
    group: 'actions',
    component: ButtonShowcase,
    status: 'ready',
  },
  {
    id: 'icon-button',
    title: 'Icon button',
    group: 'actions',
    component: IconButtonShowcase,
    status: 'ready',
  },
  {
    id: 'split-button',
    title: 'Split button',
    group: 'actions',
    component: SplitButtonShowcase,
    status: 'ready',
  },
  {
    id: 'segmented-control',
    title: 'Segmented control',
    group: 'actions',
    component: SegmentedControlShowcase,
    status: 'ready',
  },
]
