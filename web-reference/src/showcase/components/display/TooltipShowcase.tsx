import { Info } from 'lucide-react'
import { Tooltip, TooltipProvider } from '@/components/tooltip'
import { Kbd } from '@/components/kbd'
import {
  ShowcaseDemo,
  ShowcaseDemoGrid,
  ShowcaseSection,
} from '../../ShowcasePrimitives'

export function TooltipShowcase() {
  return (
    <ShowcaseSection
      id="tooltip"
      title="Tooltip"
      description="Brief supplementary text on hover or focus. Never holds essential-only information."
      componentName="Tooltip"
    >
      <TooltipProvider>
        <ShowcaseDemoGrid>
          <ShowcaseDemo label="Default" propsHint="delay 400ms">
            <Tooltip content="View patient history">
              <button
                type="button"
                className="focus-ring inline-flex items-center gap-2 rounded-md border border-border-default px-3 py-2 text-body-strong text-text-primary hover:bg-surface-hover"
              >
                <Info size={16} strokeWidth={1.5} aria-hidden />
                Hover or focus me
              </button>
            </Tooltip>
          </ShowcaseDemo>

          <ShowcaseDemo label="With shortcut hint" propsHint="pairs with Kbd">
            <Tooltip
              content={
                <span className="inline-flex items-center gap-2">
                  Open Command Bar <Kbd keys={['⌘', 'K']} />
                </span>
              }
            >
              <button
                type="button"
                className="focus-ring rounded-md bg-action-primary px-3 py-2 text-body-strong text-action-primary-fg hover:bg-action-primary-hover"
              >
                Quick actions
              </button>
            </Tooltip>
          </ShowcaseDemo>

          <ShowcaseDemo label="Placement" propsHint='side="top|bottom|left|right"'>
            {(['top', 'right', 'bottom', 'left'] as const).map((side) => (
              <Tooltip key={side} content={`Tooltip on ${side}`} side={side}>
                <button
                  type="button"
                  className="focus-ring rounded-md border border-border-default px-3 py-1.5 text-body-sm text-text-secondary hover:bg-surface-hover capitalize"
                >
                  {side}
                </button>
              </Tooltip>
            ))}
          </ShowcaseDemo>
        </ShowcaseDemoGrid>
      </TooltipProvider>
    </ShowcaseSection>
  )
}
