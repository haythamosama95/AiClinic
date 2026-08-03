import { actionsSections } from './actions'
import { aiSections } from './ai'
import { displaySections } from './display'
import { feedbackSections } from './feedback'
import { inputsSections } from './inputs'
import { layoutSections } from './layout'
import { navigationSections } from './navigation'
import {
  buildComponentSections,
  sectionsByGroup,
  showcaseGroups,
  type ShowcaseGroupId,
  type ShowcaseSectionDef,
} from '../registry'

export const componentSections: ShowcaseSectionDef[] = buildComponentSections(
  actionsSections,
  inputsSections,
  displaySections,
  navigationSections,
  feedbackSections,
  aiSections,
  layoutSections,
)

export const groupedComponentSections = sectionsByGroup(componentSections)

export { showcaseGroups, type ShowcaseGroupId, type ShowcaseSectionDef }

/**
 * Plug-in point for parallel agents:
 *
 * 1. Create showcase/components/<group>/YourShowcase.tsx
 * 2. Export a ShowcaseSectionDef from showcase/components/<group>/index.ts
 * 3. Import and spread into buildComponentSections() above
 *
 * Example (Actions agent):
 *   // showcase/components/actions/index.ts
 *   export const actionsSections = [
 *     { id: 'button', title: 'Button', group: 'actions', component: ButtonShowcase, status: 'ready' },
 *   ]
 */
