import { Check, Copy } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/actions/Button'
import { cn } from '@/lib/cn'

export type CodeBlockProps = {
  code: string
  language?: string
  className?: string
}

export function CodeBlock({ code, language, className }: CodeBlockProps) {
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    await navigator.clipboard.writeText(code)
    setCopied(true)
    window.setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div
      className={cn(
        'relative rounded-lg border border-border-default bg-surface-sunken',
        className,
      )}
    >
      {language ? (
        <div className="border-b border-border-subtle px-4 py-2">
          <span className="text-caption text-text-tertiary">{language}</span>
        </div>
      ) : null}
      <pre className="overflow-x-auto p-4">
        <code className="text-mono text-text-primary">{code}</code>
      </pre>
      <div className="absolute end-2 top-2">
        <Button
          variant="ghost"
          size="sm"
          onClick={handleCopy}
          leadingIcon={copied ? <Check size={14} /> : <Copy size={14} />}
          aria-label={copied ? 'Copied' : 'Copy code'}
        >
          {copied ? 'Copied' : 'Copy'}
        </Button>
      </div>
    </div>
  )
}
