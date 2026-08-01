import { Send, Sparkles } from 'lucide-react'
import { useCallback, useState } from 'react'
import { Button } from '@/components/actions/Button'
import { AiMessageBubble } from '@/components/ai/AiMessageBubble'
import { ProposedActionCard } from '@/components/ai/ProposedActionCard'
import { ThinkingIndicator } from '@/components/ai/ThinkingIndicator'
import { FormField } from '@/components/ui/form-field/FormField'
import { TextInput } from '@/components/ui/text-input/TextInput'
import { useToast } from '@/components/toast/Toast'
import { ShowcaseSection } from '../ShowcasePrimitives'
import { PatternFrame } from './PatternFrame'

type FlowPhase = 'idle' | 'thinking' | 'streaming' | 'proposed' | 'approved'

export function AiFlowPattern() {
  const { toast } = useToast()
  const [phase, setPhase] = useState<FlowPhase>('idle')
  const [query, setQuery] = useState('')
  const [streamText, setStreamText] = useState('')
  const [messages, setMessages] = useState<{ role: 'user' | 'assistant'; content: string }[]>([])

  const fullResponse =
    'I found 3 patients with follow-ups due this week. I can prepare an appointment proposal for Layla Hassan — would you like me to draft it?'

  const runFlow = useCallback(
    (text: string) => {
      if (!text.trim()) return
      setMessages([{ role: 'user', content: text.trim() }])
      setQuery('')
      setPhase('thinking')
      setStreamText('')

      window.setTimeout(() => {
        setPhase('streaming')
        let i = 0
        const interval = window.setInterval(() => {
          i += 3
          setStreamText(fullResponse.slice(0, i))
          if (i >= fullResponse.length) {
            window.clearInterval(interval)
            setMessages((m) => [...m, { role: 'assistant', content: fullResponse }])
            window.setTimeout(() => setPhase('proposed'), 400)
          }
        }, 30)
      }, 1200)
    },
    [fullResponse],
  )

  const handleApprove = () => {
    setPhase('approved')
    toast({
      variant: 'success',
      message: 'Appointment booked for Layla Hassan on Jul 8 at 10:00 AM.',
    })
  }

  const reset = () => {
    setPhase('idle')
    setMessages([])
    setStreamText('')
    setQuery('')
  }

  return (
    <ShowcaseSection
      id="pattern-ai-flow"
      title="AI flow end-to-end"
      componentName="05 §10 AI interaction"
      description="Ask → stream → Proposed Action Card → human Approve → success toast."
    >
      <PatternFrame minHeight="520px">
        <div className="flex h-full flex-col">
          <div className="border-b border-border-ai bg-surface-ai px-4 py-3">
            <div className="flex items-center gap-2">
              <Sparkles size={16} className="text-text-ai" aria-hidden />
              <span className="text-body-strong text-text-primary">AI assistant</span>
            </div>
            <p className="mt-1 text-caption text-text-secondary">
              Proposals require your approval before anything is saved.
            </p>
          </div>

          <div className="flex-1 space-y-4 overflow-y-auto p-4">
            {messages.map((msg, i) => (
              <AiMessageBubble
                key={i}
                role={msg.role}
                timestamp="2:14 PM"
              >
                {msg.content}
              </AiMessageBubble>
            ))}

            {phase === 'streaming' && streamText ? (
              <AiMessageBubble role="assistant" timestamp="2:14 PM">
                {streamText}
                <span className="animate-pulse text-text-ai">▋</span>
              </AiMessageBubble>
            ) : null}

            {phase === 'thinking' ? <ThinkingIndicator label="Thinking…" /> : null}

            {phase === 'proposed' || phase === 'approved' ? (
              <ProposedActionCard
                title="Book appointment"
                summary="Schedule a follow-up for Layla Hassan with Dr. Ahmed on Jul 8 at 10:00 AM."
                state={phase === 'approved' ? 'approved' : 'proposed'}
                onApprove={handleApprove}
                fields={
                  <div className="space-y-3">
                    <FormField id="flow-patient" label="Patient">
                      <TextInput id="flow-patient" defaultValue="Layla Hassan" readOnly />
                    </FormField>
                    <FormField id="flow-date" label="Date">
                      <TextInput id="flow-date" defaultValue="Jul 8, 2026" />
                    </FormField>
                    <FormField id="flow-time" label="Time">
                      <TextInput id="flow-time" defaultValue="10:00 AM" />
                    </FormField>
                  </div>
                }
              />
            ) : null}
          </div>

          <div className="border-t border-border-subtle p-4">
            {phase === 'approved' ? (
              <div className="flex justify-between gap-2">
                <p className="text-body-sm text-text-secondary">Flow complete — check the toast.</p>
                <Button variant="secondary" size="sm" onClick={reset}>
                  Reset demo
                </Button>
              </div>
            ) : (
              <form
                className="flex gap-2"
                onSubmit={(e) => {
                  e.preventDefault()
                  runFlow(query)
                }}
              >
                <TextInput
                  className="flex-1"
                  placeholder="Ask about follow-ups…"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  disabled={phase !== 'idle' && phase !== 'proposed'}
                  aria-label="Ask AI"
                />
                <Button
                  type="submit"
                  variant="ai"
                  leadingIcon={<Send size={16} />}
                  disabled={phase === 'thinking' || phase === 'streaming'}
                >
                  Ask
                </Button>
              </form>
            )}
          </div>
        </div>
      </PatternFrame>
    </ShowcaseSection>
  )
}
