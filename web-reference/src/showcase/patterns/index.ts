import type { ComponentType } from 'react'
import { AiFlowPattern } from './AiFlowPattern'
import { CalendarQueuePattern } from './CalendarQueuePattern'
import { DashboardPattern } from './DashboardPattern'
import { EditorFormPattern } from './EditorFormPattern'
import { ListIndexPattern } from './ListIndexPattern'
import { MasterDetailPattern } from './MasterDetailPattern'
import { RecordDetailPattern } from './RecordDetailPattern'
import { StateGalleryPattern } from './StateGalleryPattern'
import { WizardPattern } from './WizardPattern'
import { WorkspacePattern } from './WorkspacePattern'

export type PatternSectionDef = {
  id: string
  title: string
  description?: string
  component: ComponentType
}

export const patternSections: PatternSectionDef[] = [
  {
    id: 'pattern-list-index',
    title: 'List / Index',
    description: 'Toolbar, table, pagination, bulk actions.',
    component: ListIndexPattern,
  },
  {
    id: 'pattern-master-detail',
    title: 'Master–Detail',
    description: 'Split list with detail drawer.',
    component: MasterDetailPattern,
  },
  {
    id: 'pattern-editor-form',
    title: 'Editor / Form',
    description: 'Service editor with branch matrix and validation.',
    component: EditorFormPattern,
  },
  {
    id: 'pattern-record-detail',
    title: 'Record Detail',
    description: 'Tabs, description lists, related data.',
    component: RecordDetailPattern,
  },
  {
    id: 'pattern-workspace',
    title: 'Workspace',
    description: 'Multi-pane encounter with dockable AI.',
    component: WorkspacePattern,
  },
  {
    id: 'pattern-calendar-queue',
    title: 'Calendar / Queue',
    description: 'Day schedule and queue board.',
    component: CalendarQueuePattern,
  },
  {
    id: 'pattern-dashboard',
    title: 'Dashboard',
    description: 'Metrics, charts, and detail table.',
    component: DashboardPattern,
  },
  {
    id: 'pattern-wizard',
    title: 'Wizard',
    description: 'Multi-step branch setup.',
    component: WizardPattern,
  },
  {
    id: 'pattern-ai-flow',
    title: 'AI flow',
    description: 'Ask, stream, approve, toast.',
    component: AiFlowPattern,
  },
  {
    id: 'pattern-state-gallery',
    title: 'State gallery',
    description: 'Loading, empty, error, access, degraded.',
    component: StateGalleryPattern,
  },
]
