import type { ShowcaseSectionDef } from '../../registry'
import {
  AiMessageBubbleShowcase,
  AiModeToggleShowcase,
  AiPanelShowcase,
  AiSuggestionShowcase,
  ProposedActionCardShowcase,
  ThinkingIndicatorShowcase,
} from './AiShowcase'

export const aiSections: ShowcaseSectionDef[] = [
  { id: 'ai-mode-toggle', title: 'AI mode toggle', group: 'ai', component: AiModeToggleShowcase, status: 'ready' },
  { id: 'ai-panel', title: 'AI panel / chat', group: 'ai', component: AiPanelShowcase, status: 'ready' },
  { id: 'ai-message-bubble', title: 'AI message bubbles', group: 'ai', component: AiMessageBubbleShowcase, status: 'ready' },
  { id: 'proposed-action-card', title: 'Proposed action card', group: 'ai', component: ProposedActionCardShowcase, status: 'ready' },
  { id: 'ai-suggestion', title: 'Inline AI suggestion', group: 'ai', component: AiSuggestionShowcase, status: 'ready' },
  { id: 'thinking-indicator', title: 'Thinking indicator', group: 'ai', component: ThinkingIndicatorShowcase, status: 'ready' },
]
