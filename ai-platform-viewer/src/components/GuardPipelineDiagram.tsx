import { useState } from 'react'
import {
  GUARD_PIPELINE_STAGES,
  type GuardPipelineStage,
  type GuardStageNumber,
} from '@/catalog/guard-pipeline'
import { useSession } from '@/context/SessionContext'

function httpTone(status: number): string {
  if (status === 401 || status === 403) return 'guard-diagram__http--auth'
  if (status === 404) return 'guard-diagram__http--missing'
  if (status === 409) return 'guard-diagram__http--conflict'
  if (status === 413) return 'guard-diagram__http--size'
  if (status === 422) return 'guard-diagram__http--context'
  if (status === 429) return 'guard-diagram__http--limit'
  if (status === 503) return 'guard-diagram__http--disabled'
  return 'guard-diagram__http--server'
}

function GuardDetailPanel({ stage }: { stage: GuardPipelineStage }) {
  const { setActiveSection } = useSession()

  return (
    <div className="guard-diagram__detail" role="region" aria-label={`Guard stage ${stage.guardStage} details`}>
      <header className="guard-diagram__detail-head">
        <p className="guard-diagram__detail-eyebrow">
          Guard stage {stage.guardStage}
          {stage.skippedOnIdempotent ? (
            <span className="guard-diagram__skip-badge">skipped on idempotent replay</span>
          ) : null}
        </p>
        <h3 className="guard-diagram__detail-title">{stage.name}</h3>
        <p className="guard-diagram__detail-check">{stage.check}</p>
        <p className="guard-diagram__detail-module">
          <span>Source</span>
          <code>{stage.module}</code>
        </p>
      </header>

      <section className="guard-diagram__detail-section">
        <h4>Unblocked by</h4>
        <ul className="guard-diagram__prereq-list">
          {stage.prerequisites.map((prereq) => (
            <li key={`${stage.guardStage}-${prereq.stage}`}>
              <button
                type="button"
                className="guard-diagram__prereq-link"
                onClick={() => setActiveSection(prereq.stage)}
              >
                {prereq.label}
              </button>
              <p>{prereq.how}</p>
            </li>
          ))}
        </ul>
      </section>

      <section className="guard-diagram__detail-section">
        <h4>Error codes</h4>
        <ul className="guard-diagram__error-list">
          {stage.errors.map((error) => (
            <li key={`${stage.guardStage}-${error.code}`}>
              <div className="guard-diagram__error-head">
                <code className="guard-diagram__error-code">{error.code}</code>
                <span className={`guard-diagram__http ${httpTone(error.http)}`}>
                  HTTP {error.http}
                </span>
              </div>
              <p className="guard-diagram__error-trigger">{error.trigger}</p>
              {error.paths && error.paths.length > 0 ? (
                <ul className="guard-diagram__error-paths">
                  {error.paths.map((path) => (
                    <li key={path}>
                      <code>{path}</code>
                    </li>
                  ))}
                </ul>
              ) : null}
            </li>
          ))}
        </ul>
      </section>
    </div>
  )
}

export function GuardPipelineDiagram() {
  const [selected, setSelected] = useState<GuardStageNumber>(1)
  const activeStage = GUARD_PIPELINE_STAGES.find((stage) => stage.guardStage === selected)
    ?? GUARD_PIPELINE_STAGES[0]

  return (
    <section className="guard-diagram" aria-label="Guard pipeline checkpoints">
      <header className="guard-diagram__intro">
        <p className="guard-diagram__intro-label">Checkpoint spine</p>
        <p className="guard-diagram__intro-copy">
          Ten sequential gates run inside <code>runGuard()</code> before SSE opens.
          Select a gate to see which journey stages unblock it and every taxonomy code it can emit.
        </p>
      </header>

      <div className="guard-diagram__layout">
        <ol className="guard-diagram__spine" aria-label="Guard stages">
          {GUARD_PIPELINE_STAGES.map((stage, index) => {
            const isSelected = selected === stage.guardStage
            const isLast = index === GUARD_PIPELINE_STAGES.length - 1

            return (
              <li
                key={stage.guardStage}
                className={`guard-diagram__node${isSelected ? ' guard-diagram__node--active' : ''}${isLast ? ' guard-diagram__node--terminal' : ''}`}
              >
                <button
                  type="button"
                  className="guard-diagram__node-button"
                  aria-pressed={isSelected}
                  aria-controls="guard-diagram-detail"
                  onClick={() => setSelected(stage.guardStage)}
                >
                  <span className="guard-diagram__node-index" aria-hidden="true">
                    {String(stage.guardStage).padStart(2, '0')}
                  </span>
                  <span className="guard-diagram__node-body">
                    <span className="guard-diagram__node-name">{stage.shortName}</span>
                    <span className="guard-diagram__node-codes">
                      {stage.errors.map((error) => error.code).join(' · ')}
                    </span>
                  </span>
                  {stage.skippedOnIdempotent ? (
                    <span className="guard-diagram__node-skip" title="Skipped on idempotent replay">
                      ↺
                    </span>
                  ) : null}
                </button>
              </li>
            )
          })}
        </ol>

        <div className="guard-diagram__panel" id="guard-diagram-detail">
          <GuardDetailPanel stage={activeStage} />
        </div>
      </div>

      <footer className="guard-diagram__foot">
        <p>
          Idempotent replay at stage 8 skips journal (9) and compose (10) — the adapter replays the prior terminal outcome.
          SSE <code>accepted</code> is the Stage 10 data-journey boundary; routing runs after that.
        </p>
      </footer>
    </section>
  )
}
