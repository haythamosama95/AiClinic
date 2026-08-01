import { Send, Sparkles, Square } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/actions/Button'
import { IconButton } from '@/components/actions/IconButton'
import { AiMessageBubble } from './AiMessageBubble'
import { ThinkingIndicator } from './ThinkingIndicator'
import { cn } from '@/lib/cn'
import { Signal } from '@/primitives/Signal'

const SUGGESTED_PROMPTS = [
  'Summarize today\'s appointments',
  'Find patients due for follow-up',
  'Draft a SOAP note template',
]

export type AiPanelProps = {
  scope?: string
  className?: string
}

export function AiPanel({ scope = 'Main branch', className }: AiPanelProps) {
  const [messages, setMessages] = useState<
    { id: string; role: 'user' | 'assistant'; content: string }[]
  >([])
  const [input, setInput] = useState('')
  const [thinking, setThinking] = useState(false)
  const [streaming, setStreaming] = useState(false)

  const send = (text: string) => {
    if (!text.trim()) return
    const userMsg = { id: `u-${Date.now()}`, role: 'user' as const, content: text.trim() }
    setMessages((m) => [...m, userMsg])
    setInput('')
    setThinking(true)

    window.setTimeout(() => {
      setThinking(false)
      setStreaming(true)
      const response =
        'Based on your clinic data, I found 3 patients with follow-ups due this week. I can prepare appointment proposals for your review.'
      setMessages((m) => [
        ...m,
        { id: `a-${Date.now()}`, role: 'assistant', content: response },
      ])
      setStreaming(false)
    }, 1500)
  }

  return (
    <div
      className={cn(
        'flex h-full flex-col rounded-lg border border-border-ai bg-surface-default',
        className,
      )}
    >
      <div className="border-b border-border-subtle px-4 py-3">
        <div className="flex items-center gap-2">
          <Sparkles size={18} className="text-text-ai" aria-hidden />
          <h3 className="text-body-strong text-text-primary">AI assistant</h3>
        </div>
        <p className="mt-1 text-caption text-text-secondary">
          Scope: {scope} · Human approval required for all actions
        </p>
        <div className="mt-2 w-full">
          <Signal variant="ai" orientation="horizontal" thinking={thinking || streaming} />
        </div>
      </div>

      <div className="flex-1 space-y-4 overflow-y-auto p-4">
        {messages.length === 0 ? (
          <div className="space-y-3">
            <p className="text-body-sm text-text-secondary">
              Ask about patients, appointments, or clinic operations.
            </p>
            <div className="flex flex-wrap gap-2">
              {SUGGESTED_PROMPTS.map((prompt) => (
                <Button
                  key={prompt}
                  variant="secondary"
                  size="sm"
                  onClick={() => send(prompt)}
                >
                  {prompt}
                </Button>
              ))}
            </div>
          </div>
        ) : (
          messages.map((msg) => (
            <AiMessageBubble key={msg.id} role={msg.role}>
              {msg.content}
            </AiMessageBubble>
          ))
        )}
        {thinking ? <ThinkingIndicator /> : null}
      </div>

      <form
        className="border-t border-border-subtle p-4"
        onSubmit={(e) => {
          e.preventDefault()
          send(input)
        }}
      >
        <div className="flex gap-2">
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Ask AI…"
            aria-label="AI message input"
            className="focus-ring-ai flex-1 rounded-md border border-border-ai bg-surface-default px-3 py-2 text-body outline-none"
          />
          {thinking ? (
            <IconButton
              icon={<Square size={16} />}
              label="Stop"
              variant="ai"
              onClick={() => setThinking(false)}
            />
          ) : (
            <IconButton
              icon={<Send size={16} />}
              label="Send"
              variant="ai"
              type="submit"
            />
          )}
        </div>
      </form>
    </div>
  )
}
