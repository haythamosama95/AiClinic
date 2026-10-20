import { canonicalize, sha256Hex } from "vendor-contracts";

const MAX_FACT_JSON_BYTES = 32_000;
const encoder = new TextEncoder();
const decoder = new TextDecoder();

export type CommandFactKind =
  | "command_intent"
  | "relay_reserved"
  | "platform_result"
  | "local_result"
  | "erasure_ack";

export type CommandFactEnv = { DB: D1Database };

export type StoredCommandFact = {
  fact_id: string;
  command_id: string;
  fact_kind: CommandFactKind;
  payload_json: string;
  payload_sha256: string;
  created_at: string;
};

function decodeBase64UrlJson(segment: string): unknown | null {
  if (!/^[A-Za-z0-9_-]+$/u.test(segment)) return null;
  const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  try {
    const binary = atob(base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4));
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(
      Uint8Array.from(binary, (char) => char.charCodeAt(0)),
    )) as unknown;
  } catch {
    return null;
  }
}

function isStructurallyValidTransferReceipt(root: Record<string, unknown>): boolean {
  if (
    root.fact_kind !== "platform_result" ||
    (root.phase !== "transferOut" && root.phase !== "transferIn") ||
    root.provenance !== "authenticated_platform_transfer_step_call" ||
    (root.result !== "applied" && root.result !== "already_applied") ||
    typeof root.response_json !== "string"
  ) return false;
  try {
    const response = JSON.parse(root.response_json) as Record<string, unknown>;
    const receipt = response.receipt;
    if (
      response.result !== root.result || response.contract_version !== root.contract_version ||
      typeof receipt !== "object" || receipt === null || Array.isArray(receipt)
    ) return false;
    const signed = receipt as Record<string, unknown>;
    if (
      signed.result !== "applied" || signed.transfer_id !== root.transfer_id ||
      signed.contract_version !== response.contract_version ||
      typeof signed.signature !== "string" || typeof signed.kid !== "string" ||
      !/^[a-f0-9]{64}$/u.test(String(signed.envelope_sha256 ?? "")) ||
      !Number.isSafeInteger(signed.ledger_seq) || Number(signed.ledger_seq) <= 0 ||
      typeof signed.applied_at !== "string" || !Number.isSafeInteger(Date.parse(signed.applied_at)) ||
      !Array.isArray(signed.term_ids) ||
      !signed.term_ids.every((termId) => typeof termId === "string" && termId.length > 0)
    ) return false;
    const [headerSegment, payloadSegment, signatureSegment, extra] = signed.signature.split(".");
    if (!headerSegment || !payloadSegment || !signatureSegment || extra !== undefined ||
        !/^[A-Za-z0-9_-]{86}$/u.test(signatureSegment)) return false;
    const header = decodeBase64UrlJson(headerSegment);
    const payload = decodeBase64UrlJson(payloadSegment);
    const withoutSignature = { ...signed };
    delete withoutSignature.signature;
    return typeof header === "object" && header !== null && !Array.isArray(header) &&
      (header as Record<string, unknown>).alg === "EdDSA" &&
      (header as Record<string, unknown>).kid === signed.kid &&
      new TextDecoder().decode(canonicalize(header)) ===
        new TextDecoder().decode(canonicalize({ alg: "EdDSA", kid: signed.kid })) &&
      typeof payload === "object" && payload !== null && !Array.isArray(payload) &&
      new TextDecoder().decode(canonicalize(payload)) ===
        new TextDecoder().decode(canonicalize(withoutSignature));
  } catch {
    return false;
  }
}

export function hasForbiddenCommandFactSecret(value: unknown, factKind?: string): boolean {
  const candidate = typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
  const root = factKind === undefined ? candidate : { ...candidate, fact_kind: factKind };
  const allowedReceiptSignature = isStructurallyValidTransferReceipt(root);
  const visit = (item: unknown, path: string[]): boolean => {
    if (Array.isArray(item)) return item.some((entry, index) => visit(entry, [...path, String(index)]));
    if (typeof item === "string") {
      const text = item.trim();
      if (/^Bearer\s+\S+/iu.test(text)) return true;
      if (/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/u.test(text)) {
        return !(allowedReceiptSignature && path.join(".") === "response_json.receipt.signature");
      }
      if ((text.startsWith("{") && text.endsWith("}")) || (text.startsWith("[") && text.endsWith("]"))) {
        try { return visit(JSON.parse(text) as unknown, path); } catch { return false; }
      }
      return false;
    }
    if (typeof item !== "object" || item === null) return false;
    for (const [key, nested] of Object.entries(item)) {
      if (/^(access_jwt|jwt|client_secret|email|phone|name|contact|signed_operation_json|signed_assertion_json)$/iu.test(key)) {
        return true;
      }
      if (visit(nested, [...path, key])) return true;
    }
    return false;
  };
  return visit(value, []);
}

export async function commandFactStatements(
  env: CommandFactEnv,
  input: {
    commandId: string;
    kind: CommandFactKind;
    payload: Record<string, unknown>;
    createdAt: string;
  },
): Promise<D1PreparedStatement[]> {
  if (
    input.commandId.length === 0 || input.commandId.length > 160 ||
    !Number.isSafeInteger(Date.parse(input.createdAt)) ||
    hasForbiddenCommandFactSecret(input.payload, input.kind)
  ) {
    throw new Error("command_recovery_fact_invalid");
  }
  const payloadJson = decoder.decode(canonicalize(input.payload));
  if (encoder.encode(payloadJson).length > MAX_FACT_JSON_BYTES) {
    throw new Error("command_recovery_fact_too_large");
  }
  const payloadSha256 = await sha256Hex(canonicalize(input.payload));
  const factId = await sha256Hex(canonicalize({
    command_id: input.commandId,
    fact_kind: input.kind,
    payload_sha256: payloadSha256,
  }));
  const canonicalRow = {
    fact_id: factId,
    command_id: input.commandId,
    fact_kind: input.kind,
    payload_json: payloadJson,
    payload_sha256: payloadSha256,
    created_at: input.createdAt,
  };
  const rowJson = decoder.decode(canonicalize(canonicalRow));
  const rowSha256 = await sha256Hex(canonicalize(canonicalRow));
  return [
    env.DB.prepare(
      `INSERT INTO command_recovery_fact (
         fact_id, command_id, fact_kind, payload_json, payload_sha256, created_at
       ) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(fact_id) DO NOTHING`,
    ).bind(factId, input.commandId, input.kind, payloadJson, payloadSha256, input.createdAt),
    env.DB.prepare(
      `INSERT INTO fact_log ("table", key, row_sha256, row_json, created_at)
       SELECT 'command_recovery_fact', ?, ?, ?, ?
       WHERE EXISTS (SELECT 1 FROM command_recovery_fact WHERE fact_id = ?)
         AND NOT EXISTS (
           SELECT 1 FROM fact_log WHERE "table" = 'command_recovery_fact' AND key = ?
         )`,
    ).bind(factId, rowSha256, rowJson, input.createdAt, factId, factId),
  ];
}

export async function readCommandFact(
  env: CommandFactEnv,
  commandId: string,
  kind: CommandFactKind,
  payloadFilter?: Record<string, string>,
): Promise<{ row: StoredCommandFact; payload: Record<string, unknown> } | null> {
  const filters = Object.entries(payloadFilter ?? {});
  if (filters.some(([field]) => !/^[A-Za-z0-9_]+$/u.test(field))) {
    throw new Error("command_recovery_fact_filter_invalid");
  }
  const filterSql = filters.map(() => " AND json_extract(payload_json, ?) = ?").join("");
  const row = await env.DB.prepare(
    `SELECT fact_id, command_id, fact_kind, payload_json, payload_sha256, created_at
     FROM command_recovery_fact
     WHERE command_id = ? AND fact_kind = ?
       ${filterSql}
     ORDER BY created_at ASC, fact_id ASC LIMIT 1`,
  ).bind(
    commandId,
    kind,
    ...filters.flatMap(([field, value]) => [`$.${field}`, value]),
  ).first<StoredCommandFact>();
  if (row === null) return null;
  const payload = JSON.parse(row.payload_json) as Record<string, unknown>;
  if (
    decoder.decode(canonicalize(payload)) !== row.payload_json ||
    await sha256Hex(canonicalize(payload)) !== row.payload_sha256 ||
    hasForbiddenCommandFactSecret(payload, row.fact_kind)
  ) {
    throw new Error("command_recovery_fact_corrupt");
  }
  const expectedFactId = await sha256Hex(canonicalize({
    command_id: row.command_id,
    fact_kind: row.fact_kind,
    payload_sha256: row.payload_sha256,
  }));
  const canonicalRow = {
    fact_id: row.fact_id,
    command_id: row.command_id,
    fact_kind: row.fact_kind,
    payload_json: row.payload_json,
    payload_sha256: row.payload_sha256,
    created_at: row.created_at,
  };
  const factLog = await env.DB.prepare(
    `SELECT row_sha256, row_json FROM fact_log
     WHERE "table" = 'command_recovery_fact' AND key = ?`,
  ).bind(row.fact_id).first<{ row_sha256: string; row_json: string }>();
  if (
    expectedFactId !== row.fact_id || factLog === null ||
    factLog.row_json !== decoder.decode(canonicalize(canonicalRow)) ||
    factLog.row_sha256 !== await sha256Hex(canonicalize(canonicalRow))
  ) {
    throw new Error("command_recovery_fact_lineage_invalid");
  }
  return { row, payload };
}

export function safeResultPayload(
  value: Record<string, unknown>,
): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const key of ["result", "code", "contract_version", "detail", "receipt"]) {
    if (Object.hasOwn(value, key)) result[key] = value[key];
  }
  return result;
}
