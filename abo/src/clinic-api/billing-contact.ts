import { canonicalize, sha256Hex } from "vendor-contracts";
import type { BillingClaims } from "./auth.js";
import { clinicErrorResponse, clinicJsonResponse } from "./version.js";

const E164_PHONE = /^\+[1-9][0-9]{1,14}$/u;

export type BillingContactEnv = {
  DB: D1Database;
};

type ContactRow = {
  version: number;
  name: string;
  email: string;
  phone: string;
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

  const existing = await env.DB.prepare(
    `SELECT version, name, email, phone
     FROM billing_contact
     WHERE org_id = ? AND client_request_id = ?`,
  )
    .bind(orgId, clientRequestId)
    .first<ContactRow>();

  if (existing !== null) {
    return contactResponse(existing, contractVersion);
  }

  const maxRow = await env.DB.prepare(
    `SELECT MAX(version) AS max_version FROM billing_contact WHERE org_id = ?`,
  )
    .bind(orgId)
    .first<{ max_version: number | null }>();

  const nextVersion = (maxRow?.max_version ?? 0) + 1;
  const hash = await contactSha256(name, email, phone);

  await env.DB.prepare(
    `INSERT INTO billing_contact (
       org_id, version, client_request_id, name, email, phone,
       contact_sha256, created_by_sub, contract_version
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      orgId,
      nextVersion,
      clientRequestId,
      name,
      email,
      phone,
      hash,
      claims.sub,
      contractVersion,
    )
    .run();

  return contactResponse(
    { version: nextVersion, name, email, phone },
    contractVersion,
  );
}
