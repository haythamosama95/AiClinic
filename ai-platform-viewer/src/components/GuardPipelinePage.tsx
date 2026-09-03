import { GuardPipelineDiagram } from '@/components/GuardPipelineDiagram'
import { StagePage, StagePageIntro } from '@/components/containers'

export function GuardPipelinePage() {
  return (
    <StagePage accentClass="stage-accent--guard">
      <StagePageIntro
        eyebrow="Reference · Guard pipeline"
        eyebrowClass="stage-accent--guard"
        title="Ten checkpoints before SSE opens"
        lede="The guard runs inside every POST /v1/requests as ten sequential stages in runGuard(). Select a checkpoint to see which data-journey stages unblock it and every taxonomy code it can emit."
      />
      <GuardPipelineDiagram />
    </StagePage>
  )
}
