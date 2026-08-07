import type { CSSProperties, ReactNode } from "react";
import type { FieldDef } from "@/catalog";

type FieldControlProps = {
  field: FieldDef;
  value: string;
  onChange: (value: string) => void;
};

const controlStyle: CSSProperties = {
  width: "100%",
  padding: "8px 10px",
  border: "1px solid var(--rule)",
  background: "var(--chalk)",
  color: "var(--ink)",
  borderRadius: 0,
};

export function FieldControl({ field, value, onChange }: FieldControlProps) {
  const id = `field-${field.name}`;

  const label = (
    <label
      htmlFor={id}
      style={{
        display: "block",
        marginBottom: 4,
        fontSize: 13,
        fontWeight: 500,
        color: "var(--ink)",
      }}
    >
      {field.label}
      {field.required && (
        <span style={{ color: "var(--warn)", marginLeft: 2 }}>*</span>
      )}
    </label>
  );

  const help = field.help ? (
    <p style={{ margin: "4px 0 0", fontSize: 12, color: "var(--steel)" }}>
      {field.help}
    </p>
  ) : null;

  let control: ReactNode;

  switch (field.kind) {
    case "checkbox":
      control = (
        <label
          style={{
            display: "flex",
            alignItems: "center",
            gap: 8,
            cursor: "pointer",
          }}
        >
          <input
            id={id}
            type="checkbox"
            checked={value === "true"}
            onChange={(e) => onChange(e.target.checked ? "true" : "false")}
          />
          <span style={{ fontSize: 13, color: "var(--steel)" }}>
            {value === "true" ? "true" : "false"}
          </span>
        </label>
      );
      break;

    case "select":
      control = (
        <select
          id={id}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          style={controlStyle}
        >
          {(field.options ?? []).map((opt) => (
            <option key={opt.value} value={opt.value}>
              {opt.label}
            </option>
          ))}
        </select>
      );
      break;

    case "textarea":
    case "json":
      control = (
        <textarea
          id={id}
          className={field.kind === "json" ? "ops-mono" : undefined}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={field.placeholder}
          rows={field.kind === "json" ? 6 : 4}
          style={{
            ...controlStyle,
            minHeight: field.kind === "json" ? 120 : undefined,
            resize: "vertical",
            fontFamily:
              field.kind === "json" ? "var(--font-mono)" : undefined,
          }}
        />
      );
      break;

    case "text":
    case "password":
    case "number":
      control = (
        <input
          id={id}
          className="ops-mono"
          type={field.kind === "number" ? "number" : field.kind}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={field.placeholder}
          style={controlStyle}
          autoComplete="off"
          spellCheck={false}
        />
      );
      break;
  }

  return (
    <div style={{ marginBottom: 16 }}>
      {field.kind !== "checkbox" && label}
      {control}
      {help}
    </div>
  );
}
