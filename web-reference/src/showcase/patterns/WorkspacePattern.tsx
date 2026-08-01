import { useState } from 'react'
import { Button } from '@/components/actions/Button'
import { PatientCard } from '@/components/card/EntityCards'
import { ResizablePanels } from '@/components/resizable/ResizablePanels'
import { SectionHeader } from '@/components/layout/SectionHeader'
import { AiPanel } from '@/components/ai/AiPanel'
import { Textarea } from '@/components/ui/textarea/Textarea'
import { IconButton } from '@/components/actions/IconButton'
import { PanelRightClose, PanelRightOpen } from 'lucide-react'
import { ShowcaseSection } from '../ShowcasePrimitives'
import { PatternFrame } from './PatternFrame'

export function WorkspacePattern() {
  const [aiOpen, setAiOpen] = useState(true)

  return (
    <ShowcaseSection
      id="pattern-workspace"
      title="Workspace"
      componentName="05 §2 Workspace"
      description="Multi-pane encounter layout with patient context, SOAP notes, and dockable AI panel."
    >
      <PatternFrame minHeight="480px">
        <div className="flex h-[480px] flex-col">
          <div className="flex items-center justify-between border-b border-border-subtle px-4 py-2">
            <p className="text-body-strong text-text-primary">Encounter · Layla Hassan</p>
            <IconButton
              icon={aiOpen ? <PanelRightClose size={18} /> : <PanelRightOpen size={18} />}
              label={aiOpen ? 'Hide AI panel' : 'Show AI panel'}
              size="sm"
              onClick={() => setAiOpen((o) => !o)}
            />
          </div>
          <div className="flex min-h-0 flex-1">
            <ResizablePanels
              defaultStartPercent={22}
              minStartPercent={18}
              maxStartPercent={35}
              className="min-h-0 flex-1"
              start={
                <div className="h-full overflow-y-auto border-e border-border-subtle p-3">
                  <PatientCard
                    name="Layla Hassan"
                    mrn="MRN-10482"
                    phone="+20 100 234 5678"
                    tags={['Follow-up', 'Penicillin allergy']}
                  />
                  <div className="mt-4 space-y-2">
                    <SectionHeader title="Vitals" />
                    <dl className="space-y-1 text-body-sm">
                      <div className="flex justify-between">
                        <dt className="text-text-tertiary">BP</dt>
                        <dd className="tabular-nums text-text-primary">120/80</dd>
                      </div>
                      <div className="flex justify-between">
                        <dt className="text-text-tertiary">HR</dt>
                        <dd className="tabular-nums text-text-primary">72 bpm</dd>
                      </div>
                    </dl>
                  </div>
                </div>
              }
              end={
                <ResizablePanels
                  defaultStartPercent={aiOpen ? 62 : 100}
                  minStartPercent={40}
                  maxStartPercent={aiOpen ? 75 : 100}
                  start={
                    <div className="flex h-full flex-col gap-4 overflow-y-auto p-4">
                      <SectionHeader title="SOAP note" description="Document today's visit." />
                      <div className="space-y-3">
                        {(['Subjective', 'Objective', 'Assessment', 'Plan'] as const).map((section) => (
                          <div key={section}>
                            <label className="text-caption text-text-tertiary">{section}</label>
                            <Textarea
                              rows={2}
                              className="mt-1"
                              defaultValue={
                                section === 'Subjective'
                                  ? 'Patient reports improved symptoms since last visit.'
                                  : ''
                              }
                              aria-label={section}
                            />
                          </div>
                        ))}
                      </div>
                      <div className="flex gap-2">
                        <Button variant="primary" size="sm">Save draft</Button>
                        <Button variant="secondary" size="sm">Sign visit</Button>
                      </div>
                    </div>
                  }
                  end={
                    aiOpen ? (
                      <div className="h-full border-s border-border-subtle p-2">
                        <AiPanel scope="Layla Hassan · Downtown" className="h-full" />
                      </div>
                    ) : (
                      <div className="hidden" aria-hidden />
                    )
                  }
                />
              }
            />
          </div>
        </div>
      </PatternFrame>
    </ShowcaseSection>
  )
}
