import { UserMenu } from '@/components/navigation/UserMenu'
import { MOCK_USER } from '@/components/navigation/nav-model'
import { ShowcaseDemo, ShowcaseSection } from '../../ShowcasePrimitives'

export function UserMenuShowcase() {
  return (
    <ShowcaseSection
      id="user-menu"
      title="User menu"
      description="Avatar trigger with profile, theme, language, and sign out."
      componentName="UserMenu"
    >
      <ShowcaseDemo label="Default" propsHint="user + appVersion">
        <UserMenu user={MOCK_USER} appVersion="0.1.0" />
      </ShowcaseDemo>
    </ShowcaseSection>
  )
}
