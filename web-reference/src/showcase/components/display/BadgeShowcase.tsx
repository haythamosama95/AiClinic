import {
  Badge,
  type BadgeColor,
  type BadgeSize,
  type BadgeVariant,
} from '@/components/badge'
import {
  ShowcaseDemo,
  ShowcaseDemoGrid,
  ShowcaseSection,
  ShowcaseVariantMatrix,
} from '../../ShowcasePrimitives'

const VARIANTS: BadgeVariant[] = ['solid', 'soft', 'outline', 'dot']
const COLORS: BadgeColor[] = [
  'neutral',
  'success',
  'warning',
  'danger',
  'info',
  'teal',
  'ai',
]
const SIZES: BadgeSize[] = ['sm', 'md']

const DOMAIN_STATUSES: { label: string; color: BadgeColor }[] = [
  { label: 'Paid', color: 'success' },
  { label: 'Active', color: 'success' },
  { label: 'Confirmed', color: 'success' },
  { label: 'Pending', color: 'warning' },
  { label: 'Draft', color: 'neutral' },
  { label: 'Overdue', color: 'danger' },
  { label: 'Cancelled', color: 'danger' },
  { label: 'In progress', color: 'info' },
  { label: 'AI suggested', color: 'ai' },
]

export function BadgeShowcase() {
  return (
    <ShowcaseSection
      id="badge"
      title="Badge / Status pill"
      description="Status and counts. Always paired with text; dot-only badges need an accessible label."
      componentName="Badge"
    >
      <div className="space-y-8">
        <ShowcaseDemoGrid columns={2}>
          {VARIANTS.map((variant) => (
            <ShowcaseDemo
              key={variant}
              label={`Variant · ${variant}`}
              propsHint={`variant="${variant}"`}
            >
              <ShowcaseVariantMatrix title="Status colors">
                {COLORS.map((color) => (
                  <Badge key={color} variant={variant} color={color} label={color}>
                    {variant === 'dot' ? color : color}
                  </Badge>
                ))}
              </ShowcaseVariantMatrix>
            </ShowcaseDemo>
          ))}
        </ShowcaseDemoGrid>

        <ShowcaseDemo label="Sizes" propsHint='size="sm" | "md"'>
          {SIZES.map((size) => (
            <Badge key={size} size={size} color="success">
              {size}
            </Badge>
          ))}
        </ShowcaseDemo>

        <ShowcaseDemo label="Domain status mapping" propsHint="per 02-tokens">
          {DOMAIN_STATUSES.map(({ label, color }) => (
            <Badge key={label} color={color} variant="soft">
              {label}
            </Badge>
          ))}
        </ShowcaseDemo>

        <ShowcaseDemo label="Dot with accessible label" propsHint='variant="dot" label="Active"'>
          <Badge variant="dot" color="success" label="Active" />
          <Badge variant="dot" color="danger" label="No-show">
            No-show
          </Badge>
        </ShowcaseDemo>
      </div>
    </ShowcaseSection>
  )
}
