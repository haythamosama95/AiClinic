import { useState } from 'react'
import { SearchInput } from '@/components/ui'
import { ShowcaseDemo, ShowcaseDemoGrid, ShowcaseSection } from '../../ShowcasePrimitives'

export function SearchInputShowcase() {
  const [loading, setLoading] = useState(false)
  const [count, setCount] = useState<number | undefined>()

  return (
    <ShowcaseSection
      id="search-input"
      title="Search input"
      componentName="SearchInput"
      description="Debounced search, loading spinner, result count, Esc to clear."
    >
      <ShowcaseDemoGrid>
        <ShowcaseDemo label="Interactive" propsHint="debounceMs=300">
          <SearchInput
            className="w-full max-w-md"
            placeholder="Search patients"
            onValueChange={(q) => {
              setLoading(true)
              window.setTimeout(() => {
                setLoading(false)
                setCount(q ? Math.floor(Math.random() * 20) + 1 : undefined)
              }, 400)
            }}
            loading={loading}
            resultCount={count}
          />
        </ShowcaseDemo>
        <ShowcaseDemo label="States">
          <div className="flex w-full max-w-md flex-col gap-3">
            <SearchInput placeholder="Filter services" />
            <SearchInput disabled placeholder="Disabled" />
            <SearchInput invalid defaultValue="???" />
          </div>
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
