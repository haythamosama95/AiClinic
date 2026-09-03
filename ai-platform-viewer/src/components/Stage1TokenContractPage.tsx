import { useState } from 'react'
import { STAGE1_OPERATIONS } from '@/catalog/stage-1-token-contract'
import type { Stage1OperationId } from '@/catalog/stage-1-token-contract'
import {
  CommandCard,
  CommandDeck,
  StagePage,
  StagePageIntro,
  StagePageSeed,
  stage1CommandTone,
} from '@/components/containers'
import {
  Stage1CommandPanel,
  stage1AuthLabel,
  stage1FieldCount,
} from '@/components/Stage1CommandPanel'

export function Stage1TokenContractPage() {
  const [selectedCommand, setSelectedCommand] = useState<Stage1OperationId | null>(
    null,
  )

  const selectedOperation =
    STAGE1_OPERATIONS.find((operation) => operation.id === selectedCommand) ?? null

  function selectCommand(id: Stage1OperationId) {
    setSelectedCommand((current) => (current === id ? null : id))
  }

  return (
    <StagePage>
      <StagePageIntro
        eyebrow="Stage 1 · Token contract baseline"
        title="Accepted AAT versions"
        lede={
          <>
            The platform keeps a list of accepted AAT <code>ver</code> claims in D1{' '}
            <code>token_contract</code>. Use these control routes to open a rotation
            window or retire an old booklet edition, then probe{' '}
            <code>GET /v1/capabilities</code> with a minted AAT. Clinic{' '}
            <code>ai.aat.ver</code> must be accepted on <code>token_contract</code>{' '}
            — mint syncs that automatically.
          </>
        }
        details={
          <StagePageSeed label="Seed row (after reset)">
            <dl className="stage-page__seed-grid">
              <div>
                <dt>ver</dt>
                <dd>1</dd>
              </div>
              <div>
                <dt>retired_at</dt>
                <dd>null</dd>
              </div>
              <div>
                <dt>changed_by</dt>
                <dd>seed</dd>
              </div>
            </dl>
          </StagePageSeed>
        }
      />

      <CommandDeck
        eyebrow="Token contract commands"
        lede="Pick a command card — its request manifest opens in the panel below."
        ariaLabel="Token contract commands"
        panel={
          selectedOperation ? (
            <Stage1CommandPanel
              key={selectedOperation.id}
              operation={selectedOperation}
              onClose={() => setSelectedCommand(null)}
            />
          ) : null
        }
      >
        {STAGE1_OPERATIONS.map((operation) => (
          <CommandCard
            key={operation.id}
            method={operation.method}
            title={operation.title}
            path={operation.path}
            authLabel={stage1AuthLabel(operation)}
            fieldCount={stage1FieldCount(operation)}
            tone={stage1CommandTone(operation)}
            selected={selectedCommand === operation.id}
            onSelect={() => selectCommand(operation.id)}
          />
        ))}
      </CommandDeck>
    </StagePage>
  )
}
