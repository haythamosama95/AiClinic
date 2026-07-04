import { Button } from '@/components/actions/Button'
import { PageHeader } from '@/components/layout/PageHeader'
import { Breadcrumb } from '@/components/navigation/Breadcrumb'
import { Tabs } from '@/components/navigation/Tabs'
import { useState } from 'react'
import { ShowcaseDemo, ShowcaseSection } from '../../ShowcasePrimitives'

export function PageHeaderShowcase() {
  const [tab, setTab] = useState('overview')

  return (
    <ShowcaseSection
      id="page-header"
      title="Page header"
      description="Title, description, breadcrumb, actions, and tabs slots."
      componentName="PageHeader"
    >
      <ShowcaseDemo label="Full composition" propsHint="title + breadcrumb + actions + tabs">
        <div className="w-full rounded-lg border border-border-default bg-surface-default p-6">
          <PageHeader
            breadcrumb={
              <Breadcrumb
                items={[
                  { label: 'Billing', href: '#' },
                  { label: 'Invoices', href: '#' },
                  { label: 'INV-2026-00482' },
                ]}
              />
            }
            title="Invoice details"
            description="Review line items, payments, and patient responsibility."
            actions={
              <>
                <Button variant="secondary">Download PDF</Button>
                <Button variant="primary">Record payment</Button>
              </>
            }
            tabs={
              <Tabs
                items={[
                  { id: 'overview', label: 'Overview' },
                  { id: 'payments', label: 'Payments' },
                  { id: 'history', label: 'History' },
                ]}
                value={tab}
                onChange={setTab}
              />
            }
          />
        </div>
      </ShowcaseDemo>
    </ShowcaseSection>
  )
}
