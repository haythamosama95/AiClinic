import { Avatar, AvatarGroup } from '@/components/avatar'
import type { AvatarSize, AvatarStatus } from '@/components/avatar'
import {
  ShowcaseDemo,
  ShowcaseDemoGrid,
  ShowcaseSection,
  ShowcaseVariantMatrix,
} from '../../ShowcasePrimitives'

const SIZES: AvatarSize[] = ['xs', 'sm', 'md', 'lg', 'xl']
const STATUSES: AvatarStatus[] = ['online', 'offline', 'busy', 'away']

const TEAM = [
  { name: 'Sara Hassan', src: undefined },
  { name: 'Omar Khalil', src: undefined },
  { name: 'Layla Nour', src: undefined },
  { name: 'Youssef Ali', src: undefined },
  { name: 'Nadia Farid', src: undefined },
]

export function AvatarShowcase() {
  return (
    <ShowcaseSection
      id="avatar"
      title="Avatar / Group"
      description="Image or initials fallback with optional status dot and stacked groups."
      componentName="Avatar · AvatarGroup"
    >
      <div className="space-y-8">
        <ShowcaseDemo label="Sizes" propsHint='size="xs"…"xl"'>
          <ShowcaseVariantMatrix title="Initials">
            {SIZES.map((size) => (
              <Avatar key={size} name="Sara Hassan" size={size} />
            ))}
          </ShowcaseVariantMatrix>
        </ShowcaseDemo>

        <ShowcaseDemo label="Status dot" propsHint="showStatus">
          {STATUSES.map((status) => (
            <div key={status} className="flex flex-col items-center gap-1">
              <Avatar name="Omar Khalil" showStatus status={status} />
              <span className="text-caption text-text-tertiary">{status}</span>
            </div>
          ))}
        </ShowcaseDemo>

        <ShowcaseDemoGrid>
          <ShowcaseDemo label="Avatar group" propsHint='max={4}'>
            <AvatarGroup max={4} size="md">
              {TEAM.map((member) => (
                <Avatar key={member.name} name={member.name} size="md" />
              ))}
            </AvatarGroup>
          </ShowcaseDemo>

          <ShowcaseDemo label="Deterministic initials color" propsHint="hash from name">
            {TEAM.slice(0, 4).map((member) => (
              <Avatar key={member.name} name={member.name} />
            ))}
          </ShowcaseDemo>
        </ShowcaseDemoGrid>
      </div>
    </ShowcaseSection>
  )
}
