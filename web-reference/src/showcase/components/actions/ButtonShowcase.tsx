import { useState } from 'react'
import { Calendar, Plus, Sparkles } from 'lucide-react'
import {
  Button,
  type ButtonSize,
  type ButtonVariant,
} from '@/components/actions'
import { useDirection } from '@/providers/DirectionProvider'
import {
  ShowcaseDemo,
  ShowcaseDemoGrid,
  ShowcaseSection,
  ShowcaseVariantMatrix,
} from '../../ShowcasePrimitives'

const VARIANTS: ButtonVariant[] = [
  'primary',
  'secondary',
  'ghost',
  'danger',
  'ai',
  'link',
]

const SIZES: ButtonSize[] = ['sm', 'md', 'lg']

const COPY = {
  en: {
    addService: 'Add service',
    saveChanges: 'Save changes',
    deleteService: 'Delete service',
    askAi: 'Ask AI',
    viewDetails: 'View details',
    publish: 'Publish',
    saving: 'Saving…',
    addPatient: 'Add patient',
    scheduleView: 'Schedule view',
  },
  ar: {
    addService: 'إضافة خدمة',
    saveChanges: 'حفظ التغييرات',
    deleteService: 'حذف الخدمة',
    askAi: 'اسأل الذكاء الاصطناعي',
    viewDetails: 'عرض التفاصيل',
    publish: 'نشر',
    saving: 'جارٍ الحفظ…',
    addPatient: 'إضافة مريض',
    scheduleView: 'عرض الجدول',
  },
} as const

function labelForVariant(
  variant: ButtonVariant,
  t: (typeof COPY)[keyof typeof COPY],
) {
  switch (variant) {
    case 'primary':
      return t.addService
    case 'secondary':
      return t.saveChanges
    case 'ghost':
      return t.viewDetails
    case 'danger':
      return t.deleteService
    case 'ai':
      return t.askAi
    case 'link':
      return t.viewDetails
  }
}

export function ButtonShowcase() {
  const { locale } = useDirection()
  const t = COPY[locale]
  const [loadingDemo, setLoadingDemo] = useState(false)

  const simulateLoading = () => {
    setLoadingDemo(true)
    window.setTimeout(() => setLoadingDemo(false), 1500)
  }

  return (
    <ShowcaseSection
      id="button"
      title="Button"
      description="Trigger an action. Labels are verbs; one primary per view region. Press scales to 0.98."
      componentName="Button"
    >
      <div className="space-y-8">
        <ShowcaseDemoGrid columns={2}>
          <ShowcaseDemo label="Variants" propsHint='variant · size="md"'>
            <ShowcaseVariantMatrix title="All variants">
              {VARIANTS.map((variant) => (
                <Button
                  key={variant}
                  variant={variant}
                  leadingIcon={
                    variant === 'ai' ? (
                      <Sparkles size={16} />
                    ) : variant === 'primary' ? (
                      <Plus size={16} />
                    ) : undefined
                  }
                >
                  {labelForVariant(variant, t)}
                </Button>
              ))}
            </ShowcaseVariantMatrix>
          </ShowcaseDemo>

          <ShowcaseDemo label="Sizes" propsHint='variant="primary"'>
            <ShowcaseVariantMatrix title="sm · md · lg">
              {SIZES.map((size) => (
                <Button
                  key={size}
                  size={size}
                  leadingIcon={<Plus size={size === 'lg' ? 20 : 16} />}
                >
                  {t.addService}
                </Button>
              ))}
            </ShowcaseVariantMatrix>
          </ShowcaseDemo>
        </ShowcaseDemoGrid>

        <ShowcaseDemoGrid columns={2}>
          <ShowcaseDemo label="Disabled" propsHint="disabled">
            <Button variant="primary" disabled>
              {t.publish}
            </Button>
            <Button variant="secondary" disabled>
              {t.saveChanges}
            </Button>
            <Button variant="danger" disabled>
              {t.deleteService}
            </Button>
          </ShowcaseDemo>

          <ShowcaseDemo label="Loading" propsHint="loading · aria-busy">
            <Button variant="primary" loading>
              {t.saving}
            </Button>
            <Button
              variant="primary"
              loading={loadingDemo}
              onClick={simulateLoading}
            >
              {loadingDemo ? t.saving : t.publish}
            </Button>
          </ShowcaseDemo>

          <ShowcaseDemo label="Error" propsHint="error · aria-invalid">
            <Button variant="primary" error>
              {t.publish}
            </Button>
            <Button variant="secondary" error>
              {t.saveChanges}
            </Button>
          </ShowcaseDemo>

          <ShowcaseDemo label="With icons" propsHint="leadingIcon · trailingIcon">
            <Button variant="primary" leadingIcon={<Plus size={16} />}>
              {t.addPatient}
            </Button>
            <Button variant="secondary" trailingIcon={<Calendar size={16} />}>
              {t.scheduleView}
            </Button>
          </ShowcaseDemo>
        </ShowcaseDemoGrid>
      </div>
    </ShowcaseSection>
  )
}
