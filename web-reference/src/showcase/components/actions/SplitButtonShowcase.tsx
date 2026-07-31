import { SplitButton } from '@/components/actions'
import { useDirection } from '@/providers/DirectionProvider'
import {
  ShowcaseDemo,
  ShowcaseDemoGrid,
  ShowcaseSection,
} from '../../ShowcasePrimitives'

const COPY = {
  en: {
    exportReport: 'Export report',
    saveChanges: 'Save changes',
    saving: 'Saving…',
    exportCsv: 'Export as CSV',
    exportPdf: 'Export as PDF',
    scheduleReport: 'Schedule report',
    saveDraft: 'Save as draft',
    copyConfig: 'Copy configuration',
  },
  ar: {
    exportReport: 'تصدير التقرير',
    saveChanges: 'حفظ التغييرات',
    saving: 'جارٍ الحفظ…',
    exportCsv: 'تصدير CSV',
    exportPdf: 'تصدير PDF',
    scheduleReport: 'جدولة التقرير',
    saveDraft: 'حفظ كمسودة',
    copyConfig: 'نسخ الإعدادات',
  },
} as const

export function SplitButtonShowcase() {
  const { locale } = useDirection()
  const t = COPY[locale]

  return (
    <ShowcaseSection
      id="split-button"
      title="Split button"
      description="Primary action plus related secondary actions. Chevron opens a motion-fade-scale menu."
      componentName="SplitButton"
    >
      <ShowcaseDemoGrid columns={2}>
        <ShowcaseDemo label="Primary variant" propsHint="variant · items">
          <SplitButton
            label={t.exportReport}
            onPrimaryAction={() => undefined}
            items={[
              { id: 'csv', label: t.exportCsv },
              { id: 'pdf', label: t.exportPdf },
              { id: 'schedule', label: t.scheduleReport },
            ]}
          />
        </ShowcaseDemo>

        <ShowcaseDemo label="Secondary variant">
          <SplitButton
            variant="secondary"
            label={t.saveChanges}
            items={[
              { id: 'draft', label: t.saveDraft },
              { id: 'copy', label: t.copyConfig },
            ]}
          />
        </ShowcaseDemo>

        <ShowcaseDemo label="Disabled" propsHint="disabled">
          <SplitButton
            disabled
            label={t.exportReport}
            items={[{ id: 'csv', label: t.exportCsv }]}
          />
        </ShowcaseDemo>

        <ShowcaseDemo label="Loading" propsHint="loading">
          <SplitButton
            loading
            label={t.saving}
            items={[{ id: 'csv', label: t.exportCsv }]}
          />
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
