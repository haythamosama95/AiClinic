import { useMemo, useState } from "react";
import { SETUP_STEPS, type SetupStep } from "@/catalog/setup";
import { entityById } from "@/catalog";
import type { ConnectionConfig } from "@/lib/connection";
import type { OpsRunResult } from "@/lib/api";
import { EntityForm } from "@/components/EntityForm";

type SetupGuideProps = {
  connection: ConnectionConfig;
  onResult: (result: OpsRunResult | { error: string }) => void;
};

export function SetupGuide({ connection, onResult }: SetupGuideProps) {
  const [stepId, setStepId] = useState(SETUP_STEPS[0]?.id ?? "");

  const step: SetupStep | undefined = useMemo(
    () => SETUP_STEPS.find((s) => s.id === stepId) ?? SETUP_STEPS[0],
    [stepId],
  );

  const stepIndex = SETUP_STEPS.findIndex((s) => s.id === step?.id);
  const prev = stepIndex > 0 ? SETUP_STEPS[stepIndex - 1] : undefined;
  const next =
    stepIndex >= 0 && stepIndex < SETUP_STEPS.length - 1
      ? SETUP_STEPS[stepIndex + 1]
      : undefined;

  if (!step) {
    return null;
  }

  return (
    <div className="ops-workspace">
      <nav aria-label="Setup steps" className="ops-entity-nav">
        {SETUP_STEPS.map((s) => {
          const isActive = s.id === step.id;
          return (
            <button
              key={s.id}
              type="button"
              onClick={() => setStepId(s.id)}
              style={{
                display: "block",
                width: "100%",
                textAlign: "left",
                padding: "10px 14px",
                border: "none",
                borderLeft: isActive
                  ? "3px solid var(--teal-deep)"
                  : "3px solid transparent",
                background: isActive ? "var(--chalk)" : "transparent",
                color: "var(--ink)",
                cursor: "pointer",
              }}
            >
              <span
                className="ops-mono"
                style={{
                  display: "block",
                  fontSize: 11,
                  color: "var(--steel)",
                  marginBottom: 2,
                }}
              >
                Step {s.order}
              </span>
              <span style={{ display: "block", fontSize: 14, fontWeight: 500 }}>
                {s.title}
              </span>
            </button>
          );
        })}
      </nav>

      <div
        className="ops-fade-in"
        style={{ flex: 1, padding: "20px 24px", overflow: "auto" }}
        key={step.id}
      >
        <p
          className="ops-mono"
          style={{ margin: "0 0 6px", fontSize: 12, color: "var(--teal)" }}
        >
          Setup · step {step.order} of {SETUP_STEPS.length}
        </p>
        <h2
          style={{
            margin: "0 0 8px",
            fontSize: 18,
            fontWeight: 600,
            color: "var(--ink)",
          }}
        >
          {step.title}
        </h2>

        <section style={{ marginBottom: 16 }}>
          <h3
            style={{
              margin: "0 0 4px",
              fontSize: 12,
              fontWeight: 600,
              letterSpacing: "0.04em",
              textTransform: "uppercase",
              color: "var(--steel)",
            }}
          >
            Why this step
          </h3>
          <p style={{ margin: 0, fontSize: 14, color: "var(--ink)", lineHeight: 1.45 }}>
            {step.why}
          </p>
        </section>

        <section style={{ marginBottom: 16 }}>
          <h3
            style={{
              margin: "0 0 4px",
              fontSize: 12,
              fontWeight: 600,
              letterSpacing: "0.04em",
              textTransform: "uppercase",
              color: "var(--steel)",
            }}
          >
            Do this
          </h3>
          <p style={{ margin: 0, fontSize: 14, color: "var(--ink)", lineHeight: 1.45 }}>
            {step.doThis}
          </p>
        </section>

        {step.note ? (
          <section
            style={{
              marginBottom: 20,
              padding: "10px 12px",
              borderLeft: "3px solid var(--rule)",
              background: "var(--chalk)",
            }}
          >
            <h3
              style={{
                margin: "0 0 4px",
                fontSize: 12,
                fontWeight: 600,
                letterSpacing: "0.04em",
                textTransform: "uppercase",
                color: "var(--steel)",
              }}
            >
              Note
            </h3>
            <p style={{ margin: 0, fontSize: 13, color: "var(--ink)", lineHeight: 1.45 }}>
              {step.note}
            </p>
          </section>
        ) : null}

        {step.entityIds.length === 0 ? (
          <p style={{ fontSize: 13, color: "var(--steel)" }}>
            No control to run on this step — continue when ready.
          </p>
        ) : (
          step.entityIds.map((entityId) => {
            const entity = entityById(entityId);
            if (!entity) {
              return (
                <p key={entityId} style={{ color: "var(--warn)", fontSize: 13 }}>
                  Missing entity: {entityId}
                </p>
              );
            }
            return (
              <div
                key={entityId}
                style={{
                  marginBottom: 28,
                  paddingTop: 16,
                  borderTop: "1px solid var(--rule)",
                }}
              >
                <EntityForm
                  entity={entity}
                  connection={connection}
                  onResult={onResult}
                  seedValues={step.fieldSeeds?.[entityId]}
                />
              </div>
            );
          })
        )}

        <div
          style={{
            display: "flex",
            gap: 12,
            marginTop: 24,
            paddingTop: 16,
            borderTop: "1px solid var(--rule)",
          }}
        >
          <button
            type="button"
            disabled={!prev}
            onClick={() => prev && setStepId(prev.id)}
            style={{
              padding: "8px 16px",
              border: "1px solid var(--rule)",
              background: "var(--chalk)",
              color: "var(--ink)",
              cursor: prev ? "pointer" : "not-allowed",
              opacity: prev ? 1 : 0.45,
              fontWeight: 500,
              fontSize: 13,
            }}
          >
            Previous
          </button>
          <button
            type="button"
            disabled={!next}
            onClick={() => next && setStepId(next.id)}
            style={{
              padding: "8px 16px",
              border: "none",
              background: "var(--teal)",
              color: "#fff",
              cursor: next ? "pointer" : "not-allowed",
              opacity: next ? 1 : 0.45,
              fontWeight: 600,
              fontSize: 13,
            }}
          >
            Next step
          </button>
        </div>
      </div>
    </div>
  );
}
