export type CategoryId = "setup" | "clinic" | "control" | "debug" | "e2e";

export type FieldKind =
  | "text"
  | "password"
  | "textarea"
  | "json"
  | "number"
  | "select"
  | "checkbox";

export type FieldDef = {
  name: string;
  label: string;
  kind: FieldKind;
  required?: boolean;
  placeholder?: string;
  help?: string;
  options?: { value: string; label: string }[];
  defaultValue?: string | number | boolean;
  /** When true, value comes from connection strip unless overridden */
  fromConnection?: "platformBaseUrl" | "operatorBearer" | "aat";
};

export type EntityMode = "proxy" | "local" | "subprocess";

export type BuiltRequest =
  | {
    mode: "proxy";
    method: string;
    /** Path on the Worker, starting with / */
    path: string;
    headers?: Record<string, string>;
    body?: string;
    auth: "none" | "aat" | "operator";
  }
  | {
    mode: "local";
    /** Local ops handler id */
    handler: string;
    input: Record<string, unknown>;
  }
  | {
    mode: "subprocess";
    script: string;
    args?: string[];
    cwd?: string;
  };

export type EntityDef = {
  id: string;
  category: CategoryId;
  title: string;
  description: string;
  mode: EntityMode;
  dangerous?: boolean;
  fields: FieldDef[];
  buildRequest: (values: Record<string, string>) => BuiltRequest;
};

export const CATEGORIES: {
  id: CategoryId;
  label: string;
  blurb: string;
}[] = [
    {
      id: "setup",
      label: "Setup",
      blurb: "Ordered control steps to configure a working platform.",
    },
    {
      id: "clinic",
      label: "Clinic",
      blurb: "Installation-authenticated client flows (AAT).",
    },
    {
      id: "control",
      label: "Control",
      blurb: "Operator control plane (/control/*).",
    },
    {
      id: "debug",
      label: "Debug",
      blurb: "Internal modules and pure helpers.",
    },
    {
      id: "e2e",
      label: "E2E",
      blurb: "Health, gates, eval, and support lookup.",
    },
  ];

export function parseJsonField(
  raw: string,
  fieldName: string,
): unknown {
  const trimmed = raw.trim();
  if (!trimmed) {
    return undefined;
  }
  try {
    return JSON.parse(trimmed);
  } catch {
    throw new Error(`Field "${fieldName}" must be valid JSON`);
  }
}

export function requireValue(
  values: Record<string, string>,
  name: string,
): string {
  const v = values[name]?.trim() ?? "";
  if (!v) {
    throw new Error(`Field "${name}" is required`);
  }
  return v;
}
