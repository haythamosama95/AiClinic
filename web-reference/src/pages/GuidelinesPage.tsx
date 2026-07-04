import { DevSectionLink } from '@/components/showcase/DevSectionLink'
import { AccessibilityGuidelinesShowcase, VoiceGuidelinesShowcase } from '@/showcase/guidelines'

export function GuidelinesPage() {
  return (
    <div className="space-y-16">
      <div>
        <p className="text-overline text-text-tertiary">Milestone 5</p>
        <h2 className="text-h2 text-text-primary">Content & guidelines</h2>
        <p className="mt-2 max-w-2xl text-body-lg text-text-secondary">
          Voice examples from 08 and accessibility walkthrough from 07 — rendered reference, not prose docs.
        </p>
      </div>

      <nav aria-label="Guideline sections" className="flex flex-wrap gap-2 lg:hidden">
        <DevSectionLink
          sectionId="guidelines-voice"
          className="focus-ring rounded-md px-3 py-1.5 text-body-sm text-text-link hover:bg-surface-hover"
        >
          Voice
        </DevSectionLink>
        <DevSectionLink
          sectionId="guidelines-focus"
          className="focus-ring rounded-md px-3 py-1.5 text-body-sm text-text-link hover:bg-surface-hover"
        >
          Accessibility
        </DevSectionLink>
      </nav>

      <VoiceGuidelinesShowcase />
      <AccessibilityGuidelinesShowcase />
    </div>
  )
}

export function GuidelinesSubNav() {
  return (
    <div>
      <p className="text-overline text-text-tertiary mb-2">Guidelines</p>
      <ul className="space-y-0.5">
        <li>
          <DevSectionLink
            sectionId="guidelines-voice"
            className="focus-ring block rounded-sm py-0.5 text-caption text-text-secondary hover:text-text-link"
          >
            Voice & content
          </DevSectionLink>
        </li>
        <li>
          <DevSectionLink
            sectionId="guidelines-focus"
            className="focus-ring block rounded-sm py-0.5 text-caption text-text-secondary hover:text-text-link"
          >
            Accessibility
          </DevSectionLink>
        </li>
        <li>
          <DevSectionLink
            sectionId="guidelines-contrast"
            className="focus-ring block rounded-sm py-0.5 text-caption text-text-tertiary hover:text-text-link"
          >
            Contrast
          </DevSectionLink>
        </li>
        <li>
          <DevSectionLink
            sectionId="guidelines-keyboard"
            className="focus-ring block rounded-sm py-0.5 text-caption text-text-tertiary hover:text-text-link"
          >
            Keyboard
          </DevSectionLink>
        </li>
        <li>
          <DevSectionLink
            sectionId="guidelines-reduced-motion"
            className="focus-ring block rounded-sm py-0.5 text-caption text-text-tertiary hover:text-text-link"
          >
            Reduced motion
          </DevSectionLink>
        </li>
      </ul>
    </div>
  )
}
