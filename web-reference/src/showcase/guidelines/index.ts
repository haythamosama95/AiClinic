export { VoiceGuidelinesShowcase } from './VoiceGuidelinesShowcase'
export { AccessibilityGuidelinesShowcase } from './AccessibilityGuidelinesShowcase'

import { VoiceGuidelinesShowcase } from './VoiceGuidelinesShowcase'
import { AccessibilityGuidelinesShowcase } from './AccessibilityGuidelinesShowcase'

export type GuidelineSectionDef = {
  id: string
  title: string
  component: typeof VoiceGuidelinesShowcase | typeof AccessibilityGuidelinesShowcase
}

export const guidelineSections: GuidelineSectionDef[] = [
  { id: 'guidelines-voice', title: 'Voice & content', component: VoiceGuidelinesShowcase },
  { id: 'guidelines-focus', title: 'Accessibility', component: AccessibilityGuidelinesShowcase },
]
