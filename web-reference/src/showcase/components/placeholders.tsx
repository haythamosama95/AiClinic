import type { ShowcaseSectionDef } from '../registry'
import { PlaceholderSection } from '../ShowcasePrimitives'

function GroupPlaceholder({ title, slug }: { title: string; slug: string }) {
  return (
    <PlaceholderSection
      title={`${title} — coming soon`}
      message={`Register ${title.toLowerCase()} sections in showcase/components/${slug}/index.ts`}
    />
  )
}

function NavigationPlaceholder() {
  return <GroupPlaceholder title="Navigation" slug="navigation" />
}

function FeedbackPlaceholder() {
  return <GroupPlaceholder title="Feedback & overlays" slug="feedback" />
}

function AiPlaceholder() {
  return <GroupPlaceholder title="AI" slug="ai" />
}

function LayoutPlaceholder() {
  return <GroupPlaceholder title="Layout & utility" slug="layout" />
}

export const navigationSections: ShowcaseSectionDef[] = [
  {
    id: 'navigation-placeholder',
    title: 'Navigation',
    group: 'navigation',
    component: NavigationPlaceholder,
    status: 'placeholder',
  },
]

export const feedbackSections: ShowcaseSectionDef[] = [
  {
    id: 'feedback-placeholder',
    title: 'Feedback & overlays',
    group: 'feedback',
    component: FeedbackPlaceholder,
    status: 'placeholder',
  },
]

export const aiSections: ShowcaseSectionDef[] = [
  {
    id: 'ai-placeholder',
    title: 'AI',
    group: 'ai',
    component: AiPlaceholder,
    status: 'placeholder',
  },
]

export const layoutSections: ShowcaseSectionDef[] = [
  {
    id: 'layout-placeholder',
    title: 'Layout & utility',
    group: 'layout',
    component: LayoutPlaceholder,
    status: 'placeholder',
  },
]
