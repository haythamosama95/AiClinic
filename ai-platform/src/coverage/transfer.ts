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

type TransferPreparationRow = {
  transfer_id: string;
  org_id: string;
  from_installation_id: string;
  source_epoch: number;
  to_installation_id: string;
  destination_epoch: number;
  reason: string;
  assertion_sha256: string;
  accepted_actor: string;
  accepted_signer_credential_id: string;
  accepted_command: string;
  phase: "accepted" | "destination_ready" | "source_frozen" | "published" | "completed";
  due_at: string;
  lease_token: string | null;
  lease_until: string | null;
  created_at: string;
  updated_at: string;
};

export async function readTransferPreparationByAssertion(
  db: D1Database,
  assertionSha256: string,
): Promise<TransferPreparationRow | null> {
  return db.prepare(
    `SELECT * FROM transfer_preparation WHERE assertion_sha256 = ?`,
  ).bind(assertionSha256).first<TransferPreparationRow>();
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

async function restoreTransferOutStepFromDo(
  env: TransferEnv,
  vendorContractVersion: number,
  transfer: TransferRow,
): Promise<TransferStepRow | null> {
  if (transfer.package === null) return null;
  let persistedPackage: unknown;
  try {
    persistedPackage = JSON.parse(transfer.package) as unknown;
  } catch {
    return null;
  }
  if (!Array.isArray(persistedPackage)) return null;
  const sourceBinding = await env.DB.prepare(
    `SELECT epoch FROM tenant_binding
     WHERE org_id = ? AND installation_id = ?`,
  ).bind(transfer.org_id, transfer.from_installation_id)
    .first<{ epoch: number }>();
  if (sourceBinding === null) return null;
  const response = await callCoverageDo(env, transfer.from_installation_id, {
    kind: "transfer_out",
    installationId: transfer.from_installation_id,
    orgId: transfer.org_id,
    vendorContractVersion,
    bindingEpoch: sourceBinding.epoch,
    transferId: transfer.transfer_id,
    toInstallationId: transfer.to_installation_id,
    platformSigningKeyJson: env.PLATFORM_SIGNING_KEY,
    durationScale: durationScaleFromEnv(env),
    nowIso: await clockNowIso(env),
  });
  const packageValue = response?.package;
  const receipt = response?.receipt;
  if (
    response === null ||
    (response.result !== "applied" && response.result !== "already_applied") ||
    !Array.isArray(packageValue) ||
    await sha256Hex(canonicalize(packageValue)) !==
      await sha256Hex(canonicalize(persistedPackage)) ||
    typeof receipt !== "object" || receipt === null ||
    !(await verifyTransferOutPackageReceipt(env, transfer, packageValue, receipt))
  ) return null;
  const origins = [...new Set(persistedPackage.flatMap((row) =>
    typeof row === "object" && row !== null && !Array.isArray(row) &&
    typeof (row as Record<string, unknown>).origin_grant_id === "string"
      ? [(row as Record<string, unknown>).origin_grant_id as string]
      : [],
  ))];
  const manifest = await readTransferRouteManifest(env.DB, transfer.transfer_id);
  if (origins.some((grantId) => !manifest.has(grantId))) return null;
  const now = await clockNowIso(env);
  await env.DB.prepare(
    `INSERT OR IGNORE INTO transfer_step (transfer_id, step, receipt, applied_at)
     VALUES (?, 'transfer_out', ?, ?)`,
  ).bind(transfer.transfer_id, JSON.stringify(receipt), now).run();
  const restored = await readTransferStep(env.DB, transfer.transfer_id, "transfer_out");
  if (
    restored === null ||
    await sha256Hex(canonicalize(JSON.parse(restored.receipt))) !==
      await sha256Hex(canonicalize(receipt))
  ) {
    return null;
  }
  return restored;
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
    signed.envelope_sha256 !== await sha256Hex(canonicalize(packageValue))
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
    .prepare(`SELECT MAX(epoch) AS max_epoch FROM (
      SELECT epoch FROM tenant_binding WHERE org_id = ?
      UNION ALL
      SELECT destination_epoch AS epoch FROM transfer_preparation WHERE org_id = ?
    )`)
    .bind(orgId, orgId)
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
    acceptedActor: string;
    signerCredentialId: string;
    contractVersion: number;
  },
): Promise<TransferRow | "bad_request" | "transient"> {
  const deletionInProgress = await env.DB.prepare(
    `SELECT 1 AS pending FROM deletion_command
     WHERE org_id = ? AND phase <> 'completed' LIMIT 1`,
  ).bind(input.orgId).first<{ pending: number }>();
  if (deletionInProgress !== null) return "bad_request";
  const existing = await readTransferPreparationByAssertion(env.DB, input.assertionSha256);
  if (existing !== null) {
    if (
      existing.org_id !== input.orgId ||
      existing.from_installation_id !== input.fromInstallationId ||
      existing.reason !== input.reason ||
      existing.accepted_actor !== input.acceptedActor ||
      existing.accepted_signer_credential_id !== input.signerCredentialId
    ) return "bad_request";
    return resumeTransferPreparation(env, existing.transfer_id);
  }

  // Upgrade compatibility: a transfer row proves that the old begin flow
  // accepted this exact assertion, but only complete immutable out evidence
  // lets the new receiver safely resume it. Missing or mismatched evidence is
  // quarantined for operator adjudication instead of guessed from live routes.
  const historical = await readTransferByAssertionSha256(env.DB, input.assertionSha256);
  if (historical !== null) {
    if (
      historical.org_id !== input.orgId ||
      historical.from_installation_id !== input.fromInstallationId ||
      historical.reason !== input.reason
    ) return "bad_request";
    const oldOut = await readTransferStep(env.DB, historical.transfer_id, "transfer_out");
    const oldIn = await readTransferStep(env.DB, historical.transfer_id, "transfer_in");
    const oldSource = await env.DB.prepare(
      `SELECT epoch, status FROM tenant_binding WHERE org_id = ? AND installation_id = ?`,
    ).bind(input.orgId, historical.from_installation_id)
      .first<{ epoch: number; status: string }>();
    const oldDestination = await env.DB.prepare(
      `SELECT epoch, status FROM tenant_binding WHERE org_id = ? AND installation_id = ?`,
    ).bind(input.orgId, historical.to_installation_id)
      .first<{ epoch: number; status: string }>();
    const unstartedLegacy = historical.package === null && oldOut === null && oldIn === null;
    let verifiedHistoricalOut = false;
    if (historical.package !== null && oldOut !== null) {
      try {
        const pkg = JSON.parse(historical.package) as unknown;
        const receipt = JSON.parse(oldOut.receipt) as unknown;
        verifiedHistoricalOut = await verifyTransferOutPackageReceipt(env, historical, pkg, receipt);
      } catch {
        verifiedHistoricalOut = false;
      }
    }
    if (
      oldSource === null ||
      oldDestination === null || oldSource.status !== "retired" ||
      !(oldDestination.status === "active" || oldDestination.status === "held_for_transfer" ||
        (oldDestination.status === "retired" && oldIn !== null)) ||
      (unstartedLegacy && oldDestination.status !== "active") ||
      oldDestination.epoch <= oldSource.epoch ||
      (!unstartedLegacy && !verifiedHistoricalOut)
    ) {
      await env.DB.prepare(
        `INSERT OR IGNORE INTO transfer_route_quarantine
           (transfer_id, grant_id, reason, created_at)
         VALUES (?, '', 'legacy_transfer_evidence_ambiguous', ?)`,
      ).bind(historical.transfer_id, await clockNowIso(env)).run();
      return "bad_request";
    }
    if (unstartedLegacy) {
      const now = await clockNowIso(env);
      const destinationFence = await callCoverageDo(env, historical.to_installation_id, {
        kind: "open_awaiting_transfer",
        installationId: historical.to_installation_id,
        orgId: input.orgId,
        bindingEpoch: oldDestination.epoch,
        transferId: historical.transfer_id,
        nowIso: now,
      });
      const sourceFence = await callCoverageDo(env, historical.from_installation_id, {
        kind: "set_transfer_pending",
        installationId: historical.from_installation_id,
        orgId: input.orgId,
        bindingEpoch: oldSource.epoch,
        transferId: historical.transfer_id,
        nowIso: now,
      });
      if (destinationFence?.result !== "ok" || sourceFence?.result !== "ok") {
        await env.DB.prepare(
          `INSERT OR IGNORE INTO transfer_route_quarantine
             (transfer_id, grant_id, reason, created_at)
           VALUES (?, '', 'legacy_transfer_fence_ambiguous', ?)`,
        ).bind(historical.transfer_id, now).run();
        return "bad_request";
      }
    } else {
      const pkg = JSON.parse(historical.package!) as unknown;
      if (!Array.isArray(pkg)) return "bad_request";
      const manifest = await readTransferRouteManifest(env.DB, historical.transfer_id);
      const origins = pkg.flatMap((row) =>
        typeof row === "object" && row !== null && !Array.isArray(row) &&
        typeof (row as Record<string, unknown>).origin_grant_id === "string"
          ? [(row as Record<string, unknown>).origin_grant_id as string]
          : [],
      );
      if (origins.some((grantId) => !manifest.has(grantId))) {
        await env.DB.prepare(
          `INSERT OR IGNORE INTO transfer_route_quarantine
             (transfer_id, grant_id, reason, created_at)
           VALUES (?, '', 'legacy_transfer_manifest_ambiguous', ?)`,
        ).bind(historical.transfer_id, await clockNowIso(env)).run();
        return "bad_request";
      }
    }
    const now = await clockNowIso(env);
    const acceptedCommand = JSON.stringify({
      contract_version: input.contractVersion,
      org_id: input.orgId,
      from_installation_id: historical.from_installation_id,
      source_epoch: oldSource.epoch,
      to_installation_id: historical.to_installation_id,
      destination_epoch: oldDestination.epoch,
      reason: historical.reason,
      actor: input.acceptedActor,
      signer_credential_id: input.signerCredentialId,
      upgrade_recovery: true,
    });
    try {
      await env.DB.prepare(
        `INSERT INTO transfer_preparation (
           transfer_id, org_id, from_installation_id, source_epoch,
           to_installation_id, destination_epoch, reason, assertion_sha256,
           accepted_actor, accepted_signer_credential_id, accepted_command,
           phase, due_at, created_at, updated_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      ).bind(
        historical.transfer_id, input.orgId, historical.from_installation_id,
        oldSource.epoch, historical.to_installation_id, oldDestination.epoch,
        historical.reason, historical.assertion_sha256, input.acceptedActor,
        input.signerCredentialId, acceptedCommand,
        oldIn === null ? "published" : "completed", now, now, now,
      ).run();
    } catch {
      return "bad_request";
    }
    return historical;
  }

  const source = await readSourceBinding(env.DB, input.orgId, input.fromInstallationId);
  if (source === null) return "bad_request";
  const inProgress = await env.DB.prepare(
    `SELECT 1 AS pending FROM transfer t
     WHERE t.org_id = ? AND NOT EXISTS (
       SELECT 1 FROM transfer_step s WHERE s.transfer_id = t.transfer_id AND s.step = 'transfer_in'
     ) LIMIT 1`,
  ).bind(input.orgId).first<{ pending: number }>();
  if (inProgress !== null) return "bad_request";
  const routes = await env.DB.prepare(
    `SELECT grant_id, state FROM live_value_route
     WHERE org_id = ? AND installation_id = ? AND state IN ('stable', 'moving', 'voiding')`,
  ).bind(input.orgId, input.fromInstallationId).all<{ grant_id: string; state: string }>();
  if ((routes.results ?? []).some((row) => row.state !== "stable")) return "bad_request";

  const createdAt = await clockNowIso(env);
  const transferId = generateUlid();
  const destinationId = crypto.randomUUID();
  const destinationEpoch = (await readMaxEpoch(env.DB, input.orgId)) + 1;
  const acceptedCommand = JSON.stringify({
    contract_version: input.contractVersion,
    org_id: input.orgId,
    from_installation_id: input.fromInstallationId,
    source_epoch: source.epoch,
    to_installation_id: destinationId,
    destination_epoch: destinationEpoch,
    reason: input.reason,
    actor: input.acceptedActor,
    signer_credential_id: input.signerCredentialId,
  });
  const auditId = generateUlid();
  const auditTarget = `${input.orgId}:${input.fromInstallationId}`;
  try {
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO transfer_preparation (
           transfer_id, org_id, from_installation_id, source_epoch,
           to_installation_id, destination_epoch, reason, assertion_sha256,
           accepted_actor, accepted_signer_credential_id, accepted_command,
           phase, due_at, lease_until, created_at, updated_at
         ) SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'accepted', ?, NULL, ?, ?
         WHERE EXISTS (
           SELECT 1 FROM tenant_binding WHERE org_id = ? AND installation_id = ?
             AND epoch = ? AND status IN ('active', 'held_for_transfer')
         )
           AND NOT EXISTS (
             SELECT 1 FROM tenant_binding WHERE org_id = ? AND epoch >= ?
               AND status IN ('active', 'held_for_transfer')
           )
           AND NOT EXISTS (
             SELECT 1 FROM transfer_preparation WHERE org_id = ? AND destination_epoch >= ?
           )
           AND NOT EXISTS (
             SELECT 1 FROM deletion_command WHERE org_id = ? AND phase <> 'completed'
           )`,
      ).bind(
        transferId, input.orgId, input.fromInstallationId, source.epoch,
        destinationId, destinationEpoch, input.reason, input.assertionSha256,
        input.acceptedActor, input.signerCredentialId, acceptedCommand,
        createdAt, createdAt, createdAt,
        input.orgId, input.fromInstallationId, source.epoch,
        input.orgId, destinationEpoch, input.orgId, destinationEpoch, input.orgId,
      ),
      env.DB.prepare(
        `INSERT INTO assertion_used (challenge_sha256, credential_id, used_at)
         SELECT ?, ?, ? WHERE EXISTS (
           SELECT 1 FROM transfer_preparation WHERE assertion_sha256 = ?
         )`,
      ).bind(input.assertionSha256, input.signerCredentialId, createdAt, input.assertionSha256),
      env.DB.prepare(
        `INSERT INTO control_audit (
           audit_id, operator_id, actor, action, target, before_pointer,
           after_pointer, assertion_sha256, recorded_at
         ) SELECT ?, ?, ?, 'beginTransfer', ?, NULL, NULL, ?, ?
         WHERE EXISTS (SELECT 1 FROM transfer_preparation WHERE assertion_sha256 = ?)`,
      ).bind(auditId, input.acceptedActor, input.acceptedActor, auditTarget,
        input.assertionSha256, createdAt, input.assertionSha256),
    ]);
  } catch {
    const raced = await readTransferPreparationByAssertion(env.DB, input.assertionSha256);
    if (
      raced === null ||
      raced.org_id !== input.orgId ||
      raced.from_installation_id !== input.fromInstallationId ||
      raced.reason !== input.reason ||
      raced.accepted_actor !== input.acceptedActor ||
      raced.accepted_signer_credential_id !== input.signerCredentialId
    ) return "bad_request";
    let racedCommand: Record<string, unknown>;
    try {
      racedCommand = JSON.parse(raced.accepted_command) as Record<string, unknown>;
    } catch {
      return "bad_request";
    }
    if (racedCommand.contract_version !== input.contractVersion) return "bad_request";
    return resumeTransferPreparation(env, raced.transfer_id);
  }
  return resumeTransferPreparation(env, transferId);
}

export async function resumeTransferPreparation(
  env: TransferEnv,
  transferId: string,
): Promise<TransferRow | "bad_request" | "transient"> {
  const preparation = await env.DB.prepare(
    `SELECT * FROM transfer_preparation WHERE transfer_id = ?`,
  ).bind(transferId).first<TransferPreparationRow>();
  if (preparation === null) return "bad_request";
  if (preparation.phase === "published" || preparation.phase === "completed") {
    return await readTransferById(env.DB, transferId) ?? "bad_request";
  }

  if (preparation.phase === "accepted") {
    const opened = await callCoverageDo(env, preparation.to_installation_id, {
      kind: "open_awaiting_transfer",
      transferId,
      bindingEpoch: preparation.destination_epoch,
    });
    if (opened?.result !== "ok") return "transient";
    const nowIso = await clockNowIso(env);
    await env.DB.prepare(
      `UPDATE transfer_preparation SET phase = 'destination_ready', due_at = ?, updated_at = ?
       WHERE transfer_id = ? AND phase = 'accepted'`,
    ).bind(nowIso, nowIso, transferId).run();
  }

  const latest = await env.DB.prepare(
    `SELECT * FROM transfer_preparation WHERE transfer_id = ?`,
  ).bind(transferId).first<TransferPreparationRow>();
  if (latest === null) return "bad_request";
  if (latest.phase === "destination_ready") {
    const deletionFence = await env.DB.prepare(
      `SELECT freeze_id FROM deletion_command
       WHERE org_id = ? AND installation_id = ? AND binding_epoch = ?
         AND phase = 'completed' AND held = 1
       ORDER BY updated_at DESC LIMIT 1`,
    ).bind(latest.org_id, latest.from_installation_id, latest.source_epoch)
      .first<{ freeze_id: string }>();
    const frozen = await callCoverageDo(env, latest.from_installation_id, {
      kind: "set_transfer_pending",
      transferId,
      adoptDeletionId: deletionFence?.freeze_id,
      bindingEpoch: latest.source_epoch,
    });
    if (frozen?.result !== "ok") return "transient";
    const nowIso = await clockNowIso(env);
    await env.DB.prepare(
      `UPDATE transfer_preparation SET phase = 'source_frozen', due_at = ?, updated_at = ?
       WHERE transfer_id = ? AND phase = 'destination_ready'`,
    ).bind(nowIso, nowIso, transferId).run();
  }

  const ready = await env.DB.prepare(
    `SELECT * FROM transfer_preparation WHERE transfer_id = ?`,
  ).bind(transferId).first<TransferPreparationRow>();
  if (ready === null) return "bad_request";
  if (ready.phase === "published") return await readTransferById(env.DB, transferId) ?? "bad_request";
  if (ready.phase !== "source_frozen") return "transient";

  const nowIso = await clockNowIso(env);
  const routeRows = await env.DB.prepare(
    `SELECT grant_id, generation, state FROM live_value_route
     WHERE org_id = ? AND installation_id = ? AND state IN ('stable', 'moving', 'voiding')`,
  ).bind(ready.org_id, ready.from_installation_id).all<{
    grant_id: string; generation: number; state: string;
  }>();
  const routes = routeRows.results ?? [];
  if (routes.some((row) => row.state !== "stable")) return "transient";
  try {
    await env.DB.batch([
    ...routes.map((row) => env.DB.prepare(
      `UPDATE live_value_route SET state = 'moving', transfer_id = ?, reversal_id = NULL, updated_at = ?
       WHERE grant_id = ? AND state = 'stable' AND generation = ? AND installation_id = ?`,
    ).bind(transferId, nowIso, row.grant_id, row.generation, ready.from_installation_id)),
    env.DB.prepare(
      `UPDATE tenant_binding SET status = 'retired', retired_at = ?, reason = ?
       WHERE org_id = ? AND installation_id = ? AND epoch = ?
         AND status IN ('active', 'held_for_transfer')
         AND NOT EXISTS (
           SELECT 1 FROM live_value_route WHERE org_id = ? AND installation_id = ?
             AND (state IN ('stable', 'voiding') OR (state = 'moving' AND transfer_id <> ?))
         )`,
    ).bind(nowIso, ready.reason, ready.org_id, ready.from_installation_id,
      ready.source_epoch, ready.org_id, ready.from_installation_id, transferId),
    env.DB.prepare(
      `INSERT INTO installation (installation_id, org_id, status, display_name, region, enrolled_at)
       SELECT ?, ?, 'active', '', '', ?
       WHERE EXISTS (SELECT 1 FROM tenant_binding WHERE org_id = ? AND installation_id = ?
         AND epoch = ? AND status = 'retired' AND retired_at = ?)
       AND NOT EXISTS (SELECT 1 FROM installation WHERE installation_id = ?)`,
    ).bind(ready.to_installation_id, ready.org_id, nowIso, ready.org_id,
      ready.from_installation_id, ready.source_epoch, nowIso, ready.to_installation_id),
    env.DB.prepare(
      `INSERT INTO tenant_binding (org_id, installation_id, epoch, status, retired_at, reason, created_at)
       SELECT ?, ?, ?, 'active', NULL, NULL, ?
       WHERE EXISTS (SELECT 1 FROM installation WHERE installation_id = ? AND org_id = ?)
       AND NOT EXISTS (SELECT 1 FROM tenant_binding WHERE org_id = ? AND installation_id = ?)`,
    ).bind(ready.org_id, ready.to_installation_id, ready.destination_epoch, nowIso,
      ready.to_installation_id, ready.org_id, ready.org_id, ready.to_installation_id),
    env.DB.prepare(
      `INSERT INTO transfer (
         transfer_id, org_id, from_installation_id, to_installation_id,
         reason, assertion_sha256, package, created_at
       ) SELECT ?, ?, ?, ?, ?, ?, NULL, ?
       WHERE EXISTS (SELECT 1 FROM tenant_binding WHERE org_id = ? AND installation_id = ?
         AND epoch = ? AND status = 'active')
       AND EXISTS (SELECT 1 FROM tenant_binding WHERE org_id = ? AND installation_id = ?
         AND epoch = ? AND status = 'retired' AND retired_at = ?)
       AND NOT EXISTS (SELECT 1 FROM live_value_route WHERE org_id = ? AND installation_id = ?
         AND (state IN ('stable', 'voiding') OR (state = 'moving' AND transfer_id <> ?)))`,
    ).bind(transferId, ready.org_id, ready.from_installation_id, ready.to_installation_id,
      ready.reason, ready.assertion_sha256, nowIso, ready.org_id, ready.to_installation_id,
      ready.destination_epoch, ready.org_id, ready.from_installation_id,
      ready.source_epoch, nowIso, ready.org_id, ready.from_installation_id, transferId),
    env.DB.prepare(
      `UPDATE transfer_preparation SET phase = 'published', due_at = ?, updated_at = ?
       WHERE transfer_id = ? AND phase = 'source_frozen'
         AND EXISTS (SELECT 1 FROM transfer WHERE transfer_id = ?)`,
    ).bind(nowIso, nowIso, transferId, transferId),
    ]);
  } catch {
    return await readTransferById(env.DB, transferId) ?? "transient";
  }
  return await readTransferById(env.DB, transferId) ?? "transient";
}

export async function dispatchTransferPreparations(
  env: TransferEnv,
  limit = 25,
): Promise<number> {
  const now = await clockNowIso(env);
  const rows = await env.DB.prepare(
    `SELECT transfer_id FROM transfer_preparation
     WHERE phase NOT IN ('published', 'completed') AND due_at <= ?
       AND (lease_until IS NULL OR lease_until <= ?)
     ORDER BY due_at, transfer_id LIMIT ?`,
  ).bind(now, now, Math.max(1, Math.min(100, limit))).all<{ transfer_id: string }>();
  let dispatched = 0;
  for (const row of rows.results ?? []) {
    const token = generateUlid();
    const claimedAt = await clockNowIso(env);
    const leaseUntil = new Date(Date.parse(claimedAt) + 4 * 60 * 1000).toISOString();
    await env.DB.prepare(
      `UPDATE transfer_preparation SET lease_token = ?, lease_until = ?
       WHERE transfer_id = ? AND phase NOT IN ('published', 'completed') AND due_at <= ?
         AND (lease_until IS NULL OR lease_until <= ?)`,
    ).bind(token, leaseUntil, row.transfer_id, claimedAt, claimedAt).run();
    const claimed = await env.DB.prepare(
      `SELECT lease_token FROM transfer_preparation WHERE transfer_id = ?`,
    ).bind(row.transfer_id).first<{ lease_token: string | null }>();
    if (claimed?.lease_token !== token) continue;
    dispatched += 1;
    const result = await resumeTransferPreparation(env, row.transfer_id);
    const nextAt = await clockNowIso(env);
    await env.DB.prepare(
      `UPDATE transfer_preparation SET due_at = ?, lease_token = NULL, lease_until = NULL,
         updated_at = ? WHERE transfer_id = ? AND lease_token = ?`,
    ).bind(new Date(Date.parse(nextAt) + 5 * 60 * 1000).toISOString(),
      nextAt, row.transfer_id, token).run();
    if (result !== "transient") {
      await env.DB.prepare(
        `UPDATE transfer_preparation SET due_at = ?, lease_token = NULL, lease_until = NULL,
           updated_at = ? WHERE transfer_id = ? AND lease_token = ?`,
      ).bind(nextAt, nextAt, row.transfer_id, token).run();
    }
  }
  return dispatched;
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

  if (transfer.package !== null) {
    const restored = await restoreTransferOutStepFromDo(env, vendorContractVersion, transfer);
    if (restored !== null) {
      return {
        result: "already_applied",
        detail: transfer.package,
        receipt: JSON.parse(restored.receipt) as Record<string, unknown>,
      };
    }
    return { result: "rejected", code: "transfer_route_quarantined" };
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
  if (sourceBinding === null) return { result: "bad_request" };
  const pendingAccounting = await env.DB.prepare(
    `SELECT COUNT(*) AS count FROM ai_request
     WHERE installation_id = ? AND accounting_state = 'pending'`,
  ).bind(transfer.from_installation_id).first<{ count: number }>();
  const pendingFallback = await env.DB.prepare(
    `SELECT COUNT(*) AS count FROM fallback_admission
     WHERE installation_id = ? AND state = 'pending'`,
  ).bind(transfer.from_installation_id).first<{ count: number }>();
  if ((pendingAccounting?.count ?? 0) > 0 || (pendingFallback?.count ?? 0) > 0) {
    return { result: "transient", detail: "transfer_accounting_pending" };
  }

  const doResponse = await callCoverageDo(env, transfer.from_installation_id, {
    kind: "transfer_out",
    installationId: transfer.from_installation_id,
    orgId: transfer.org_id,
    vendorContractVersion,
    bindingEpoch: sourceBinding.epoch,
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
  if (doResponse.result === "transient") {
    return {
      result: "transient",
      detail: typeof doResponse.detail === "string" ? doResponse.detail : "transfer_accounting_pending",
    };
  }
  if (doResponse.result !== "applied" && doResponse.result !== "already_applied") {
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
      .prepare(`UPDATE transfer SET package = ? WHERE transfer_id = ? AND (package IS NULL OR package = ?)`)
      .bind(packageJson, transferId, packageJson),
    env.DB
      .prepare(
        `INSERT OR IGNORE INTO transfer_step (transfer_id, step, receipt, applied_at)
         VALUES (?, 'transfer_out', ?, ?)`,
      )
      .bind(transferId, receiptJson, appliedAt),
    ...routeManifest.map((row) => env.DB.prepare(
      `INSERT OR IGNORE INTO transfer_route_manifest (
         transfer_id, grant_id, source_epoch, source_generation
       ) VALUES (?, ?, ?, ?)`,
    ).bind(transferId, row.grant_id, row.binding_epoch, row.generation)),
    ...routeSettleStatements,
  ]);

  const storedTransfer = await readTransferById(env.DB, transferId);
  const storedStep = await readTransferStep(env.DB, transferId, "transfer_out");
  const storedManifest = await readTransferRouteManifest(env.DB, transferId);
  if (
    storedTransfer?.package !== packageJson || storedStep === null ||
    await sha256Hex(canonicalize(JSON.parse(storedStep.receipt))) !==
      await sha256Hex(canonicalize(receiptRaw)) ||
    routeManifest.some((row) => {
      const stored = storedManifest.get(row.grant_id);
      return stored === undefined || stored.source_epoch !== row.binding_epoch ||
        stored.source_generation !== row.generation;
    })
  ) {
    return { result: "rejected", code: "transfer_route_quarantined" };
  }

  return {
    result: doResponse.result,
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

  let outStep = await readTransferStep(env.DB, transferId, "transfer_out");
  if (outStep === null && transfer.package !== null) {
    outStep = await restoreTransferOutStepFromDo(env, vendorContractVersion, transfer);
  }
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
    await env.DB.prepare(
      `UPDATE transfer_preparation SET phase = 'completed', updated_at = ?
       WHERE transfer_id = ? AND phase = 'published'`,
    ).bind(await clockNowIso(env), transferId).run();
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

  if (doResponse === null ||
      (doResponse.result !== "applied" && doResponse.result !== "already_applied")) {
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
      `INSERT OR IGNORE INTO transfer_step (transfer_id, step, receipt, applied_at)
       VALUES (?, 'transfer_in', ?, ?)`,
    )
    .bind(transferId, receiptJson, appliedAt)
    .run();
  const storedIn = await readTransferStep(env.DB, transferId, "transfer_in");
  if (
    storedIn === null ||
    await sha256Hex(canonicalize(JSON.parse(storedIn.receipt))) !==
      await sha256Hex(canonicalize(receiptRaw))
  ) {
    return { result: "rejected", code: "transfer_route_quarantined" };
  }
  await env.DB.prepare(
    `UPDATE transfer_preparation SET phase = 'completed', updated_at = ?
     WHERE transfer_id = ? AND phase = 'published'`,
  ).bind(appliedAt, transferId).run();

  await raiseAl11Transfer(env, transferId, transfer.org_id);

  return {
    result: doResponse.result === "already_applied" ? "already_applied" : "applied",
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

type InspectedCoverage = {
  terms: Array<{ term_id: string; state: string }>;
  reservations: ReservationInventoryRow[];
};

type ReservationInventoryRow = {
  id: string;
  weight: number;
  term_id: string;
  capability: string;
  admitted_at: number;
};

function isReservationInventoryRow(value: unknown): value is ReservationInventoryRow {
  return isRecord(value) && typeof value.id === "string" &&
    typeof value.weight === "number" && Number.isFinite(value.weight) &&
    typeof value.term_id === "string" && typeof value.capability === "string" &&
    typeof value.admitted_at === "number" && Number.isFinite(value.admitted_at);
}

async function inspectInstallationCoverage(
  env: TransferEnv,
  installationId: string,
  orgId: string,
): Promise<InspectedCoverage | null> {
  const inspected = await callCoverageDo(env, installationId, {
    kind: "inspect_coverage",
    installationId,
    orgId,
    vendorContractVersion: CHANNEL_VERSIONS.platformDo,
  });
  if (
    inspected === null || !Array.isArray(inspected.terms) ||
    !Array.isArray(inspected.reservations) ||
    inspected.terms.some((row) => !isRecord(row) ||
      typeof row.term_id !== "string" || typeof row.state !== "string") ||
    !inspected.reservations.every(isReservationInventoryRow)
  ) {
    return null;
  }
  return {
    terms: inspected.terms as Array<{ term_id: string; state: string }>,
    reservations: inspected.reservations,
  };
}

type DeletionCommandRow = {
  assertion_sha256: string;
  freeze_id: string;
  org_id: string;
  installation_id: string;
  binding_epoch: number;
  reason: string;
  accepted_actor: string;
  signer_credential_id: string;
  accepted_command: string;
  phase: "accepted" | "frozen" | "completed";
  freeze_inventory: string | null;
  freeze_ack_at: string | null;
  retained_term_ids: string | null;
  held: number | null;
  alert_due: number;
  purge_state: "due" | "completed";
  completion_detail: string | null;
};

export async function readDeletionCommand(
  db: D1Database,
  assertionSha256: string,
): Promise<DeletionCommandRow | null> {
  return db.prepare(
    `SELECT assertion_sha256, freeze_id, org_id, installation_id, binding_epoch, reason,
            accepted_actor, signer_credential_id, accepted_command, phase,
            freeze_inventory, freeze_ack_at, retained_term_ids, held, alert_due, purge_state,
            completion_detail
     FROM deletion_command WHERE assertion_sha256 = ?`,
  ).bind(assertionSha256).first<DeletionCommandRow>();
}

export async function acceptDeleteInstallation(
  env: TransferEnv,
  input: {
    orgId: string;
    reason: string;
    operatorId: string;
    assertionSha256: string;
    signerCredentialId: string;
    acceptedCommand: string;
  },
): Promise<
  | { result: "accepted"; assertionSha256: string }
  | { result: "bad_request" }
> {
  const pendingPreparation = await env.DB.prepare(
    `SELECT pending.transfer_id FROM (
       SELECT transfer_id FROM transfer_preparation
         WHERE org_id = ? AND phase <> 'completed'
       UNION ALL
       SELECT t.transfer_id FROM transfer t
         WHERE t.org_id = ? AND NOT EXISTS (
           SELECT 1 FROM transfer_step s
           WHERE s.transfer_id = t.transfer_id AND s.step = 'transfer_in'
         )
     ) pending LIMIT 1`,
  ).bind(input.orgId, input.orgId).first<{ transfer_id: string }>();
  if (pendingPreparation !== null) return { result: "bad_request" };
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

  const nowIso = await clockNowIso(env);
  const auditId = generateUlid();
  if (installation.status === "deleted") {
    const completed = await env.DB.prepare(
      `SELECT assertion_sha256, freeze_id, freeze_inventory, freeze_ack_at, retained_term_ids,
              held, completion_detail
       FROM deletion_command
       WHERE org_id = ? AND installation_id = ? AND binding_epoch = ?
         AND reason = ? AND phase = 'completed' AND purge_state = 'completed'
       ORDER BY created_at LIMIT 1`,
    ).bind(input.orgId, binding.installation_id, binding.epoch, input.reason)
      .first<Pick<DeletionCommandRow,
        "assertion_sha256" | "freeze_id" | "freeze_inventory" | "freeze_ack_at" |
        "retained_term_ids" | "held" | "completion_detail">>();
    if (completed?.completion_detail === null || completed === null) {
      return { result: "bad_request" };
    }
    try {
      await env.DB.batch([
        env.DB.prepare(
          `INSERT INTO deletion_command (
             assertion_sha256, freeze_id, org_id, installation_id, binding_epoch, reason,
             accepted_actor, signer_credential_id, accepted_command, phase,
             freeze_inventory, freeze_ack_at, retained_term_ids, held, alert_due,
             purge_state, completion_detail, due_at, lease_until, created_at, updated_at
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'completed', ?, ?, ?, ?, 0,
             'completed', ?, ?, NULL, ?, ?)`,
        ).bind(
          input.assertionSha256, completed.freeze_id, input.orgId, binding.installation_id, binding.epoch,
          input.reason, input.operatorId, input.signerCredentialId, input.acceptedCommand,
          completed.freeze_inventory, completed.freeze_ack_at, completed.retained_term_ids,
          completed.held, completed.completion_detail, nowIso, nowIso, nowIso,
        ),
        env.DB.prepare(
          `INSERT INTO assertion_used (challenge_sha256, credential_id, used_at)
           SELECT ?, ?, ? WHERE EXISTS (
             SELECT 1 FROM deletion_command WHERE assertion_sha256 = ?
           )`,
        ).bind(input.assertionSha256, input.signerCredentialId, nowIso, input.assertionSha256),
        env.DB.prepare(
          `INSERT INTO control_audit (
             audit_id, operator_id, actor, action, target, before_pointer,
             after_pointer, assertion_sha256, recorded_at
           ) SELECT ?, ?, ?, 'deleteInstallation', ?, NULL, NULL, ?, ?
           WHERE EXISTS (
             SELECT 1 FROM deletion_command WHERE assertion_sha256 = ?
           )`,
        ).bind(auditId, input.operatorId, input.operatorId,
          `${input.orgId}:${binding.installation_id}`, input.assertionSha256,
          nowIso, input.assertionSha256),
      ]);
    } catch {
      // The exact accepted command is read back and checked below.
    }
    const repeated = await readDeletionCommand(env.DB, input.assertionSha256);
    if (
      repeated === null || repeated.phase !== "completed" ||
      repeated.completion_detail !== completed.completion_detail ||
      repeated.accepted_command !== input.acceptedCommand
    ) return { result: "bad_request" };
    return { result: "accepted", assertionSha256: input.assertionSha256 };
  }

  try {
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO deletion_command (
           assertion_sha256, freeze_id, org_id, installation_id, binding_epoch, reason,
           accepted_actor, signer_credential_id, accepted_command, phase,
           freeze_inventory, freeze_ack_at, retained_term_ids, held, alert_due,
           purge_state, completion_detail, due_at, lease_until, created_at, updated_at
         ) SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, 'accepted', NULL, NULL, NULL, NULL, 0,
           'due', NULL, ?, NULL, ?, ?
         WHERE EXISTS (
           SELECT 1 FROM tenant_binding WHERE org_id = ? AND installation_id = ?
             AND epoch = ? AND status IN ('active', 'held_for_transfer')
         )
           AND NOT EXISTS (SELECT 1 FROM deletion_command WHERE org_id = ? AND phase <> 'completed')
           AND NOT EXISTS (SELECT 1 FROM transfer_preparation WHERE org_id = ? AND phase <> 'completed')
           AND NOT EXISTS (
             SELECT 1 FROM transfer t WHERE t.org_id = ? AND NOT EXISTS (
               SELECT 1 FROM transfer_step s WHERE s.transfer_id = t.transfer_id AND s.step = 'transfer_in'
             )
           )`,
      ).bind(
        input.assertionSha256, input.assertionSha256, input.orgId, binding.installation_id, binding.epoch,
        input.reason, input.operatorId, input.signerCredentialId, input.acceptedCommand,
        nowIso, nowIso, nowIso,
        input.orgId, binding.installation_id, binding.epoch,
        input.orgId, input.orgId, input.orgId,
      ),
      env.DB.prepare(
        `INSERT INTO assertion_used (challenge_sha256, credential_id, used_at)
         SELECT ?, ?, ? WHERE EXISTS (
           SELECT 1 FROM deletion_command WHERE assertion_sha256 = ?
         )`,
      ).bind(input.assertionSha256, input.signerCredentialId, nowIso, input.assertionSha256),
      env.DB.prepare(
        `INSERT INTO control_audit (
           audit_id, operator_id, actor, action, target, before_pointer,
           after_pointer, assertion_sha256, recorded_at
         ) SELECT ?, ?, ?, 'deleteInstallation', ?, NULL, NULL, ?, ?
         WHERE EXISTS (
           SELECT 1 FROM deletion_command WHERE assertion_sha256 = ?
         )`,
      ).bind(
        auditId, input.operatorId, input.operatorId,
        `${input.orgId}:${binding.installation_id}`, input.assertionSha256,
        nowIso, input.assertionSha256,
      ),
    ]);
  } catch {
    // Exact retries are resolved by the assertion-digest keyed command below.
  }
  const accepted = await readDeletionCommand(env.DB, input.assertionSha256);
  if (
    accepted === null || accepted.org_id !== input.orgId ||
    accepted.installation_id !== binding.installation_id ||
    accepted.binding_epoch !== binding.epoch || accepted.reason !== input.reason ||
    accepted.accepted_actor !== input.operatorId ||
    accepted.signer_credential_id !== input.signerCredentialId ||
    accepted.accepted_command !== input.acceptedCommand
  ) return { result: "bad_request" };
  return { result: "accepted", assertionSha256: input.assertionSha256 };
}

export async function resumeDeleteInstallation(
  env: TransferEnv,
  assertionSha256: string,
): Promise<{ result: "ok"; detail: string } | { result: "transient" | "bad_request" }> {
  const command = await readDeletionCommand(env.DB, assertionSha256);
  if (command === null) return { result: "bad_request" };
  if (command.phase === "completed" && command.completion_detail !== null) {
    return { result: "ok", detail: command.completion_detail };
  }

  if (command.phase === "accepted") {
    let acceptedCommand: Record<string, unknown>;
    try { acceptedCommand = JSON.parse(command.accepted_command) as Record<string, unknown>; }
    catch { return { result: "transient" }; }
    if (
      typeof acceptedCommand.accepted_at !== "string" ||
      typeof acceptedCommand.snapshot_version !== "number" ||
      !(acceptedCommand.duration_scale === null || acceptedCommand.duration_scale === "staging")
    ) return { result: "transient" };
    const nowIso = acceptedCommand.accepted_at;
    const frozen = await callCoverageDo(env, command.installation_id, {
      kind: "set_transfer_pending",
      transferId: command.freeze_id,
      installationId: command.installation_id,
      orgId: command.org_id,
      bindingEpoch: command.binding_epoch,
      vendorContractVersion: acceptedCommand.snapshot_version,
      nowIso,
      durationScale: acceptedCommand.duration_scale,
    });
    if (
      frozen?.result !== "ok" || !Array.isArray(frozen.terms) ||
      !Array.isArray(frozen.reservations) ||
      frozen.terms.some((row) => !isRecord(row) || typeof row.term_id !== "string" ||
        typeof row.state !== "string") ||
      !frozen.reservations.every(isReservationInventoryRow)
    ) return { result: "transient" };
    const openTerms = (frozen.terms as Array<{ term_id: string; state: string }>)
      .filter((term) => termIsNotEnded(term.state));
    const reservations = frozen.reservations as ReservationInventoryRow[];
    const termIds = [...new Set([
      ...openTerms.map((term) => term.term_id),
      ...reservations.map((reservation) => reservation.term_id),
    ])];
    const held = termIds.length > 0 || reservations.length > 0;
    const inventory = JSON.stringify({
      terms: frozen.terms,
      reservations,
    });
    const retiredAt = held ? null : nowIso;
    const bindingStatus = held ? "held_for_transfer" : "retired";
    await env.DB.batch([
      env.DB.prepare(
        `UPDATE installation SET status = 'deleted'
         WHERE installation_id = ? AND EXISTS (
           SELECT 1 FROM tenant_binding WHERE org_id = ? AND installation_id = ?
             AND epoch = ? AND status IN ('active', 'held_for_transfer')
         )`,
      ).bind(command.installation_id, command.org_id, command.installation_id, command.binding_epoch),
      env.DB.prepare(
        `UPDATE tenant_binding SET status = ?, retired_at = ?, reason = ?
         WHERE org_id = ? AND installation_id = ? AND epoch = ?
           AND status IN ('active', 'held_for_transfer')`,
      ).bind(bindingStatus, retiredAt, held ? null : command.reason,
        command.org_id, command.installation_id, command.binding_epoch),
      env.DB.prepare(
        `UPDATE deletion_command
         SET phase = 'frozen', freeze_inventory = ?, freeze_ack_at = ?,
             retained_term_ids = ?, held = ?, alert_due = ?, due_at = ?, updated_at = ?
         WHERE assertion_sha256 = ? AND phase = 'accepted'
           AND EXISTS (SELECT 1 FROM tenant_binding WHERE org_id = ?
             AND installation_id = ? AND epoch = ? AND status = ?)`,
      ).bind(inventory, nowIso, JSON.stringify(termIds), held ? 1 : 0, held ? 1 : 0,
        nowIso, nowIso, assertionSha256, command.org_id, command.installation_id,
        command.binding_epoch, bindingStatus),
    ]);
  }

  const frozenCommand = await readDeletionCommand(env.DB, assertionSha256);
  if (frozenCommand === null) return { result: "bad_request" };
  if (frozenCommand.phase === "completed" && frozenCommand.completion_detail !== null) {
    return { result: "ok", detail: frozenCommand.completion_detail };
  }
  if (frozenCommand.phase !== "frozen" || frozenCommand.retained_term_ids === null) {
    return { result: "transient" };
  }
  const binding = await readBindingRow(env.DB, frozenCommand.org_id, frozenCommand.installation_id);
  const installation = await readInstallationRow(env.DB, frozenCommand.installation_id);
  if (
    binding === null || installation === null || binding.epoch !== frozenCommand.binding_epoch ||
    installation.status !== "deleted" ||
      (frozenCommand.held === 1
        ? !["held_for_transfer", "retired"].includes(binding.status)
        : binding.status !== "retired")
  ) return { result: "transient" };

  if (frozenCommand.alert_due === 1) {
    await raiseAl18HeldBinding(env, frozenCommand.org_id, frozenCommand.installation_id);
    await env.DB.prepare(
      `UPDATE deletion_command SET alert_due = 0, updated_at = ?
       WHERE assertion_sha256 = ? AND phase = 'frozen'`,
    ).bind(await clockNowIso(env), assertionSha256).run();
  }

  const retainedTermIds = JSON.parse(frozenCommand.retained_term_ids) as unknown;
  if (!Array.isArray(retainedTermIds) || retainedTermIds.some((id) => typeof id !== "string")) {
    return { result: "transient" };
  }
  try {
    await purgeByInstallationId(frozenCommand.installation_id, frozenCommand.accepted_actor, {
      db: env.DB,
      r2: env.R2,
      auditId: `rm27-delete-purge:${assertionSha256}`,
      preserveUsageTermIds: retainedTermIds as string[],
    });
  } catch {
    return { result: "transient" };
  }
  const finalInstallation = await readInstallationRow(env.DB, frozenCommand.installation_id);
  const finalBinding = await readBindingRow(env.DB, frozenCommand.org_id, frozenCommand.installation_id);
  if (finalInstallation === null || finalBinding === null) return { result: "transient" };
  const detail = installationDeleteDetail(finalInstallation, finalBinding);
  const completedAt = await clockNowIso(env);
  await env.DB.prepare(
    `UPDATE deletion_command SET phase = 'completed', purge_state = 'completed',
       completion_detail = ?, due_at = ?, updated_at = ?
     WHERE assertion_sha256 = ? AND phase = 'frozen' AND purge_state = 'due'`,
  ).bind(detail, completedAt, completedAt, assertionSha256).run();
  const completed = await readDeletionCommand(env.DB, assertionSha256);
  if (completed?.phase !== "completed" || completed.completion_detail === null) {
    return { result: "transient" };
  }
  return { result: "ok", detail: completed.completion_detail };
}

export async function dispatchDeletionCommands(env: TransferEnv, limit = 25): Promise<number> {
  const nowIso = await clockNowIso(env);
  const rows = await env.DB.prepare(
    `SELECT assertion_sha256 FROM deletion_command
     WHERE phase <> 'completed' AND due_at <= ?
       AND (lease_until IS NULL OR lease_until <= ?)
     ORDER BY due_at, created_at LIMIT ?`,
  ).bind(nowIso, nowIso, limit).all<{ assertion_sha256: string }>();
  let attempted = 0;
  for (const row of rows.results ?? []) {
    attempted += 1;
    await resumeDeleteInstallation(env, row.assertion_sha256);
  }
  return attempted;
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
  const inspected = await inspectInstallationCoverage(
    env,
    installationId,
    orgId,
  );
  // Unknown or malformed DO state is never proof of emptiness.
  if (
    inspected === null || inspected.reservations.length > 0 ||
    inspected.terms.some((row) => termIsNotEnded(row.state))
  ) {
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
