import { canonicalize, sha256Hex } from "vendor-contracts";
import type { BillingClaims } from "./auth.js";
import { clinicErrorResponse, clinicJsonResponse } from "./version.js";

const E164_PHONE = /^\+[1-9][0-9]{1,14}$/u;
const INSERT_ATTEMPTS = 4;

export type BillingContactEnv = {
  DB: D1Database;
};

type ContactRow = {
  version: number;
  name: string;
  email: string;
  phone: string;
  contact_sha256?: string;
};

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.length > 0;
}

function contactResponse(
  row: ContactRow,
  contractVersion: number,
): Response {
  return clinicJsonResponse(
    {
      contract_version: contractVersion,
      version: row.version,
      name: row.name,
      email: row.email,
      phone: row.phone,
    },
    200,
    contractVersion,
  );
}

async function contactSha256(
  name: string,
  email: string,
  phone: string,
): Promise<string> {
  return sha256Hex(canonicalize({ name, email, phone }));
}

async function findRequestContact(
  env: BillingContactEnv,
  orgId: string,
  clientRequestId: string,
): Promise<ContactRow | null> {
  return env.DB.prepare(
    `SELECT version, name, email, phone, contact_sha256
     FROM billing_contact
     WHERE org_id = ? AND client_request_id = ?`,
  )
    .bind(orgId, clientRequestId)
    .first<ContactRow>();
}

function replayOrConflict(
  row: ContactRow,
  hash: string,
  contractVersion: number,
): Response {
  if (row.contact_sha256 !== hash) {
    return clinicErrorResponse("idempotency_conflict", 409, contractVersion);
  }
  return contactResponse(row, contractVersion);
}

export async function handleGetBillingContact(
  env: BillingContactEnv,
  orgId: string,
  contractVersion: number,
): Promise<Response> {
  const row = await env.DB.prepare(
    `SELECT version, name, email, phone
     FROM billing_contact
     WHERE org_id = ?
     ORDER BY version DESC
     LIMIT 1`,
  )
    .bind(orgId)
    .first<ContactRow>();

  if (row === null) {
    return clinicErrorResponse("not_found", 404, contractVersion);
  }

  return contactResponse(row, contractVersion);
}

export async function handlePutBillingContact(
  request: Request,
  env: BillingContactEnv,
  claims: BillingClaims,
  contractVersion: number,
): Promise<Response> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return clinicErrorResponse("invalid_request", 422, contractVersion);
  }

  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return clinicErrorResponse("invalid_request", 422, contractVersion);
  }

  const record = body as Record<string, unknown>;
  const clientRequestId = record.client_request_id;
  const name = record.name;
  const email = record.email;
  const phone = record.phone;

  if (
    !isNonEmptyString(clientRequestId) ||
    !isNonEmptyString(name) ||
    !isNonEmptyString(email) ||
    !isNonEmptyString(phone)
  ) {
    return clinicErrorResponse("invalid_request", 422, contractVersion);
  }

  if (!E164_PHONE.test(phone)) {
    return clinicErrorResponse("invalid_request", 422, contractVersion);
  }

  const orgId = claims.org;
  const hash = await contactSha256(name, email, phone);
  const existing = await findRequestContact(env, orgId, clientRequestId);
  if (existing !== null) {
    return replayOrConflict(existing, hash, contractVersion);
  }

  let lastError: unknown;
  for (let attempt = 0; attempt < INSERT_ATTEMPTS; attempt += 1) {
    try {
      const inserted = await env.DB.prepare(
        `INSERT INTO billing_contact (
           org_id, version, client_request_id, name, email, phone,
           contact_sha256, created_by_sub, contract_version
         )
         SELECT ?,
                (SELECT COALESCE(MAX(version), 0) + 1
                 FROM billing_contact WHERE org_id = ?),
                ?, ?, ?, ?, ?, ?, ?
         WHERE NOT EXISTS (
           SELECT 1 FROM billing_contact
           WHERE org_id = ? AND client_request_id = ?
         )
         ON CONFLICT DO NOTHING`,
      )
        .bind(
          orgId,
          orgId,
          clientRequestId,
          name,
          email,
          phone,
          hash,
          claims.sub,
          contractVersion,
          orgId,
          clientRequestId,
        )
        .run();

      if ((inserted.meta.changes ?? 0) > 0) {
        const versionRow = await env.DB.prepare(
          `SELECT version, name, email, phone, contact_sha256
           FROM billing_contact
           WHERE org_id = ? AND client_request_id = ?`,
        )
          .bind(orgId, clientRequestId)
          .first<ContactRow>();
        if (versionRow !== null) {
          return contactResponse(versionRow, contractVersion);
        }
      }
    } catch (error) {
      lastError = error;
    }

    // A competing request with this key may have won the insert. Re-read it
    // before retrying so the winner is replayed or reported as a conflict.
    const winner = await findRequestContact(env, orgId, clientRequestId);
    if (winner !== null) {
      return replayOrConflict(winner, hash, contractVersion);
    }
  }

  if (lastError !== undefined) {
    throw lastError;
  }
  throw new Error("Billing contact insert did not complete after retries");
}
