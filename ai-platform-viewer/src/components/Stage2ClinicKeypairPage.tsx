import { useState } from 'react'
import { STAGE2_OPERATIONS } from '@/catalog/stage-2-clinic-keypair'
import type { Stage2OperationId } from '@/catalog/stage-2-clinic-keypair'
import {
  CommandCard,
  CommandDeck,
  StagePage,
  StagePageIntro,
  StagePageSeed,
} from '@/components/containers'
import {
  Stage2CommandPanel,
  stage2FieldCount,
} from '@/components/Stage2CommandPanel'

export function Stage2ClinicKeypairPage() {
  const [selectedCommand, setSelectedCommand] = useState<Stage2OperationId | null>(
    null,
  )

  const selectedOperation =
    STAGE2_OPERATIONS.find((operation) => operation.id === selectedCommand) ?? null

  function selectCommand(id: Stage2OperationId) {
    setSelectedCommand((current) => (current === id ? null : id))
  }

  return (
    <StagePage accentClass="stage-page--clinic">
      <StagePageIntro
        eyebrow="Stage 2 · Clinic keypair enrollment"
        eyebrowClass="stage-page__eyebrow--clinic"
        title="Signing stamp in clinic Postgres"
        lede={
          <>
            The clinic mints its Ed25519 keypair inside Supabase. The private key
            never leaves the database — only the <code>kid</code>,{' '}
            <code>installation_id</code>, and <code>public_jwk.x</code> travel to
            the platform enroll call in Stage 3. After the first enroll, operators
            rotate keys with <code>rotate_installation_key()</code> and revoke old
            keys with <code>revoke_installation_key(kid)</code>.{' '}
            <code>get_ai_availability()</code> is the read-only clinic switch for
            Flutter. These RPCs run against local PostgREST, not the Cloudflare
            gateway.
          </>
        }
        details={
          <StagePageSeed label="Default availability (after reset)" variant="clinic">
            <dl className="stage-page__seed-grid">
              <div>
                <dt>enrolled</dt>
                <dd>false</dd>
              </div>
              <div>
                <dt>platform_base_url</dt>
                <dd>null</dd>
              </div>
              <div>
                <dt>private key</dt>
                <dd>stays in Postgres</dd>
              </div>
            </dl>
          </StagePageSeed>
        }
      />

      <CommandDeck
        eyebrow="Clinic RPC commands"
        lede="Pick a command on the left — its request panel opens on the right."
        ariaLabel="Clinic keypair commands"
        panel={
          selectedOperation ? (
            <Stage2CommandPanel
              key={selectedOperation.id}
              operation={selectedOperation}
              onClose={() => setSelectedCommand(null)}
            />
          ) : null
        }
      >
        {STAGE2_OPERATIONS.map((operation) => (
          <CommandCard
            key={operation.id}
            method="RPC"
            title={operation.title}
            path={operation.path}
            authLabel="Supabase admin"
            fieldCount={stage2FieldCount(operation)}
            tone="lifecycle"
            selected={selectedCommand === operation.id}
            onSelect={() => selectCommand(operation.id)}
          />
        ))}
      </CommandDeck>
    </StagePage>
  )
}
