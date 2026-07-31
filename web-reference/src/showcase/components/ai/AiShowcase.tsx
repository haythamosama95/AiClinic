import { useState } from 'react'
import { AiModeToggle } from '@/components/navigation/AiModeToggle'
import {
  AiMessageBubble,
  AiPanel,
  AiSuggestion,
  ProposedActionCard,
  ThinkingIndicator,
  type ProposedActionState,
} from '@/components/ai'
import { FormField } from '@/components/ui/form-field/FormField'
import { TextInput } from '@/components/ui/text-input/TextInput'
import {
  ShowcaseDemo,
  ShowcaseSection,
  ShowcaseVariantMatrix,
} from '../../ShowcasePrimitives'

export function AiModeToggleShowcase() {
  return (
    <ShowcaseSection id="ai-mode-toggle" title="AI mode toggle" componentName="AiModeToggle">
      <ShowcaseDemo label="Standard ↔ AI">
        <AiModeToggle />
        <AiModeToggle showLabel={false} />
      </ShowcaseDemo>
    </ShowcaseSection>
  )
}

export function AiPanelShowcase() {
  return (
    <ShowcaseSection id="ai-panel" title="AI panel / chat" componentName="AiPanel">
      <div className="h-[420px] max-w-lg">
        <AiPanel scope="Downtown branch" />
      </div>
    </ShowcaseSection>
  )
}

export function AiMessageBubbleShowcase() {
  return (
    <ShowcaseSection id="ai-message-bubble" title="AI message bubbles" componentName="AiMessageBubble">
      <div className="max-w-lg space-y-4">
        <AiMessageBubble role="user" timestamp="2:14 PM">
          Which patients need follow-up this week?
        </AiMessageBubble>
        <AiMessageBubble role="assistant" timestamp="2:14 PM" onCopy={() => undefined}>
          Three patients have follow-ups due: Layla Hassan, Omar Farouk, and Nadia El-Sayed.
        </AiMessageBubble>
      </div>
    </ShowcaseSection>
  )
}

const PROPOSED_STATES: ProposedActionState[] = [
  'proposed',
  'editing',
  'submitting',
  'approved',
  'rejected',
  'failed',
]

export function ProposedActionCardShowcase() {
  const [activeState, setActiveState] = useState<ProposedActionState>('proposed')

  return (
    <ShowcaseSection
      id="proposed-action-card"
      title="Proposed action card"
      componentName="ProposedActionCard"
      description="Human-gated AI actions. Approve runs the validated backend path."
    >
      <ShowcaseVariantMatrix title="States">
        {PROPOSED_STATES.map((s) => (
          <button
            key={s}
            type="button"
            onClick={() => setActiveState(s)}
            className="focus-ring rounded-md border border-border-default px-2 py-1 text-caption capitalize hover:bg-surface-hover"
          >
            {s}
          </button>
        ))}
      </ShowcaseVariantMatrix>
      <div className="mt-6 max-w-md">
        <ProposedActionCard
          title="Book appointment"
          summary="Schedule a follow-up for Layla Hassan with Dr. Ahmed on Jul 8 at 10:00 AM."
          state={activeState}
          errorMessage={activeState === 'failed' ? 'Doctor is not available at the selected time.' : undefined}
          fields={
            <div className="space-y-3">
              <FormField id="pa-patient" label="Patient">
                <TextInput id="pa-patient" defaultValue="Layla Hassan" readOnly />
              </FormField>
              <FormField id="pa-date" label="Date">
                <TextInput id="pa-date" defaultValue="Jul 8, 2026" />
              </FormField>
              <FormField id="pa-time" label="Time">
                <TextInput id="pa-time" defaultValue="10:00 AM" />
              </FormField>
            </div>
          }
        />
      </div>
    </ShowcaseSection>
  )
}

export function AiSuggestionShowcase() {
  return (
    <ShowcaseSection id="ai-suggestion" title="Inline AI suggestion" componentName="AiSuggestion">
      <AiSuggestion
        message="AI can draft a SOAP note from today's visit summary."
        onAccept={() => undefined}
        onDismiss={() => undefined}
      />
    </ShowcaseSection>
  )
}

export function ThinkingIndicatorShowcase() {
  return (
    <ShowcaseSection id="thinking-indicator" title="Thinking indicator" componentName="ThinkingIndicator">
      <ShowcaseDemo label="Signal pulse">
        <ThinkingIndicator />
      </ShowcaseDemo>
    </ShowcaseSection>
  )
}
