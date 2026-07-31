import { Skeleton } from '@/components/skeleton'
import { Avatar } from '@/components/avatar'
import {
  ShowcaseDemo,
  ShowcaseDemoGrid,
  ShowcaseSection,
} from '../../ShowcasePrimitives'

export function SkeletonShowcase() {
  return (
    <ShowcaseSection
      id="skeleton"
      title="Skeleton"
      description="Shape-matched placeholders with calm shimmer; static under reduced motion."
      componentName="Skeleton"
    >
      <ShowcaseDemoGrid>
        <ShowcaseDemo label="Variants" propsHint='variant="text|circular|rectangular"'>
          <Skeleton variant="text" className="max-w-xs" />
          <Skeleton variant="circular" width={40} height={40} />
          <Skeleton variant="rectangular" width={120} height={80} />
        </ShowcaseDemo>

        <ShowcaseDemo label="List row layout" propsHint="composed">
          <div className="flex w-full max-w-sm items-center gap-3">
            <Skeleton variant="circular" width={32} height={32} />
            <div className="flex-1 space-y-2">
              <Skeleton variant="text" className="w-3/4" />
              <Skeleton variant="text" className="w-1/2" />
            </div>
          </div>
        </ShowcaseDemo>

        <ShowcaseDemo label="Card layout" propsHint="composed">
          <div className="w-full max-w-xs space-y-3 rounded-lg border border-border-subtle p-4">
            <Skeleton variant="rectangular" height={96} className="w-full" />
            <Skeleton variant="text" />
            <Skeleton variant="text" className="w-2/3" />
          </div>
        </ShowcaseDemo>

        <ShowcaseDemo label="Contrast with loaded avatar" propsHint="loading → loaded">
          <Skeleton variant="circular" width={32} height={32} />
          <Avatar name="Sara Hassan" size="md" />
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
