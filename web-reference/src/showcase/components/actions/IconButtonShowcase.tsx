import { Calendar, Plus, Sparkles, Trash2 } from 'lucide-react'
import { IconButton } from '@/components/actions'
import { useDirection } from '@/providers/DirectionProvider'
import {
  ShowcaseDemo,
  ShowcaseDemoGrid,
  ShowcaseSection,
  ShowcaseVariantMatrix,
} from '../../ShowcasePrimitives'

const COPY = {
  en: {
    addPatient: 'Add patient',
    deleteRow: 'Delete row',
    editAppointment: 'Edit appointment',
    askAi: 'Ask AI',
  },
  ar: {
    addPatient: 'إضافة مريض',
    deleteRow: 'حذف الصف',
    editAppointment: 'تعديل الموعد',
    askAi: 'اسأل الذكاء الاصطناعي',
  },
} as const

export function IconButtonShowcase() {
  const { locale } = useDirection()
  const t = COPY[locale]

  return (
    <ShowcaseSection
      id="icon-button"
      title="Icon button"
      description="Compact actions for toolbars and row actions. aria-label and tooltip required."
      componentName="IconButton"
    >
      <ShowcaseDemoGrid columns={2}>
        <ShowcaseDemo label="Variants" propsHint="ghost · secondary · danger · ai">
          <ShowcaseVariantMatrix title="All variants">
            <IconButton variant="ghost" label={t.addPatient} icon={<Plus size={16} />} />
            <IconButton
              variant="secondary"
              label={t.editAppointment}
              icon={<Calendar size={16} />}
            />
            <IconButton variant="danger" label={t.deleteRow} icon={<Trash2 size={16} />} />
            <IconButton variant="ai" label={t.askAi} icon={<Sparkles size={16} />} />
          </ShowcaseVariantMatrix>
        </ShowcaseDemo>

        <ShowcaseDemo label="Sizes" propsHint="sm · md · lg">
          <IconButton size="sm" label={t.addPatient} icon={<Plus size={16} />} />
          <IconButton size="md" label={t.addPatient} icon={<Plus size={16} />} />
          <IconButton size="lg" label={t.addPatient} icon={<Plus size={20} />} />
        </ShowcaseDemo>

        <ShowcaseDemo label="Disabled" propsHint="disabled">
          <IconButton disabled label={t.deleteRow} icon={<Trash2 size={16} />} />
        </ShowcaseDemo>

        <ShowcaseDemo label="Error" propsHint="error · aria-invalid">
          <IconButton error label={t.deleteRow} icon={<Trash2 size={16} />} />
        </ShowcaseDemo>
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}
