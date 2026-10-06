import {
  CHANNEL_VERSIONS,
  canonicalize,
  receiptSigningBytes,
  sha256Hex,
  signCompactJws,
} from "vendor-contracts";
import { raiseAl11Transfer, raiseAl18HeldBinding, type CoverageAlertEnv } from "../alert/index";
import { clockNowIso, type ClockEnv } from "../clock";
import { purgeByInstallationId } from "../retention/index";
import { generateUlid } from "../trace";

type TransferEnv = ClockEnv &
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
    return (await response.json()) as Record<string, unknown>;
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

  await env.DB.batch([
    env.DB
      .prepare(
        `UPDATE tenant_binding
         SET status = 'retired', retired_at = ?, reason = ?
         WHERE org_id = ? AND installation_id = ?
           AND status IN ('active', 'held_for_transfer')`,
      )
      .bind(createdAt, input.reason, input.orgId, input.fromInstallationId),
    env.DB
      .prepare(
        `INSERT INTO installation (
           installation_id, org_id, status, display_name, region, enrolled_at
         ) VALUES (?, ?, 'active', '', '', ?)`,
      )
      .bind(newInstallationId, input.orgId, createdAt),
    env.DB
      .prepare(
        `INSERT INTO tenant_binding (
           org_id, installation_id, epoch, status, retired_at, reason, created_at
         ) VALUES (?, ?, ?, 'active', NULL, NULL, ?)`,
      )
      .bind(input.orgId, newInstallationId, nextEpoch, createdAt),
    env.DB
      .prepare(
        `INSERT INTO transfer (
           transfer_id, org_id, from_installation_id, to_installation_id,
           reason, assertion_sha256, package, created_at
         ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?)`,
      )
      .bind(
        transferId,
        input.orgId,
        input.fromInstallationId,
        newInstallationId,
        input.reason,
        input.assertionSha256,
        createdAt,
      ),
  ]);

  const opened = await callCoverageDo(env, newInstallationId, {
    kind: "open_awaiting_transfer",
    bindingEpoch: nextEpoch,
  });
  if (opened === null || opened.result !== "ok") {
    return "bad_request";
  }

  const row = await readTransferById(env.DB, transferId);
  if (row === null) {
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
    const receipt = JSON.parse(existingStep.receipt) as Record<string, unknown>;
    const packageJson =
      transfer.package !== null ? transfer.package : "[]";
    return {
      result: "already_applied",
      detail: packageJson,
      receipt,
    };
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

  const packageJson = JSON.stringify(packageValue);
  const receiptJson = JSON.stringify(receiptRaw);
  const appliedAt = await clockNowIso(env);

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
  if (existingIn !== null) {
    const receipt = JSON.parse(existingIn.receipt) as Record<string, unknown>;
    const packageJson =
      transfer.package !== null ? transfer.package : "[]";
    return {
      result: "already_applied",
      detail: packageJson,
      receipt,
    };
  }

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

async function installationHasOpenCoverage(
  env: TransferEnv,
  installationId: string,
  orgId: string,
): Promise<boolean> {
  const inspected = await callCoverageDo(env, installationId, {
    kind: "inspect_coverage",
    installationId,
    orgId,
    vendorContractVersion: CHANNEL_VERSIONS.platformDo,
  });
  if (inspected === null || !Array.isArray(inspected.terms)) {
    return false;
  }
  return (inspected.terms as Array<{ state?: string }>).some(
    (row) =>
      row.state === "active" ||
      row.state === "grace" ||
      row.state === "queued" ||
      row.state === "held",
  );
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

  await purgeByInstallationId(binding.installation_id, input.operatorId, {
    db: env.DB,
    r2: env.R2,
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
