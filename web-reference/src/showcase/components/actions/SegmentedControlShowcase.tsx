import { useState } from 'react'
import { LayoutGrid, List } from 'lucide-react'
import { SegmentedControl } from '@/components/actions'
import { useDirection } from '@/providers/DirectionProvider'
import {
  ShowcaseDemo,
  ShowcaseDemoGrid,
  ShowcaseSection,
} from '../../ShowcasePrimitives'

const COPY = {
  en: {
    list: 'List',
    board: 'Board',
    day: 'Day',
    week: 'Week',
    viewMode: 'View mode',
    scheduleView: 'Schedule view',
  },
  ar: {
    list: 'قائمة',
    board: 'لوحة',
    day: 'يوم',
    week: 'أسبوع',
    viewMode: 'وضع العرض',
    scheduleView: 'عرض الجدول',
  },
} as const

export function SegmentedControlShowcase() {
  const { locale } = useDirection()
  const t = COPY[locale]
  const [viewMode, setViewMode] = useState<'list' | 'board'>('list')
  const [scheduleView, setScheduleView] = useState<'day' | 'week'>('day')

  return (
    <ShowcaseSection
      id="segmented-control"
      title="Button group / Segmented control"
      description='Mutually exclusive choice among 2–5 options. role="radiogroup" with arrow-key navigation.'
      componentName="SegmentedControl"
    >
      <ShowcaseDemoGrid columns={2}>
        <ShowcaseDemo label="View mode" propsHint="with icons">
          <SegmentedControl
            aria-label={t.viewMode}
            value={viewMode}
            onChange={setViewMode}
            options={[
              {
                value: 'list',
                label: (
                  <>
                    <List size={14} className="me-1.5 inline" />
                    {t.list}
                  </>
                ),
              },
              {
                value: 'board',
                label: (
                  <>
                    <LayoutGrid size={14} className="me-1.5 inline" />
                    {t.board}
                  </>
                ),
              },
            ]}
          />
        </ShowcaseDemo>

        <ShowcaseDemo label="Size sm" propsHint='size="sm"'>
          <SegmentedControl
            size="sm"
            aria-label={t.scheduleView}
            value={scheduleView}
            onChange={setScheduleView}
            options={[
              { value: 'day', label: t.day },
              { value: 'week', label: t.week },
            ]}
          />
        </ShowcaseDemo>

        <ShowcaseDemo label="With disabled option">
          <SegmentedControl
            aria-label={t.viewMode}
            value="list"
            onChange={() => undefined}
            options={[
              { value: 'list', label: t.list },
              { value: 'board', label: t.board, disabled: true },
            ]}
          />
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
