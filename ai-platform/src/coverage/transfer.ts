import {
  CHANNEL_VERSIONS,
  canonicalize,
  receiptSigningBytes,
  sha256Hex,
  signCompactJws,
  verifyReceiptSignature,
} from "vendor-contracts";
import { raiseAl11Transfer, raiseAl18HeldBinding, type CoverageAlertEnv } from "../alert/index";
import { clockNowIso, type ClockEnv } from "../clock";
import { purgeByInstallationId } from "../retention/index";
import { generateUlid } from "../trace";
import { decodeDoResponse } from "../quota-do/response-decoder";

export type TransferEnv = ClockEnv &
  CoverageAlertEnv & {
    DB: D1Database;
    DO: DurableObjectNamespace;
    R2: R2Bucket;
    PLATFORM_SIGNING_KEY: string;
    DURATION_SCALE?: string;
  };

export type TransferRow = {
  transfer_id: string;
  org_id: string;
  from_installation_id: string;
  to_installation_id: string;
  reason: string;
  assertion_sha256: string;
  package: string | null;
  created_at: string;
};

type TransferStepRow = {
  transfer_id: string;
  step: string;
  receipt: string;
  applied_at: string;
};

type PlatformSigningMaterial = {
  kid: string;
  privateKey: CryptoKey;
};

function base64UrlDecode(segment: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]*$/u.test(segment)) {
    return null;
  }
  const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
  try {
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  } catch {
    return null;
  }
}

async function loadPlatformSigningKey(
  json: string,
): Promise<PlatformSigningMaterial | null> {
  try {
    const parsed = JSON.parse(json) as { kid?: string; pkcs8?: string };
    if (typeof parsed.kid !== "string" || typeof parsed.pkcs8 !== "string") {
      return null;
    }
    const pkcs8 = base64UrlDecode(parsed.pkcs8);
    if (pkcs8 === null) {
      return null;
    }
    const privateKey = await crypto.subtle.importKey(
      "pkcs8",
      pkcs8,
      { name: "Ed25519" },
      false,
      ["sign"],
    );
    return { kid: parsed.kid, privateKey };
  } catch {
    return null;
  }
}

function durationScaleFromEnv(env: TransferEnv): "staging" | undefined {
  return env.DURATION_SCALE === "staging" ? "staging" : undefined;
}

async function callCoverageDo(
  env: TransferEnv,
  installationId: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown> | null> {
  const id = env.DO.idFromName(installationId);
  const stub = env.DO.get(id);
  try {
    const response = await stub.fetch("https://quota-do.internal/rpc", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contract_version: CHANNEL_VERSIONS.platformDo,
        installationId,
        ...body,
      }),
    });
    if (!response.ok) {
      return null;
    }
    return decodeDoResponse<Record<string, unknown>>(
      await response.json(),
      CHANNEL_VERSIONS.platformDo,
    ) ?? null;
  } catch {
    return null;
  }
}

export function transferRowToDetail(row: TransferRow): string {
  const ordered = {
    transfer_id: row.transfer_id,
    org_id: row.org_id,
    from_installation_id: row.from_installation_id,
    to_installation_id: row.to_installation_id,
    reason: row.reason,
    assertion_sha256: row.assertion_sha256,
    package: row.package === null ? null : JSON.parse(row.package),
    created_at: row.created_at,
  };
  return JSON.stringify(ordered);
}

export async function readTransferById(
  db: D1Database,
  transferId: string,
): Promise<TransferRow | null> {
  return db
    .prepare(
      `SELECT transfer_id, org_id, from_installation_id, to_installation_id,
              reason, assertion_sha256, package, created_at
       FROM transfer WHERE transfer_id = ?`,
    )
    .bind(transferId)
    .first<TransferRow>();
}

export async function readTransferByAssertionSha256(
  db: D1Database,
  assertionSha256: string,
): Promise<TransferRow | null> {
  if (assertionSha256.length === 0) {
    return null;
  }
  return db
    .prepare(
      `SELECT transfer_id, org_id, from_installation_id, to_installation_id,
              reason, assertion_sha256, package, created_at
       FROM transfer WHERE assertion_sha256 = ?`,
    )
    .bind(assertionSha256)
    .first<TransferRow>();
}

async function readTransferStep(
  db: D1Database,
  transferId: string,
  step: "transfer_out" | "transfer_in",
): Promise<TransferStepRow | null> {
  return db
    .prepare(
      `SELECT transfer_id, step, receipt, applied_at
       FROM transfer_step WHERE transfer_id = ? AND step = ?`,
    )
    .bind(transferId, step)
    .first<TransferStepRow>();
}

async function readTransferRouteManifest(
  db: D1Database,
  transferId: string,
): Promise<Map<string, TransferRouteManifest>> {
  const rows = await db.prepare(
    `SELECT grant_id, source_epoch, source_generation
     FROM transfer_route_manifest WHERE transfer_id = ?`,
  ).bind(transferId).all<TransferRouteManifest>();
  return new Map((rows.results ?? []).map((row) => [row.grant_id, row]));
}

async function verifyTransferOutPackageReceipt(
  env: TransferEnv,
  transfer: TransferRow,
  packageValue: unknown,
  receipt: unknown,
): Promise<boolean> {
  if (!Array.isArray(packageValue) || typeof receipt !== "object" || receipt === null || Array.isArray(receipt)) {
    return false;
  }
  const signed = receipt as Record<string, unknown>;
  const termIds = signed.term_ids;
  if (
    signed.transfer_id !== transfer.transfer_id ||
    signed.installation_id !== transfer.from_installation_id ||
    signed.org_id !== transfer.org_id ||
    signed.result !== "applied" ||
    typeof signed.envelope_sha256 !== "string" ||
    typeof signed.signature !== "string" ||
    !Array.isArray(termIds) || termIds.length !== packageValue.length ||
    !termIds.every((id) => typeof id === "string") ||
    signed.envelope_sha256 !== await sha256Hex(
      new TextEncoder().encode(canonicalize(packageValue)),
    )
  ) {
    return false;
  }
  try {
    const signing = JSON.parse(env.PLATFORM_SIGNING_KEY) as { public_key?: unknown };
    if (typeof signing.public_key !== "string") return false;
    const bytes = base64UrlDecode(signing.public_key);
    if (bytes === null) return false;
    const publicKey = await crypto.subtle.importKey(
      "raw", bytes, { name: "Ed25519" }, false, ["verify"],
    );
    return await verifyReceiptSignature({ receipt: signed, publicKey });
  } catch {
    return false;
  }
}

export async function verifyTransferOutEvidence(
  env: TransferEnv,
  transfer: TransferRow,
): Promise<boolean> {
  if (await readTransferStep(env.DB, transfer.transfer_id, "transfer_in") !== null) {
    return true;
  }
  const step = await readTransferStep(env.DB, transfer.transfer_id, "transfer_out");
  let packageValue: unknown;
  let receipt: unknown;
  try {
    packageValue = transfer.package === null ? null : JSON.parse(transfer.package) as unknown;
    receipt = step === null ? null : JSON.parse(step.receipt) as unknown;
  } catch {
    packageValue = null;
    receipt = null;
  }
  if (step !== null && await verifyTransferOutPackageReceipt(env, transfer, packageValue, receipt)) {
    return true;
  }
  await env.DB.prepare(
    `INSERT OR IGNORE INTO transfer_route_quarantine
       (transfer_id, grant_id, reason, created_at)
     VALUES (?, '', 'receipt_export_mismatch', ?)`,
  ).bind(transfer.transfer_id, await clockNowIso(env)).run();
  return false;
}

export async function isTransferRouteQuarantined(
  db: D1Database,
  transferId: string,
): Promise<boolean> {
  const row = await db.prepare(
    `SELECT 1 AS quarantined FROM transfer_route_quarantine
     WHERE transfer_id = ?
       AND NOT EXISTS (
         SELECT 1 FROM transfer_step
         WHERE transfer_step.transfer_id = transfer_route_quarantine.transfer_id
           AND transfer_step.step = 'transfer_in'
       )
     LIMIT 1`,
  ).bind(transferId).first<{ quarantined: number }>();
  return row !== null;
}

type TransferValueRoute = {
  grant_id: string;
  binding_epoch: number;
  generation: number;
  state: string;
  transfer_id: string | null;
};

type TransferRouteManifest = {
  grant_id: string;
  source_epoch: number;
  source_generation: number;
};

async function prepareValueRoutesForTransfer(
  env: TransferEnv,
  transfer: TransferRow,
  nowIso: string,
): Promise<TransferValueRoute[] | null> {
  const routes = await env.DB.prepare(
    `SELECT grant_id, binding_epoch, generation, state, transfer_id FROM live_value_route
     WHERE org_id = ? AND installation_id = ? AND state IN ('stable', 'moving')`,
  ).bind(transfer.org_id, transfer.from_installation_id).all<TransferValueRoute>();
  const current = routes.results ?? [];
  if (current.some((row) => row.state === "moving" && row.transfer_id !== transfer.transfer_id)) {
    return null;
  }
  const updates = current
    .filter((row) => row.state === "stable")
    .map((row) => env.DB.prepare(
      `UPDATE live_value_route SET state = 'moving', transfer_id = ?, reversal_id = NULL, updated_at = ?
       WHERE grant_id = ? AND state = 'stable' AND generation = ? AND installation_id = ?`,
    ).bind(transfer.transfer_id, nowIso, row.grant_id, row.generation, transfer.from_installation_id));
  if (updates.length > 0) await env.DB.batch(updates);
  const after = await env.DB.prepare(
    `SELECT grant_id, binding_epoch, generation, state, transfer_id FROM live_value_route
     WHERE org_id = ? AND installation_id = ? AND state IN ('stable', 'moving', 'voiding')`,
  ).bind(transfer.org_id, transfer.from_installation_id).all<TransferValueRoute>();
  const rows = after.results ?? [];
  if (rows.some((row) => row.state === "voiding" || row.state === "stable" ||
      (row.state === "moving" && row.transfer_id !== transfer.transfer_id))) return null;
  return rows;
}

async function publishTransferredValueRoutes(
  env: TransferEnv,
  transfer: TransferRow,
  packageValue: unknown[],
  destinationEpoch: number,
  manifestByGrant: Map<string, TransferRouteManifest>,
  nowIso: string,
): Promise<boolean> {
  const originIds = [...new Set(packageValue.map((row) =>
    typeof row === "object" && row !== null && !Array.isArray(row) &&
    typeof (row as Record<string, unknown>).origin_grant_id === "string"
      ? (row as Record<string, unknown>).origin_grant_id as string
      : "",
  ).filter(Boolean))];
  if (originIds.some((grantId) => !manifestByGrant.has(grantId))) return false;
  const currentRows = originIds.length === 0
    ? []
    : (await env.DB.prepare(
        `SELECT grant_id, org_id, installation_id, binding_epoch, generation,
                state, transfer_id
         FROM live_value_route WHERE grant_id IN (${originIds.map(() => "?").join(",")})`,
      ).bind(...originIds).all<TransferValueRoute & { org_id: string }>()).results ?? [];
  const currentByGrant = new Map(currentRows.map((row) => [row.grant_id, row]));
  if (originIds.some((grantId) => {
    const route = currentByGrant.get(grantId);
    const manifest = manifestByGrant.get(grantId)!;
    return route === undefined || route.org_id !== transfer.org_id || !(
      (route.installation_id === transfer.from_installation_id &&
        route.binding_epoch === manifest.source_epoch &&
        route.generation === manifest.source_generation &&
        route.state === "moving" && route.transfer_id === transfer.transfer_id) ||
      (route.installation_id === transfer.to_installation_id &&
        route.binding_epoch === destinationEpoch &&
        route.generation === manifest.source_generation + 1 &&
        route.state === "stable" && route.transfer_id === null)
    );
  })) return false;
  const statements = originIds.flatMap((grantId) => [
    env.DB.prepare(
      `UPDATE live_value_route
       SET installation_id = ?, binding_epoch = ?, generation = generation + 1,
           state = 'stable', transfer_id = NULL, reversal_id = NULL, updated_at = ?
       WHERE grant_id = ? AND org_id = ? AND installation_id = ?
         AND binding_epoch = ? AND generation = ?
         AND state = 'moving' AND transfer_id = ?`,
    ).bind(
      transfer.to_installation_id, destinationEpoch, nowIso, grantId, transfer.org_id,
      transfer.from_installation_id, manifestByGrant.get(grantId)!.source_epoch,
      manifestByGrant.get(grantId)!.source_generation, transfer.transfer_id,
    ),
    env.DB.prepare(
      `UPDATE reversal_command SET route_installation_id = ?, route_epoch = ?,
         route_generation = route_generation + 1, updated_at = ?
       WHERE grant_id = ? AND state = 'due' AND route_installation_id = ?
         AND route_epoch = ? AND route_generation = ?
         AND EXISTS (
           SELECT 1 FROM live_value_route
           WHERE grant_id = ? AND org_id = ? AND installation_id = ?
             AND binding_epoch = ? AND generation = ?
             AND state = 'stable' AND transfer_id IS NULL
         )`,
    ).bind(
      transfer.to_installation_id, destinationEpoch, nowIso, grantId,
      transfer.from_installation_id, manifestByGrant.get(grantId)!.source_epoch,
      manifestByGrant.get(grantId)!.source_generation, grantId, transfer.org_id,
      transfer.to_installation_id, destinationEpoch,
      manifestByGrant.get(grantId)!.source_generation + 1,
    ),
  ]);
  if (statements.length > 0) await env.DB.batch(statements);
  if (originIds.length === 0) return true;
  const rows = await env.DB.prepare(
    `SELECT grant_id, installation_id, binding_epoch, generation, state, transfer_id
     FROM live_value_route WHERE grant_id IN (${originIds.map(() => "?").join(",")})`,
  ).bind(...originIds).all<{
    grant_id: string; installation_id: string; binding_epoch: number; generation: number; state: string; transfer_id: string | null;
  }>();
  return originIds.every((id) => (rows.results ?? []).some((row) =>
    row.grant_id === id && row.installation_id === transfer.to_installation_id &&
    row.binding_epoch === destinationEpoch &&
    row.generation === manifestByGrant.get(id)!.source_generation + 1 &&
    row.state === "stable" && row.transfer_id === null,
  ));
}

async function readSourceBinding(
  db: D1Database,
  orgId: string,
  fromInstallationId: string,
): Promise<{ installation_id: string; epoch: number; status: string } | null> {
  return db
    .prepare(
      `SELECT installation_id, epoch, status FROM tenant_binding
       WHERE org_id = ? AND installation_id = ?
         AND status IN ('active', 'held_for_transfer')`,
    )
    .bind(orgId, fromInstallationId)
    .first<{ installation_id: string; epoch: number; status: string }>();
}

async function readMaxEpoch(db: D1Database, orgId: string): Promise<number> {
  const row = await db
    .prepare(`SELECT MAX(epoch) AS max_epoch FROM tenant_binding WHERE org_id = ?`)
    .bind(orgId)
    .first<{ max_epoch: number | null }>();
  return row?.max_epoch ?? 0;
}

export async function signTransferReceipt(input: {
  signingKey: PlatformSigningMaterial;
  vendorContractVersion: number;
  transferId: string;
  installationId: string;
  orgId: string;
  termIds: string[];
  appliedAt: string;
  ledgerSeq: number;
  envelopeSha256: string;
}): Promise<Record<string, unknown>> {
  const unsigned = {
    contract_version: input.vendorContractVersion,
    transfer_id: input.transferId,
    installation_id: input.installationId,
    org_id: input.orgId,
    result: "applied",
    term_ids: input.termIds,
    applied_at: input.appliedAt,
    ledger_seq: input.ledgerSeq,
    envelope_sha256: input.envelopeSha256,
    kid: input.signingKey.kid,
  };
  const signature = await signCompactJws({
    payload: receiptSigningBytes(unsigned),
    privateKey: input.signingKey.privateKey,
    kid: input.signingKey.kid,
  });
  return { ...unsigned, signature };
}

export async function executeBeginTransfer(
  env: TransferEnv,
  input: {
    orgId: string;
    fromInstallationId: string;
    reason: string;
    assertionSha256: string;
  },
): Promise<TransferRow | "bad_request"> {
  const source = await readSourceBinding(
    env.DB,
    input.orgId,
    input.fromInstallationId,
  );
  if (source === null) {
    return "bad_request";
  }

  const newInstallationId = crypto.randomUUID();
  const transferId = generateUlid();
  const createdAt = await clockNowIso(env);
  const nextEpoch = (await readMaxEpoch(env.DB, input.orgId)) + 1;
  const routeRows = await env.DB.prepare(
    `SELECT grant_id, generation, state FROM live_value_route
     WHERE org_id = ? AND installation_id = ? AND state IN ('stable', 'moving', 'voiding')`,
  ).bind(input.orgId, input.fromInstallationId).all<{
    grant_id: string; generation: number; state: string;
  }>();
  const routes = routeRows.results ?? [];
  if (routes.some((row) => row.state !== "stable")) return "bad_request";

  await env.DB.batch([
    ...routes.map((row) => env.DB.prepare(
      `UPDATE live_value_route SET state = 'moving', transfer_id = ?, reversal_id = NULL, updated_at = ?
       WHERE grant_id = ? AND state = 'stable' AND generation = ? AND installation_id = ?`,
    ).bind(transferId, createdAt, row.grant_id, row.generation, input.fromInstallationId)),
    env.DB
      .prepare(
        `UPDATE tenant_binding
         SET status = 'retired', retired_at = ?, reason = ?
         WHERE org_id = ? AND installation_id = ?
           AND status IN ('active', 'held_for_transfer')
           AND NOT EXISTS (
             SELECT 1 FROM live_value_route
             WHERE org_id = ? AND installation_id = ?
               AND (state IN ('stable', 'voiding')
                 OR (state = 'moving' AND transfer_id <> ?))
           )`,
      )
      .bind(createdAt, input.reason, input.orgId, input.fromInstallationId,
        input.orgId, input.fromInstallationId, transferId),
    env.DB
      .prepare(
        `INSERT INTO installation (
           installation_id, org_id, status, display_name, region, enrolled_at
         )
         SELECT ?, ?, 'active', '', '', ?
         WHERE EXISTS (
           SELECT 1 FROM tenant_binding WHERE org_id = ? AND installation_id = ?
             AND status = 'retired' AND retired_at = ?
         )
           AND NOT EXISTS (
             SELECT 1 FROM live_value_route
             WHERE org_id = ? AND installation_id = ?
               AND (state IN ('stable', 'voiding')
                 OR (state = 'moving' AND transfer_id <> ?))
           )`,
      )
      .bind(newInstallationId, input.orgId, createdAt, input.orgId,
        input.fromInstallationId, createdAt, input.orgId,
        input.fromInstallationId, transferId),
    env.DB
      .prepare(
        `INSERT INTO tenant_binding (
           org_id, installation_id, epoch, status, retired_at, reason, created_at
         )
         SELECT ?, ?, ?, 'active', NULL, NULL, ?
         WHERE EXISTS (
           SELECT 1 FROM installation WHERE installation_id = ? AND org_id = ?
         )`,
      )
      .bind(input.orgId, newInstallationId, nextEpoch, createdAt,
        newInstallationId, input.orgId),
    env.DB
      .prepare(
        `INSERT INTO transfer (
           transfer_id, org_id, from_installation_id, to_installation_id,
           reason, assertion_sha256, package, created_at
         )
         SELECT ?, ?, ?, ?, ?, ?, NULL, ?
         WHERE EXISTS (
           SELECT 1 FROM tenant_binding WHERE org_id = ? AND installation_id = ?
             AND epoch = ? AND status = 'active'
         )
           AND EXISTS (
             SELECT 1 FROM tenant_binding WHERE org_id = ? AND installation_id = ?
               AND status = 'retired' AND retired_at = ?
           )
           AND NOT EXISTS (
             SELECT 1 FROM live_value_route
             WHERE org_id = ? AND installation_id = ?
               AND (state IN ('stable', 'voiding')
                 OR (state = 'moving' AND transfer_id <> ?))
           )`,
      )
      .bind(
        transferId,
        input.orgId,
        input.fromInstallationId,
        newInstallationId,
        input.reason,
        input.assertionSha256,
        createdAt,
        input.orgId,
        newInstallationId,
        nextEpoch,
        input.orgId,
        input.fromInstallationId,
        createdAt,
        input.orgId,
        input.fromInstallationId,
        transferId,
      ),
  ]);

  const row = await readTransferById(env.DB, transferId);
  if (row === null) return "bad_request";

  const opened = await callCoverageDo(env, newInstallationId, {
    kind: "open_awaiting_transfer",
    bindingEpoch: nextEpoch,
  });
  if (opened === null || opened.result !== "ok") {
    return "bad_request";
  }

  return row;
}

export type TransferStepResult =
  | {
      result: "applied" | "already_applied";
      detail: string;
      receipt: Record<string, unknown>;
    }
  | { result: "transient"; detail: string }
  | { result: "rejected"; code: string }
  | { result: "bad_request" };

export async function executeTransferOut(
  env: TransferEnv,
  vendorContractVersion: number,
  transferId: string,
): Promise<TransferStepResult> {
  const transfer = await readTransferById(env.DB, transferId);
  if (transfer === null) {
    return { result: "bad_request" };
  }

  const existingStep = await readTransferStep(env.DB, transferId, "transfer_out");
  if (existingStep !== null) {
    if (!(await verifyTransferOutEvidence(env, transfer))) {
      return { result: "rejected", code: "transfer_route_quarantined" };
    }
    const receipt = JSON.parse(existingStep.receipt) as Record<string, unknown>;
    const packageJson =
      transfer.package !== null ? transfer.package : "[]";
    return {
      result: "already_applied",
      detail: packageJson,
      receipt,
    };
  }

  const transferStartedAt = await clockNowIso(env);
  const movingRoutes = await prepareValueRoutesForTransfer(env, transfer, transferStartedAt);
  if (movingRoutes === null) {
    return { result: "transient", detail: "reversal_or_transfer_in_progress" };
  }

  const sourceBinding = await env.DB
    .prepare(
      `SELECT epoch FROM tenant_binding
       WHERE org_id = ? AND installation_id = ?`,
    )
    .bind(transfer.org_id, transfer.from_installation_id)
    .first<{ epoch: number }>();

  const doResponse = await callCoverageDo(env, transfer.from_installation_id, {
    kind: "transfer_out",
    installationId: transfer.from_installation_id,
    orgId: transfer.org_id,
    vendorContractVersion,
    bindingEpoch: sourceBinding?.epoch ?? 1,
    transferId,
    toInstallationId: transfer.to_installation_id,
    platformSigningKeyJson: env.PLATFORM_SIGNING_KEY,
    durationScale: durationScaleFromEnv(env),
    nowIso: await clockNowIso(env),
  });

  if (doResponse === null) {
    return { result: "bad_request" };
  }
  if (doResponse.result === "bad_request") {
    return { result: "bad_request" };
  }
  if (doResponse.result !== "applied") {
    return { result: "bad_request" };
  }

  const packageValue = doResponse.package;
  const termIds = doResponse.term_ids;
  const ledgerSeq = doResponse.ledger_seq;
  const receiptRaw = doResponse.receipt;
  if (
    !Array.isArray(packageValue) ||
    !Array.isArray(termIds) ||
    typeof ledgerSeq !== "number" ||
    typeof receiptRaw !== "object" ||
    receiptRaw === null
  ) {
    return { result: "bad_request" };
  }
  if (!(await verifyTransferOutPackageReceipt(env, transfer, packageValue, receiptRaw))) {
    await env.DB.prepare(
      `INSERT OR IGNORE INTO transfer_route_quarantine
         (transfer_id, grant_id, reason, created_at)
       VALUES (?, '', 'receipt_export_mismatch', ?)`,
    ).bind(transferId, await clockNowIso(env)).run();
    return { result: "rejected", code: "transfer_route_quarantined" };
  }

  const packageJson = JSON.stringify(packageValue);
  const receiptJson = JSON.stringify(receiptRaw);
  const appliedAt = await clockNowIso(env);
  const movedOrigins = new Set(packageValue.flatMap((row) =>
    typeof row === "object" && row !== null && !Array.isArray(row) &&
    typeof (row as Record<string, unknown>).origin_grant_id === "string"
      ? [(row as Record<string, unknown>).origin_grant_id as string]
      : [],
  ));
  const routeManifest = movingRoutes.filter((row) => movedOrigins.has(row.grant_id));
  if (routeManifest.length !== movedOrigins.size) {
    return { result: "transient", detail: "value_route_manifest_pending" };
  }
  const routeSettleStatements = movingRoutes
    .filter((row) => !movedOrigins.has(row.grant_id))
    .map((row) => env.DB.prepare(
      `UPDATE live_value_route SET state = 'stable', transfer_id = NULL, updated_at = ?
       WHERE grant_id = ? AND state = 'moving' AND transfer_id = ? AND generation = ?`,
    ).bind(appliedAt, row.grant_id, transferId, row.generation));

  await env.DB.batch([
    env.DB
      .prepare(`UPDATE transfer SET package = ? WHERE transfer_id = ?`)
      .bind(packageJson, transferId),
    env.DB
      .prepare(
        `INSERT INTO transfer_step (transfer_id, step, receipt, applied_at)
         VALUES (?, 'transfer_out', ?, ?)`,
      )
      .bind(transferId, receiptJson, appliedAt),
    ...routeManifest.map((row) => env.DB.prepare(
      `INSERT INTO transfer_route_manifest (
         transfer_id, grant_id, source_epoch, source_generation
       ) VALUES (?, ?, ?, ?)`,
    ).bind(transferId, row.grant_id, row.binding_epoch, row.generation)),
    ...routeSettleStatements,
  ]);

  return {
    result: "applied",
    detail: packageJson,
    receipt: receiptRaw as Record<string, unknown>,
  };
}

export async function executeTransferIn(
  env: TransferEnv,
  vendorContractVersion: number,
  transferId: string,
): Promise<TransferStepResult> {
  const transfer = await readTransferById(env.DB, transferId);
  if (transfer === null) {
    return { result: "bad_request" };
  }

  const outStep = await readTransferStep(env.DB, transferId, "transfer_out");
  if (outStep === null) {
    return { result: "transient", detail: "awaiting_transfer_out" };
  }

  const existingIn = await readTransferStep(env.DB, transferId, "transfer_in");

  if (transfer.package === null) {
    return { result: "bad_request" };
  }

  const packageValue = JSON.parse(transfer.package) as unknown;
  if (!Array.isArray(packageValue)) {
    return { result: "bad_request" };
  }

  const destBinding = await env.DB
    .prepare(
      `SELECT epoch FROM tenant_binding
       WHERE org_id = ? AND installation_id = ?`,
    )
    .bind(transfer.org_id, transfer.to_installation_id)
    .first<{ epoch: number }>();
  if (destBinding === null) return { result: "bad_request" };

  if (existingIn !== null) {
    return {
      result: "already_applied",
      detail: transfer.package,
      receipt: JSON.parse(existingIn.receipt) as Record<string, unknown>,
    };
  }

  if (await isTransferRouteQuarantined(env.DB, transferId)) {
    return { result: "rejected", code: "transfer_route_quarantined" };
  }
  if (!(await verifyTransferOutEvidence(env, transfer))) {
    return { result: "rejected", code: "transfer_route_quarantined" };
  }

  const routeManifest = await readTransferRouteManifest(env.DB, transferId);
  const originIds = [...new Set(packageValue.flatMap((row) =>
    typeof row === "object" && row !== null && !Array.isArray(row) &&
    typeof (row as Record<string, unknown>).origin_grant_id === "string"
      ? [(row as Record<string, unknown>).origin_grant_id as string]
      : [],
  ))];
  if (originIds.some((grantId) => !routeManifest.has(grantId))) {
    return { result: "transient", detail: "value_route_manifest_pending" };
  }

  const doResponse = await callCoverageDo(env, transfer.to_installation_id, {
    kind: "transfer_in",
    installationId: transfer.to_installation_id,
    orgId: transfer.org_id,
    vendorContractVersion,
    bindingEpoch: destBinding?.epoch ?? 1,
    transferId,
    package: packageValue,
    platformSigningKeyJson: env.PLATFORM_SIGNING_KEY,
    durationScale: durationScaleFromEnv(env),
    nowIso: await clockNowIso(env),
  });

  if (doResponse === null || doResponse.result !== "applied") {
    return { result: "bad_request" };
  }

  const termIds = doResponse.term_ids;
  const receiptRaw = doResponse.receipt;
  if (
    !Array.isArray(termIds) ||
    typeof receiptRaw !== "object" ||
    receiptRaw === null
  ) {
    return { result: "bad_request" };
  }

  if (!(await publishTransferredValueRoutes(
    env, transfer, packageValue, destBinding.epoch, routeManifest, await clockNowIso(env),
  ))) {
    return { result: "transient", detail: "value_route_publish_pending" };
  }

  const packageJson = transfer.package;
  const receiptJson = JSON.stringify(receiptRaw);
  const appliedAt = await clockNowIso(env);

  await env.DB
    .prepare(
      `INSERT INTO transfer_step (transfer_id, step, receipt, applied_at)
       VALUES (?, 'transfer_in', ?, ?)`,
    )
    .bind(transferId, receiptJson, appliedAt)
    .run();

  await raiseAl11Transfer(env, transferId, transfer.org_id);

  return {
    result: "applied",
    detail: packageJson,
    receipt: receiptRaw as Record<string, unknown>,
  };
}

type InstallationRow = {
  installation_id: string;
  org_id: string;
  status: string;
  display_name: string;
  region: string;
  enrolled_at: string;
};

type TenantBindingRow = {
  org_id: string;
  installation_id: string;
  epoch: number;
  status: string;
  retired_at: string | null;
  reason: string | null;
  created_at: string;
};

function installationDeleteDetail(
  installation: InstallationRow,
  binding: TenantBindingRow,
): string {
  return JSON.stringify({ installation, tenant_binding: binding });
}

async function readInstallationRow(
  db: D1Database,
  installationId: string,
): Promise<InstallationRow | null> {
  return db
    .prepare(
      `SELECT installation_id, org_id, status, display_name, region, enrolled_at
       FROM installation WHERE installation_id = ?`,
    )
    .bind(installationId)
    .first<InstallationRow>();
}

async function readBindingRow(
  db: D1Database,
  orgId: string,
  installationId: string,
): Promise<TenantBindingRow | null> {
  return db
    .prepare(
      `SELECT org_id, installation_id, epoch, status, retired_at, reason, created_at
       FROM tenant_binding WHERE org_id = ? AND installation_id = ?`,
    )
    .bind(orgId, installationId)
    .first<TenantBindingRow>();
}

async function readLiveOrgBinding(
  db: D1Database,
  orgId: string,
): Promise<TenantBindingRow | null> {
  return db
    .prepare(
      `SELECT org_id, installation_id, epoch, status, retired_at, reason, created_at
       FROM tenant_binding
       WHERE org_id = ? AND status IN ('active', 'held_for_transfer')
       ORDER BY epoch DESC
       LIMIT 1`,
    )
    .bind(orgId)
    .first<TenantBindingRow>();
}

function termIsNotEnded(state: string | undefined): boolean {
  return (
    state === "active" ||
    state === "grace" ||
    state === "queued" ||
    state === "held"
  );
}

async function inspectInstallationTerms(
  env: TransferEnv,
  installationId: string,
  orgId: string,
): Promise<Array<{ term_id?: string; state?: string }>> {
  const inspected = await callCoverageDo(env, installationId, {
    kind: "inspect_coverage",
    installationId,
    orgId,
    vendorContractVersion: CHANNEL_VERSIONS.platformDo,
  });
  if (inspected === null || !Array.isArray(inspected.terms)) {
    return [];
  }
  return inspected.terms as Array<{ term_id?: string; state?: string }>;
}

async function installationHasOpenCoverage(
  env: TransferEnv,
  installationId: string,
  orgId: string,
): Promise<boolean> {
  const terms = await inspectInstallationTerms(env, installationId, orgId);
  return terms.some((row) => termIsNotEnded(row.state));
}

async function installationOpenTermIds(
  env: TransferEnv,
  installationId: string,
  orgId: string,
): Promise<string[]> {
  const terms = await inspectInstallationTerms(env, installationId, orgId);
  return terms
    .filter((row) => termIsNotEnded(row.state) && typeof row.term_id === "string")
    .map((row) => row.term_id as string);
}

export async function executeDeleteInstallation(
  env: TransferEnv,
  input: {
    orgId: string;
    reason: string;
    operatorId: string;
  },
): Promise<
  | { result: "ok"; detail: string }
  | { result: "bad_request" }
> {
  const binding = await readLiveOrgBinding(env.DB, input.orgId);
  if (binding === null) {
    return { result: "bad_request" };
  }

  const installation = await readInstallationRow(
    env.DB,
    binding.installation_id,
  );
  if (installation === null) {
    return { result: "bad_request" };
  }

  if (
    installation.status === "deleted" &&
    (binding.status === "held_for_transfer" || binding.status === "retired")
  ) {
    return {
      result: "ok",
      detail: installationDeleteDetail(installation, binding),
    };
  }

  const nowIso = await clockNowIso(env);
  const hasCoverage = await installationHasOpenCoverage(
    env,
    binding.installation_id,
    input.orgId,
  );

  await env.DB
    .prepare(`UPDATE installation SET status = 'deleted' WHERE installation_id = ?`)
    .bind(binding.installation_id)
    .run();

  if (hasCoverage) {
    await env.DB
      .prepare(
        `UPDATE tenant_binding
         SET status = 'held_for_transfer', retired_at = NULL, reason = NULL
         WHERE org_id = ? AND installation_id = ?`,
      )
      .bind(input.orgId, binding.installation_id)
      .run();

    await callCoverageDo(env, binding.installation_id, {
      kind: "set_transfer_pending",
      bindingEpoch: binding.epoch,
    });

    await raiseAl18HeldBinding(env, input.orgId, binding.installation_id);
  } else {
    await env.DB
      .prepare(
        `UPDATE tenant_binding
         SET status = 'retired', retired_at = ?, reason = ?
         WHERE org_id = ? AND installation_id = ?`,
      )
      .bind(nowIso, input.reason, input.orgId, binding.installation_id)
      .run();
  }

  const installationAfter = await readInstallationRow(
    env.DB,
    binding.installation_id,
  );
  const bindingAfter = await readBindingRow(
    env.DB,
    input.orgId,
    binding.installation_id,
  );
  if (installationAfter === null || bindingAfter === null) {
    return { result: "bad_request" };
  }

  const detail = installationDeleteDetail(installationAfter, bindingAfter);

  const preserveUsageTermIds = await installationOpenTermIds(
    env,
    binding.installation_id,
    input.orgId,
  );

  await purgeByInstallationId(binding.installation_id, input.operatorId, {
    db: env.DB,
    r2: env.R2,
    preserveUsageTermIds,
  });

  return {
    result: "ok",
    detail,
  };
}

export async function retireHeldBindingIfEmpty(
  env: TransferEnv,
  orgId: string,
  installationId: string,
  reason: string,
): Promise<void> {
  const binding = await readBindingRow(env.DB, orgId, installationId);
  if (binding === null || binding.status !== "held_for_transfer") {
    return;
  }
  const hasCoverage = await installationHasOpenCoverage(
    env,
    installationId,
    orgId,
  );
  if (hasCoverage) {
    return;
  }
  const nowIso = await clockNowIso(env);
  await env.DB
    .prepare(
      `UPDATE tenant_binding
       SET status = 'retired', retired_at = ?, reason = ?
       WHERE org_id = ? AND installation_id = ? AND status = 'held_for_transfer'`,
    )
    .bind(nowIso, reason, orgId, installationId)
    .run();
}
