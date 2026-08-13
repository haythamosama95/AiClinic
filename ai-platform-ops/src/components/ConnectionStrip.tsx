import { useState } from "react";
import type { CSSProperties } from "react";
import { bootstrapDevCredentials } from "@/lib/api";
import type { ConnectionConfig } from "@/lib/connection";

type ConnectionStripProps = {
  connection: ConnectionConfig;
  onChange: (config: ConnectionConfig) => void;
};

const FIELDS: {
  key: keyof ConnectionConfig;
  label: string;
  type: "text" | "password";
}[] = [
    { key: "platformBaseUrl", label: "Platform URL", type: "text" },
    { key: "operatorBearer", label: "Operator bearer", type: "password" },
    { key: "aat", label: "AAT", type: "password" },
  ];

const inputStyle: CSSProperties = {
  flex: 1,
  minWidth: 0,
  padding: "6px 10px",
  border: "1px solid var(--rule)",
  background: "var(--chalk)",
  color: "var(--ink)",
  borderRadius: 0,
};

const labelStyle: CSSProperties = {
  flexShrink: 0,
  width: 130,
  color: "var(--steel)",
  fontSize: 13,
};

export function ConnectionStrip({ connection, onChange }: ConnectionStripProps) {
  const [bootstrapping, setBootstrapping] = useState(false);
  const [bootstrapMessage, setBootstrapMessage] = useState<string | null>(null);

  const update = (key: keyof ConnectionConfig, value: string) => {
    onChange({ ...connection, [key]: value });
  };

  const handleBootstrap = async () => {
    setBootstrapping(true);
    setBootstrapMessage(null);
    try {
      const result = await bootstrapDevCredentials();
      const next: ConnectionConfig = { ...connection };
      if (result.operatorBearer) {
        next.operatorBearer = result.operatorBearer;
      }
      if (result.aat) {
        next.aat = result.aat;
      }
      onChange(next);

      const parts: string[] = [];
      if (result.notes.length > 0) {
        parts.push(...result.notes);
      }
      if (result.errors.length > 0) {
        parts.push(...result.errors.map((entry) => `Error: ${entry}`));
      }
      setBootstrapMessage(parts.join(" "));
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setBootstrapMessage(`Error: ${message}`);
    } finally {
      setBootstrapping(false);
    }
  };

  return (
    <div style={{ flex: 1, minWidth: 0 }}>
      <div
        style={{
          display: "flex",
          flexWrap: "wrap",
          gap: "12px 24px",
          alignItems: "center",
        }}
      >
        {FIELDS.map(({ key, label, type }) => (
          <label
            key={key}
            style={{
              display: "flex",
              alignItems: "center",
              gap: 10,
              flex: "1 1 220px",
              minWidth: 200,
            }}
          >
            <span style={labelStyle}>{label}</span>
            <input
              className="ops-mono"
              type={type}
              value={connection[key]}
              onChange={(e) => update(key, e.target.value)}
              style={inputStyle}
              autoComplete="off"
              spellCheck={false}
            />
          </label>
        ))}
        <button
          type="button"
          onClick={() => void handleBootstrap()}
          disabled={bootstrapping}
          style={{
            flex: "0 0 auto",
            padding: "7px 14px",
            border: "1px solid var(--teal)",
            background: bootstrapping ? "var(--rule)" : "var(--teal)",
            color: bootstrapping ? "var(--steel)" : "#fff",
            cursor: bootstrapping ? "wait" : "pointer",
            fontSize: 13,
            fontWeight: 500,
          }}
        >
          {bootstrapping ? "Bootstrapping…" : "Bootstrap dev credentials"}
        </button>
      </div>
      {bootstrapMessage ? (
        <p
          style={{
            margin: "8px 0 0",
            fontSize: 12,
            color: bootstrapMessage.startsWith("Error")
              ? "var(--warn)"
              : "var(--steel)",
            lineHeight: 1.4,
          }}
        >
          {bootstrapMessage}
        </p>
      ) : null}
    </div>
  );
}
