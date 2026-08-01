import { Check, X } from 'lucide-react'
import { ShowcaseSection } from '../ShowcasePrimitives'

type CopyExample = {
  context: string
  good: string
  avoid: string
}

const VOICE_EXAMPLES: CopyExample[] = [
  {
    context: 'Primary button',
    good: 'Add service',
    avoid: 'Submit',
  },
  {
    context: 'Destructive confirmation',
    good: 'Delete service',
    avoid: 'Yes',
  },
  {
    context: 'Empty state',
    good: 'No services yet. Add your first service to start billing.',
    avoid: 'No data found.',
  },
  {
    context: 'Validation error',
    good: 'The promotion must be less than or equal to the effective price.',
    avoid: 'PROMO_EXCEEDS_PRICE',
  },
  {
    context: 'Concurrency conflict',
    good: 'This was changed by someone else. Reload to see the latest version before saving.',
    avoid: 'STALE_SERVICE error.',
  },
  {
    context: 'AI proposal',
    good: 'AI suggests booking a follow-up for Layla Hassan.',
    avoid: 'Appointment booked for Layla Hassan.',
  },
  {
    context: 'AI unavailable',
    good: 'AI is unavailable right now. You can do this manually.',
    avoid: 'Error: AI service down.',
  },
  {
    context: 'Permission denied',
    good: "You don't have permission to do this.",
    avoid: '403 Forbidden',
  },
]

function CopyCard({ label, text, variant }: { label: string; text: string; variant: 'good' | 'avoid' }) {
  const isGood = variant === 'good'
  return (
    <div
      className={
        isGood
          ? 'rounded-lg border border-status-success-border bg-status-success-surface p-4'
          : 'rounded-lg border border-status-danger-border bg-status-danger-surface p-4'
      }
    >
      <div className="mb-2 flex items-center gap-2">
        {isGood ? (
          <Check size={14} className="text-status-success-fg" aria-hidden />
        ) : (
          <X size={14} className="text-status-danger-fg" aria-hidden />
        )}
        <span className="text-overline text-text-tertiary">{label}</span>
      </div>
      <p className="text-body text-text-primary">{text}</p>
    </div>
  )
}

export function VoiceGuidelinesShowcase() {
  return (
    <ShowcaseSection
      id="guidelines-voice"
      title="Voice & content"
      componentName="08-voice-and-content"
      description="Good vs avoid copy for buttons, errors, empties, confirmations, and AI."
    >
      <div className="space-y-8">
        {VOICE_EXAMPLES.map((ex) => (
          <div key={ex.context}>
            <p className="mb-3 text-body-strong text-text-primary">{ex.context}</p>
            <div className="grid gap-4 sm:grid-cols-2">
              <CopyCard label="Use" text={ex.good} variant="good" />
              <CopyCard label="Avoid" text={ex.avoid} variant="avoid" />
            </div>
          </div>
        ))}

        <div className="rounded-lg border border-border-default bg-surface-sunken p-6">
          <h4 className="text-h3 text-text-primary">House rules</h4>
          <ul className="mt-3 list-disc space-y-2 ps-5 text-body text-text-secondary">
            <li>Sentence case everywhere — buttons, titles, labels.</li>
            <li>Verb-first actions: &quot;Save changes&quot;, not &quot;OK&quot;.</li>
            <li>One name per concept: if the button says &quot;Publish&quot;, the toast says &quot;Published&quot;.</li>
            <li>Tabular figures for money, dates, and counts.</li>
            <li>Write whole phrases for translation — no string concatenation.</li>
          </ul>
        </div>
      </div>
    </ShowcaseSection>
  )
}
