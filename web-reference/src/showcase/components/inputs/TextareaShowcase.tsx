import { useId } from 'react'
import { FormField, Textarea } from '@/components/ui'
import { ShowcaseDemo, ShowcaseDemoGrid, ShowcaseSection } from '../../ShowcasePrimitives'

export function TextareaShowcase() {
  const id = useId()
  return (
    <ShowcaseSection id="textarea" title="Textarea" componentName="Textarea">
      <ShowcaseDemoGrid>
        <FormField id={id} label="Clinical notes" helperText="Visible to care team only.">
          <Textarea id={id} placeholder="Document findings and plan…" rows={4} />
        </FormField>
        <ShowcaseDemo label="Auto-grow + counter" propsHint="autoGrow showCounter maxLength">
          <Textarea
            autoGrow
            showCounter
            maxLength={200}
            defaultValue="Auto-growing textarea with character counter."
            className="w-full"
          />
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
