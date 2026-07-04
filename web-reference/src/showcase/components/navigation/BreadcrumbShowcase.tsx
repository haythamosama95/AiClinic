import { Breadcrumb } from '@/components/navigation/Breadcrumb'
import { ShowcaseDemo, ShowcaseDemoGrid, ShowcaseSection } from '../../ShowcasePrimitives'

export function BreadcrumbShowcase() {
  return (
    <ShowcaseSection
      id="breadcrumb"
      title="Breadcrumb"
      description="Hierarchical wayfinding. The current page is not a link."
      componentName="Breadcrumb"
    >
      <ShowcaseDemoGrid columns={1}>
        <ShowcaseDemo label="Default trail" propsHint="items with href">
          <Breadcrumb
            items={[
              { label: 'Home', href: '#' },
              { label: 'Patients', href: '#' },
              { label: 'Layla Hassan' },
            ]}
          />
        </ShowcaseDemo>
        <ShowcaseDemo label="Long trail (middle truncates on narrow)" propsHint="overflow">
          <Breadcrumb
            items={[
              { label: 'Home', href: '#' },
              { label: 'Billing', href: '#' },
              { label: 'Invoices', href: '#' },
              { label: 'INV-2026-00482' },
            ]}
          />
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
