import type { ComponentType } from 'react'

export type ShowcaseGroupId =
  | 'actions'
  | 'inputs'
  | 'display'
  | 'navigation'
  | 'feedback'
  | 'ai'
  | 'layout'

export type ShowcaseSectionStatus = 'ready' | 'placeholder'

export interface ShowcaseSectionDef {
  id: string
  title: string
  description?: string
  group: ShowcaseGroupId
  component: ComponentType
  status: ShowcaseSectionStatus
}

export interface ShowcaseGroupDef {
  id: ShowcaseGroupId
  title: string
  description: string
}

export const showcaseGroups: ShowcaseGroupDef[] = [
  {
    id: 'actions',
    title: 'Actions',
    description: 'Buttons, icon buttons, split buttons, and segmented controls.',
  },
  {
    id: 'inputs',
    title: 'Inputs & forms',
    description: 'Form fields, text inputs, pickers, and validation states.',
  },
  {
    id: 'display',
    title: 'Data display',
    description: 'Badges, chips, avatars, progress, and read-only primitives.',
  },
  {
    id: 'navigation',
    title: 'Navigation',
    description: 'Sidebar, tabs, menus, Command Bar, and wayfinding.',
  },
  {
    id: 'feedback',
    title: 'Feedback & overlays',
    description: 'Toasts, dialogs, drawers, and empty states.',
  },
  {
    id: 'ai',
    title: 'AI',
    description: 'AI mode, panels, proposed actions, and thinking indicators.',
  },
  {
    id: 'layout',
    title: 'Layout & utility',
    description: 'Headers, toolbars, scroll areas, and shell composition.',
  },
]

/** Merge section arrays from each component group. Other agents extend their group file. */
export function buildComponentSections(
  ...sectionArrays: ShowcaseSectionDef[][]
): ShowcaseSectionDef[] {
  return sectionArrays.flat()
}

export function sectionsByGroup(
  sections: ShowcaseSectionDef[],
): Record<ShowcaseGroupId, ShowcaseSectionDef[]> {
  return showcaseGroups.reduce(
    (acc, group) => {
      acc[group.id] = sections.filter((section) => section.group === group.id)
      return acc
    },
    {} as Record<ShowcaseGroupId, ShowcaseSectionDef[]>,
  )
}
