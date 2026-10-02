const textEncoder = new TextEncoder();

function comparePropertyNames(a: string, b: string): number {
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}

function serializeNumber(value: number): string {
  if (!Number.isFinite(value)) {
    throw new TypeError("Invalid JSON number");
  }
  if (value === 0 || Object.is(value, -0)) {
    return "0";
  }
  return value.toString();
}

function serializeString(value: string): string {
  return JSON.stringify(value);
}

function serializeJsonValue(value: unknown): string {
  if (value === null) {
    return "null";
  }
  if (typeof value === "boolean") {
    return value ? "true" : "false";
  }
  if (typeof value === "number") {
    return serializeNumber(value);
  }
  if (typeof value === "string") {
    return serializeString(value);
  }
  if (Array.isArray(value)) {
    const items = value.map((item) => serializeJsonValue(item));
    return `[${items.join(",")}]`;
  }
  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    const keys = Object.keys(record).sort(comparePropertyNames);
    const members = keys.map(
      (key) => `${serializeString(key)}:${serializeJsonValue(record[key])}`,
    );
    return `{${members.join(",")}}`;
  }
  throw new TypeError("Invalid JSON value");
}

/** RFC 8785 canonical UTF-8 bytes for a JSON value. */
export function canonicalize(value: unknown): Uint8Array {
  return textEncoder.encode(serializeJsonValue(value));
}

/** Lowercase hex SHA-256 over `bytes`. */
export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Buffer.from(digest).toString("hex");
}
