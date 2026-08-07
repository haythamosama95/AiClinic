import type { CSSProperties } from "react";
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
  const update = (key: keyof ConnectionConfig, value: string) => {
    onChange({ ...connection, [key]: value });
  };

  return (
    <div
      style={{
        display: "flex",
        flexWrap: "wrap",
        gap: "12px 24px",
        flex: 1,
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
    </div>
  );
}
