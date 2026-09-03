import type { NavSection } from '@/types'

export const DEFAULT_SECTION: NavSection = 'stage-1'

const SECTION_PATHS: Record<NavSection, string> = {
  'stage-0': '/stage-0',
  'stage-1': '/stage-1',
  'stage-2': '/stage-2',
  'stage-3': '/stage-3',
  'stage-4': '/stage-4',
  'stage-5': '/stage-5',
  'stage-6': '/stage-6',
  'stage-7': '/stage-7',
  'stage-8': '/stage-8',
  'stage-9': '/stage-9',
  'stage-10': '/stage-10',
  'stage-11': '/stage-11',
  'stage-12': '/stage-12',
  'guard-pipeline': '/guard-pipeline',
  secrets: '/secrets',
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
