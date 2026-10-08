import type { NavSection } from '@/types'

export const DEFAULT_SECTION: NavSection = 'stage-7'

const SECTION_PATHS: Record<NavSection, string> = {
  'stage-7': '/stage-7',
  'stage-8': '/stage-8',
  'stage-9': '/stage-9',
  'stage-10': '/stage-10',
  'stage-11': '/stage-11',
  'stage-12': '/stage-12',
}

const PATH_TO_SECTION = new Map<string, NavSection>(
  Object.entries(SECTION_PATHS).map(([section, path]) => [
    path,
    section as NavSection,
  ]),
)

export function pathForSection(section: NavSection): string {
  return SECTION_PATHS[section]
}

export function sectionFromPath(pathname: string): NavSection {
  return PATH_TO_SECTION.get(pathname) ?? DEFAULT_SECTION
}
