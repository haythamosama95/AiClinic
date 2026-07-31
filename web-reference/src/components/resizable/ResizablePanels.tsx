import { useCallback, useRef, useState, type ReactNode } from 'react'
import { cn } from '@/lib/cn'

export type ResizablePanelsProps = {
  start: ReactNode
  end: ReactNode
  defaultStartPercent?: number
  minStartPercent?: number
  maxStartPercent?: number
  className?: string
}

export function ResizablePanels({
  start,
  end,
  defaultStartPercent = 35,
  minStartPercent = 20,
  maxStartPercent = 60,
  className,
}: ResizablePanelsProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const [startPercent, setStartPercent] = useState(defaultStartPercent)
  const dragging = useRef(false)

  const onPointerMove = useCallback(
    (e: PointerEvent) => {
      if (!dragging.current || !containerRef.current) return
      const rect = containerRef.current.getBoundingClientRect()
      const isRtl = document.documentElement.dir === 'rtl'
      const x = isRtl ? rect.right - e.clientX : e.clientX - rect.left
      const pct = (x / rect.width) * 100
      setStartPercent(Math.min(maxStartPercent, Math.max(minStartPercent, pct)))
    },
    [maxStartPercent, minStartPercent],
  )

  const onPointerUp = useCallback(() => {
    dragging.current = false
    document.removeEventListener('pointermove', onPointerMove)
    document.removeEventListener('pointerup', onPointerUp)
  }, [onPointerMove])

  const onPointerDown = (e: React.PointerEvent) => {
    e.preventDefault()
    dragging.current = true
    document.addEventListener('pointermove', onPointerMove)
    document.addEventListener('pointerup', onPointerUp)
  }

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'ArrowLeft') {
      e.preventDefault()
      setStartPercent((p) => Math.max(minStartPercent, p - 2))
    } else if (e.key === 'ArrowRight') {
      e.preventDefault()
      setStartPercent((p) => Math.min(maxStartPercent, p + 2))
    }
  }

  return (
    <div
      ref={containerRef}
      className={cn('flex h-64 overflow-hidden rounded-lg border border-border-default', className)}
    >
      <div className="overflow-auto" style={{ width: `${startPercent}%` }}>
        {start}
      </div>
      <div
        role="separator"
        aria-orientation="vertical"
        aria-valuenow={Math.round(startPercent)}
        aria-valuemin={minStartPercent}
        aria-valuemax={maxStartPercent}
        tabIndex={0}
        onPointerDown={onPointerDown}
        onKeyDown={onKeyDown}
        className="focus-ring z-10 w-1 shrink-0 cursor-col-resize bg-border-default transition-colors hover:bg-border-focus"
      />
      <div className="min-w-0 flex-1 overflow-auto">{end}</div>
    </div>
  )
}
