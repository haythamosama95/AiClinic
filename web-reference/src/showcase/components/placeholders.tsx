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

function FeedbackPlaceholder() {
  return <GroupPlaceholder title="Feedback & overlays" slug="feedback" />
}

function AiPlaceholder() {
  return <GroupPlaceholder title="AI" slug="ai" />
}

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
