import { useEffect, useState } from "react";
import type { EntityDef } from "@/catalog";
import type { ConnectionConfig } from "@/lib/connection";
import { runBuiltRequest, type OpsRunResult } from "@/lib/api";
import { FieldControl } from "@/components/FieldControl";

type EntityFormProps = {
  entity: EntityDef;
  connection: ConnectionConfig;
  onResult: (result: OpsRunResult | { error: string }) => void;
  /** Optional overrides applied on top of field defaults / fromConnection */
  seedValues?: Record<string, string>;
};

function buildInitialValues(
  entity: EntityDef,
  connection: ConnectionConfig,
  seedValues?: Record<string, string>,
): Record<string, string> {
  const values: Record<string, string> = {};
  for (const field of entity.fields) {
    if (field.defaultValue !== undefined) {
      values[field.name] = String(field.defaultValue);
    } else if (field.kind === "checkbox") {
      values[field.name] = "false";
    } else {
      values[field.name] = "";
    }
    if (field.fromConnection && !values[field.name]) {
      values[field.name] = connection[field.fromConnection];
    }
    if (seedValues?.[field.name] !== undefined) {
      values[field.name] = seedValues[field.name]!;
    }
  }
  return values;
}

export function EntityForm({
  entity,
  connection,
  onResult,
  seedValues,
}: EntityFormProps) {
  const [values, setValues] = useState(() =>
    buildInitialValues(entity, connection, seedValues),
  );
  const [confirmText, setConfirmText] = useState("");
  const [running, setRunning] = useState(false);

  useEffect(() => {
    setValues(buildInitialValues(entity, connection, seedValues));
    setConfirmText("");
    setRunning(false);
    // Re-seed when the entity or seed map identity changes (setup step forms).
    // eslint-disable-next-line react-hooks/exhaustive-deps -- connection re-seed handled below
  }, [entity.id, seedValues]);

  useEffect(() => {
    setValues((prev) => {
      const next = { ...prev };
      for (const field of entity.fields) {
        if (field.fromConnection) {
          next[field.name] = connection[field.fromConnection];
        }
      }
      return next;
    });
  }, [
    connection.platformBaseUrl,
    connection.operatorBearer,
    connection.aat,
    entity.id,
    entity.fields,
  ]);

  const updateField = (name: string, value: string) => {
    setValues((prev) => ({ ...prev, [name]: value }));
  };

  const confirmOk = !entity.dangerous || confirmText === entity.id;
  const canRun = confirmOk && !running;

  const handleRun = async () => {
    if (!canRun) return;
    setRunning(true);
    try {
      const built = entity.buildRequest(values);
      const result = await runBuiltRequest(built, connection);
      onResult(result);
    } catch (err) {
      onResult({
        error: err instanceof Error ? err.message : String(err),
      });
    } finally {
      setRunning(false);
    }
  };

  return (
    <div>
      <div style={{ marginBottom: 20 }}>
        <h2
          style={{
            margin: "0 0 4px",
            fontSize: 18,
            fontWeight: 600,
            color: "var(--ink)",
          }}
        >
          {entity.title}
        </h2>
        <p style={{ margin: 0, fontSize: 13, color: "var(--steel)" }}>
          {entity.description}
        </p>
        <p
          className="ops-mono"
          style={{ margin: "6px 0 0", fontSize: 11, color: "var(--steel)" }}
        >
          {entity.id} · {entity.mode}
        </p>
      </div>

      {entity.fields.map((field) => (
        <FieldControl
          key={field.name}
          field={field}
          value={values[field.name] ?? ""}
          onChange={(v) => updateField(field.name, v)}
        />
      ))}

      {entity.dangerous && (
        <div style={{ marginBottom: 16 }}>
          <label
            htmlFor="danger-confirm"
            style={{
              display: "block",
              marginBottom: 4,
              fontSize: 13,
              fontWeight: 500,
              color: "var(--warn)",
            }}
          >
            Type <span className="ops-mono">{entity.id}</span> to confirm
          </label>
          <input
            id="danger-confirm"
            className="ops-mono"
            type="text"
            value={confirmText}
            onChange={(e) => setConfirmText(e.target.value)}
            style={{
              width: "100%",
              padding: "8px 10px",
              border: "1px solid var(--rule)",
              background: "var(--chalk)",
              color: "var(--ink)",
            }}
            autoComplete="off"
            spellCheck={false}
          />
        </div>
      )}

      <button
        type="button"
        onClick={() => void handleRun()}
        disabled={!canRun}
        style={{
          padding: "10px 24px",
          border: "none",
          background: entity.dangerous ? "var(--warn)" : "var(--teal)",
          color: "#fff",
          fontWeight: 600,
          fontSize: 14,
          cursor: canRun ? "pointer" : "not-allowed",
          opacity: canRun ? 1 : 0.55,
        }}
      >
        {running
          ? "Running…"
          : entity.dangerous
            ? "Run (dangerous)"
            : "Run"}
      </button>
    </div>
  );
}
