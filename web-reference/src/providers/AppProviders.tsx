import { useEffect, useState, type ReactNode } from 'react'
import { TooltipProvider } from '@/components/tooltip/Tooltip'
import { AiModeProvider } from './AiModeProvider'
import { CommandBarProvider } from './CommandBarProvider'
import { DensityProvider } from './DensityProvider'
import { DirectionProvider } from './DirectionProvider'
import { ThemeProvider } from './ThemeProvider'

function ReducedMotionSync({ children }: { children: ReactNode }) {
  const [reduced, setReduced] = useState(false)

  useEffect(() => {
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)')
    const update = () => {
      const isReduced = mq.matches
      setReduced(isReduced)
      document.documentElement.dataset.reducedMotion = String(isReduced)
    }
    update()
    mq.addEventListener('change', update)
    return () => mq.removeEventListener('change', update)
  }, [])

  return <div data-reduced-motion={reduced ? 'true' : 'false'}>{children}</div>
}

export function AppProviders({ children }: { children: ReactNode }) {
  return (
    <ThemeProvider>
      <DensityProvider>
        <DirectionProvider>
          <AiModeProvider>
            <CommandBarProvider>
              <TooltipProvider>
                <ReducedMotionSync>{children}</ReducedMotionSync>
              </TooltipProvider>
            </CommandBarProvider>
          </AiModeProvider>
        </DirectionProvider>
      </DensityProvider>
    </ThemeProvider>
  )
}
