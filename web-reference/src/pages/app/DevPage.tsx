import { DevLocaleControls } from '@/components/showcase/DevLocaleControls'
import { DevSectionLayout } from '@/components/showcase/DevSectionLayout'
import { FoundationsContent, FoundationsSubNav } from '@/pages/FoundationsPage'
import { ComponentsPage, ComponentsSubNav } from '@/pages/ComponentsPage'
import { PageHeader } from '@/components/layout/PageHeader'
import { Tabs } from '@/components/navigation/Tabs'
import { useHashRoute } from '@/router/useHashRoute'

export type DevSection = 'foundations' | 'components'

export function DevPage({ section }: { section: DevSection }) {
  const { navigate } = useHashRoute()

  return (
    <>
      <PageHeader
        title="Design System"
        description="Foundations, tokens, and component matrices for the AiClinic design reference."
        tabs={
          <Tabs
            items={[
              { id: 'foundations', label: 'Foundations' },
              { id: 'components', label: 'Components' },
            ]}
            value={section}
            onChange={(id) => navigate(`dev/${id}`)}
            aria-label="Design system sections"
          />
        }
      />
      <div className="mt-6">
        <DevLocaleControls />
      </div>
      <div className="mt-8">
        <DevSectionLayout
          nav={section === 'foundations' ? <FoundationsSubNav /> : <ComponentsSubNav />}
        >
          {section === 'foundations' ? (
            <div className="space-y-16">
              <div>
                <p className="text-overline text-text-tertiary">Milestone 1</p>
                <h2 className="text-h2 text-text-primary">Foundations</h2>
                <p className="mt-2 max-w-2xl text-body-lg text-text-secondary">
                  Tokens, typography, spacing, motion, and The Signal.
                </p>
              </div>
              <FoundationsContent />
            </div>
          ) : (
            <ComponentsPage />
          )}
        </DevSectionLayout>
      </div>
    </>
  )
}
