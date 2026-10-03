import { WorkerEntrypoint } from "cloudflare:workers";
import {
  CHANNEL_VERSIONS,
  canonicalize,
  negotiate,
  parseRegistrationAttestation,
  sha256Hex,
  validateOperation,
  verifyAccessJwt,
  verifyAssertion,
  type AccessCertsDocument,
  type Assertion,
} from "vendor-contracts";
import {
  raiseAl13,
  raiseAl13Bootstrap,
  raiseAl13IssuerKey,
} from "../alert/index";
import {
  clockNowIso,
  clockNowMs,
  clockNowSeconds,
  type ClockEnv,
} from "../clock";
import { writeEntrypointAudit } from "../control/audit";

const VENDOR_CHANNEL = CHANNEL_VERSIONS.vendorEntrypoint;
const ACTIVATION_MS = 24 * 60 * 60 * 1000;
const ASSERTION_FRESHNESS_MS = 5 * 60 * 1000;

const METHOD_CLASS = {
  registerOperatorCredential: "HP",
  revokeOperatorCredential: "HP",
  registerIssuerKey: "HP",
  retireIssuerKey: "HP",
  revokeIssuerKey: "HP",
  listOperatorCredentials: "M",
  listIssuerKeys: "M",
} as const;

type VendorMethod = keyof typeof METHOD_CLASS;

type HpVendorMethod = {
  [K in VendorMethod]: (typeof METHOD_CLASS)[K] extends "HP" ? K : never;
}[VendorMethod];

type VendorResultEnvelope = {
  contract_version: number;
  result: "ok" | "rejected" | "conflict";
  code: string;
  detail: string;
};

type VendorEnv = ClockEnv & {
  DB: D1Database;
  ISSUER_ID: string;
  ACCESS_TEAM_DOMAIN: string;
  ACCESS_AUD: string;
  WEBAUTHN_RP_ID: string;
  WEBAUTHN_ORIGIN: string;
  ALERT_EMAIL_TO: string;
  SEND_EMAIL: {
    send(message: {
      from: string;
      to: string;
      subject: string;
      text: string;
    }): Promise<void>;
  };
};

type OperatorCredentialRow = {
  credential_id: string;
  operator_email: string;
  public_key_cose: string;
  alg: string;
  status: string;
  activates_at: string;
  approved_by: string | null;
  revoked_by: string | null;
};

type IssuerKeyRow = {
  kid: string;
  issuer: string;
  public_key: string;
  status: string;
  not_before: string;
  not_after: string;
  registered_by: string;
  assertion_sha256: string;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseRequestedVersion(
  args: Record<string, unknown>,
): number | null {
  const raw = args.contract_version;
  if (raw === undefined || raw === null) {
    return null;
  }
  if (!Number.isInteger(raw)) {
    return null;
  }
  return raw as number;
}

function rejected(
  contractVersion: number,
  code: string,
  detail = "",
): VendorResultEnvelope {
  return {
    contract_version: contractVersion,
    result: "rejected",
    code,
    detail,
  };
}

function ok(contractVersion: number, detail: string): VendorResultEnvelope {
  return {
    contract_version: contractVersion,
    result: "ok",
    code: "",
    detail,
  };
}

function conflict(contractVersion: number, code: string): VendorResultEnvelope {
  return {
    contract_version: contractVersion,
    result: "conflict",
    code,
    detail: "",
  };
}

function rowToDetail(row: OperatorCredentialRow): string {
  const ordered = {
    credential_id: row.credential_id,
    operator_email: row.operator_email,
    public_key_cose: row.public_key_cose,
    alg: row.alg,
    status: row.status,
    activates_at: row.activates_at,
    approved_by: row.approved_by,
    revoked_by: row.revoked_by,
  };
  return JSON.stringify(ordered);
}

function issuerKeyRowToDetail(row: IssuerKeyRow): string {
  const ordered = {
    kid: row.kid,
    issuer: row.issuer,
    public_key: row.public_key,
    status: row.status,
    not_before: row.not_before,
    not_after: row.not_after,
    registered_by: row.registered_by,
    assertion_sha256: row.assertion_sha256,
  };
  return JSON.stringify(ordered);
}

function isValidEd25519PublicKeyEncoding(publicKey: string): boolean {
  const decoded = base64UrlDecode(publicKey);
  return decoded !== null && decoded.length === 32;
}

async function readIssuerKey(
  db: D1Database,
  kid: string,
): Promise<IssuerKeyRow | null> {
  return db
    .prepare(
      `SELECT kid, issuer, public_key, status, not_before, not_after,
              registered_by, assertion_sha256
       FROM issuer_key WHERE kid = ?`,
    )
    .bind(kid)
    .first<IssuerKeyRow>();
}

function base64UrlDecode(segment: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]*$/u.test(segment)) {
    return null;
  }
  const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
  try {
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  } catch {
    return null;
  }
}

function decodeAssertion(
  value: unknown,
): Assertion | null {
  if (!isRecord(value)) {
    return null;
  }
  const alg = value.alg;
  if (alg !== "ES256" && alg !== "EdDSA") {
    return null;
  }
  if (
    typeof value.authenticator_data !== "string" ||
    typeof value.client_data_json !== "string" ||
    typeof value.signature !== "string"
  ) {
    return null;
  }
  const authenticatorData = base64UrlDecode(value.authenticator_data);
  const clientDataJSON = base64UrlDecode(value.client_data_json);
  const signature = base64UrlDecode(value.signature);
  if (
    authenticatorData === null ||
    clientDataJSON === null ||
    signature === null
  ) {
    return null;
  }
  return {
    alg,
    authenticatorData,
    clientDataJSON,
    signature,
  };
}

function decodeAttestation(value: unknown): { alg: "ES256" | "EdDSA"; publicKey: Uint8Array } | null {
  if (!isRecord(value)) {
    return null;
  }
  if (value.alg !== "ES256" && value.alg !== "EdDSA") {
    return null;
  }
  if (typeof value.public_key !== "string") {
    return null;
  }
  const publicKey = base64UrlDecode(value.public_key);
  if (publicKey === null) {
    return null;
  }
  return { alg: value.alg, publicKey };
}

async function loadAccessCerts(env: VendorEnv): Promise<AccessCertsDocument | null> {
  const issuer = `https://${env.ACCESS_TEAM_DOMAIN}`;
  const url = `${issuer}/cdn-cgi/access/certs`;
  try {
    const response = await fetch(url);
    if (!response.ok) {
      return null;
    }
    const body = (await response.json()) as { keys?: AccessCertsDocument["keys"] };
    if (!Array.isArray(body.keys)) {
      return null;
    }
    return { issuer, keys: body.keys };
  } catch {
    return null;
  }
}

async function verifyHpAccess(
  env: VendorEnv,
  accessJwt: unknown,
): Promise<{ ok: true; email: string } | { ok: false }> {
  if (typeof accessJwt !== "string" || accessJwt.length === 0) {
    return { ok: false };
  }
  const certs = await loadAccessCerts(env);
  if (certs === null) {
    return { ok: false };
  }
  const nowSeconds = await clockNowSeconds(env);
  return verifyAccessJwt({
    jwt: accessJwt,
    certs,
    aud: env.ACCESS_AUD,
    nowSeconds,
  });
}

async function operatorCredentialCount(db: D1Database): Promise<number> {
  const row = await db
    .prepare("SELECT COUNT(*) AS count FROM operator_credential")
    .first<{ count: number }>();
  return row?.count ?? 0;
}

async function readOperatorCredential(
  db: D1Database,
  credentialId: string,
): Promise<OperatorCredentialRow | null> {
  return db
    .prepare(
      `SELECT credential_id, operator_email, public_key_cose, alg, status,
              activates_at, approved_by, revoked_by
       FROM operator_credential WHERE credential_id = ?`,
    )
    .bind(credentialId)
    .first<OperatorCredentialRow>();
}

async function promoteCredentialIfDue(
  env: VendorEnv,
  row: OperatorCredentialRow,
): Promise<OperatorCredentialRow> {
  if (row.status !== "pending") {
    return row;
  }
  const nowIso = await clockNowIso(env);
  if (row.activates_at > nowIso) {
    return row;
  }
  await env.DB.prepare(
    `UPDATE operator_credential SET status = 'active'
     WHERE credential_id = ? AND status = 'pending'`,
  )
    .bind(row.credential_id)
    .run();
  const updated = await readOperatorCredential(env.DB, row.credential_id);
  return updated ?? { ...row, status: "active" };
}

async function promoteAllDueCredentials(env: VendorEnv): Promise<void> {
  const nowIso = await clockNowIso(env);
  await env.DB.prepare(
    `UPDATE operator_credential SET status = 'active'
     WHERE status = 'pending' AND activates_at <= ?`,
  )
    .bind(nowIso)
    .run();
}

async function operationAssertionSha256(
  operation: Record<string, unknown>,
): Promise<string> {
  return sha256Hex(canonicalize(operation));
}

async function assertionChallengeUsed(
  db: D1Database,
  challengeSha256: string,
): Promise<boolean> {
  const row = await db
    .prepare("SELECT challenge_sha256 FROM assertion_used WHERE challenge_sha256 = ?")
    .bind(challengeSha256)
    .first<{ challenge_sha256: string }>();
  return row !== null;
}

async function insertAssertionUsed(
  env: VendorEnv,
  challengeSha256: string,
  credentialId: string,
): Promise<void> {
  const usedAt = await clockNowIso(env);
  await env.DB.prepare(
    `INSERT INTO assertion_used (challenge_sha256, credential_id, used_at)
     VALUES (?, ?, ?)`,
  )
    .bind(challengeSha256, credentialId, usedAt)
    .run();
}

async function importSignerPublicKey(
  row: OperatorCredentialRow,
): Promise<CryptoKey | null> {
  const publicKeyBytes = base64UrlDecode(row.public_key_cose);
  if (publicKeyBytes === null) {
    return null;
  }
  const alg = row.alg === "ES256" || row.alg === "EdDSA" ? row.alg : null;
  if (alg === null) {
    return null;
  }
  const parsed = await parseRegistrationAttestation({
    alg,
    publicKey: publicKeyBytes,
  });
  return parsed.ok ? parsed.publicKey : null;
}

function stableJson(value: unknown): string {
  return JSON.stringify(value);
}

function operationParamsMatch(
  method: HpVendorMethod,
  operation: Record<string, unknown>,
  rpcArgs: Record<string, unknown>,
  accessJwt: string,
  negotiatedVersion: number,
): boolean {
  if (operation.op !== method) {
    return false;
  }
  if (operation.contract_version !== negotiatedVersion) {
    return false;
  }
  if (!isRecord(operation.params)) {
    return false;
  }
  const params = operation.params;
  const expected: Record<string, unknown> = {
    contract_version: negotiatedVersion,
    access_jwt: accessJwt,
  };
  if (method === "registerOperatorCredential") {
    expected.credential_id = rpcArgs.credential_id;
    expected.attestation = rpcArgs.attestation;
    if (rpcArgs.signer_credential_id !== undefined) {
      expected.signer_credential_id = rpcArgs.signer_credential_id;
    }
  } else if (method === "revokeOperatorCredential") {
    expected.credential_id = rpcArgs.credential_id;
    expected.signer_credential_id = rpcArgs.signer_credential_id;
  } else if (method === "registerIssuerKey") {
    expected.kid = rpcArgs.kid;
    expected.public_key = rpcArgs.public_key;
    expected.not_before = rpcArgs.not_before;
    expected.not_after = rpcArgs.not_after;
  } else if (method === "retireIssuerKey" || method === "revokeIssuerKey") {
    expected.kid = rpcArgs.kid;
  } else {
    return false;
  }
  return stableJson(params) === stableJson(expected);
}

function hpAuditTarget(
  method: HpVendorMethod,
  rpcArgs: Record<string, unknown>,
): string {
  if (
    method === "registerIssuerKey" ||
    method === "retireIssuerKey" ||
    method === "revokeIssuerKey"
  ) {
    return typeof rpcArgs.kid === "string" ? rpcArgs.kid : "";
  }
  return typeof rpcArgs.credential_id === "string" ? rpcArgs.credential_id : "";
}

async function assertionIssuedAtFresh(
  env: VendorEnv,
  issuedAt: string,
): Promise<boolean> {
  const issuedMs = Date.parse(issuedAt);
  if (Number.isNaN(issuedMs)) {
    return false;
  }
  const nowMs = await clockNowMs(env);
  return Math.abs(nowMs - issuedMs) <= ASSERTION_FRESHNESS_MS;
}

type HpAssertionReject = {
  ok: false;
  envelope: VendorResultEnvelope;
  auditAssertionSha256: string | null;
  auditTarget: string;
};

type HpAssertionOk = {
  ok: true;
  signer: OperatorCredentialRow;
  operation: Record<string, unknown>;
  assertionSha256: string;
  auditTarget: string;
};

type HpAssertionResult = HpAssertionReject | HpAssertionOk;

async function runHpAssertionChecks(
  env: VendorEnv,
  method: HpVendorMethod,
  rpcArgs: Record<string, unknown>,
  accessEmail: string,
  negotiatedVersion: number,
): Promise<HpAssertionResult> {
  const auditTarget = hpAuditTarget(method, rpcArgs);
  const assertionRaw = rpcArgs.assertion;
  const operationRaw = rpcArgs.operation;
  const signerCredentialId = rpcArgs.signer_credential_id;

  if (assertionRaw === undefined || assertionRaw === null) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_required"),
      auditAssertionSha256: null,
      auditTarget,
    };
  }
  if (typeof signerCredentialId !== "string" || signerCredentialId.length === 0) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: null,
      auditTarget,
    };
  }
  if (!validateOperation(operationRaw).ok) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: null,
      auditTarget,
    };
  }
  const operation = operationRaw as Record<string, unknown>;
  const assertionSha256 = await operationAssertionSha256(operation);
  const accessJwt =
    typeof rpcArgs.access_jwt === "string" ? rpcArgs.access_jwt : "";
  if (!operationParamsMatch(method, operation, rpcArgs, accessJwt, negotiatedVersion)) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  const assertion = decodeAssertion(assertionRaw);
  if (assertion === null) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  let signer = await readOperatorCredential(env.DB, signerCredentialId);
  if (signer === null) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "credential_not_found"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  const publicKey = await importSignerPublicKey(signer);
  if (publicKey === null) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  const verified = await verifyAssertion({
    assertion,
    operation: operationRaw,
    rpId: env.WEBAUTHN_RP_ID,
    origin: env.WEBAUTHN_ORIGIN,
    publicKey,
  });
  if (!verified.ok) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  if (typeof operation.actor_email !== "string") {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }
  if (typeof operation.issued_at !== "string") {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_invalid"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  if (!(await assertionIssuedAtFresh(env, operation.issued_at))) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_expired"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }
  if (operation.actor_email !== accessEmail) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "actor_email_mismatch"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  if (await assertionChallengeUsed(env.DB, assertionSha256)) {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "assertion_used"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  if (signer.status === "revoked") {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "credential_revoked"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  signer = await promoteCredentialIfDue(env, signer);
  if (signer.status !== "active") {
    return {
      ok: false,
      envelope: rejected(negotiatedVersion, "credential_not_active"),
      auditAssertionSha256: assertionSha256,
      auditTarget,
    };
  }

  return {
    ok: true,
    signer,
    operation,
    assertionSha256,
    auditTarget,
  };
}

async function finishHpAssertion(
  env: VendorEnv,
  accessEmail: string,
  method: HpVendorMethod,
  check: HpAssertionOk,
): Promise<void> {
  await insertAssertionUsed(env, check.assertionSha256, check.signer.credential_id);
  await writeEntrypointAudit(
    env.DB,
    accessEmail,
    method,
    check.auditTarget,
    check.assertionSha256,
  );
}

async function rejectHpAssertion(
  env: VendorEnv,
  accessEmail: string,
  method: HpVendorMethod,
  check: HpAssertionReject,
): Promise<VendorResultEnvelope> {
  await writeEntrypointAudit(
    env.DB,
    accessEmail,
    method,
    check.auditTarget,
    check.auditAssertionSha256,
  );
  return check.envelope;
}

async function bootstrapRegister(
  env: VendorEnv,
  rpcArgs: Record<string, unknown>,
  accessEmail: string,
  negotiatedVersion: number,
): Promise<VendorResultEnvelope> {
  const credentialId = rpcArgs.credential_id;
  const attestationRaw = rpcArgs.attestation;
  if (typeof credentialId !== "string" || credentialId.length === 0) {
    return rejected(negotiatedVersion, "assertion_invalid");
  }
  const attestation = decodeAttestation(attestationRaw);
  if (attestation === null) {
    return rejected(negotiatedVersion, "assertion_invalid");
  }
  const parsed = await parseRegistrationAttestation(attestation);
  if (!parsed.ok) {
    return rejected(negotiatedVersion, "assertion_invalid");
  }

  const nowMs = await clockNowMs(env);
  const activatesAt = new Date(nowMs + ACTIVATION_MS).toISOString();
  const publicKeyCose = attestationRaw && isRecord(attestationRaw)
    ? String(attestationRaw.public_key)
    : "";

  await env.DB.prepare(
    `INSERT INTO operator_credential
       (credential_id, operator_email, public_key_cose, alg, status, activates_at, approved_by, revoked_by)
     VALUES (?, ?, ?, ?, 'pending', ?, NULL, NULL)`,
  )
    .bind(credentialId, accessEmail, publicKeyCose, parsed.alg, activatesAt)
    .run();

  const row = await readOperatorCredential(env.DB, credentialId);
  if (row === null) {
    return rejected(negotiatedVersion, "assertion_invalid");
  }

  await writeEntrypointAudit(
    env.DB,
    accessEmail,
    "registerOperatorCredential",
    credentialId,
    null,
  );

  await raiseAl13Bootstrap(env, {
    credentialId,
    operatorEmail: accessEmail,
  });

  return ok(negotiatedVersion, rowToDetail(row));
}

export class VendorEntrypoint extends WorkerEntrypoint<VendorEnv> {
  async registerOperatorCredential(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const hasAssertion =
      args.assertion !== undefined && args.assertion !== null;
    const registrySize = await operatorCredentialCount(this.env.DB);

    if (!hasAssertion) {
      if (registrySize > 0) {
        const target =
          typeof args.credential_id === "string" ? args.credential_id : "";
        await writeEntrypointAudit(
          this.env.DB,
          access.email,
          "registerOperatorCredential",
          target,
          null,
        );
        return rejected(version, "assertion_required");
      }
      return bootstrapRegister(this.env, args, access.email, version);
    }

    const check = await runHpAssertionChecks(
      this.env,
      "registerOperatorCredential",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      return rejectHpAssertion(
        this.env,
        access.email,
        "registerOperatorCredential",
        check,
      );
    }

    const credentialId = args.credential_id;
    const attestationRaw = args.attestation;
    if (typeof credentialId !== "string" || credentialId.length === 0) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "registerOperatorCredential",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "assertion_invalid");
    }
    const attestation = decodeAttestation(attestationRaw);
    if (attestation === null) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "registerOperatorCredential",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "assertion_invalid");
    }
    const parsed = await parseRegistrationAttestation(attestation);
    if (!parsed.ok) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "registerOperatorCredential",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "assertion_invalid");
    }
    const publicKeyCose =
      attestationRaw && isRecord(attestationRaw)
        ? String(attestationRaw.public_key)
        : "";

    const existing = await readOperatorCredential(this.env.DB, credentialId);
    if (existing !== null) {
      if (existing.public_key_cose !== publicKeyCose) {
        await writeEntrypointAudit(
          this.env.DB,
          access.email,
          "registerOperatorCredential",
          check.auditTarget,
          check.assertionSha256,
        );
        return conflict(version, "public_key_cose_mismatch");
      }
      await finishHpAssertion(
        this.env,
        access.email,
        "registerOperatorCredential",
        check,
      );
      return ok(version, rowToDetail(existing));
    }

    await finishHpAssertion(
      this.env,
      access.email,
      "registerOperatorCredential",
      check,
    );

    const nowMs = await clockNowMs(this.env);
    const activatesAt = new Date(nowMs + ACTIVATION_MS).toISOString();
    await this.env.DB.prepare(
      `INSERT INTO operator_credential
         (credential_id, operator_email, public_key_cose, alg, status, activates_at, approved_by, revoked_by)
       VALUES (?, ?, ?, ?, 'pending', ?, ?, NULL)`,
    )
      .bind(
        credentialId,
        access.email,
        publicKeyCose,
        parsed.alg,
        activatesAt,
        access.email,
      )
      .run();

    const row = await readOperatorCredential(this.env.DB, credentialId);
    if (row === null) {
      return rejected(version, "assertion_invalid");
    }

    await raiseAl13(this.env, {
      credentialId,
      operatorEmail: access.email,
      kind: "register",
      operation: check.operation,
    });

    return ok(version, rowToDetail(row));
  }

  async revokeOperatorCredential(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const check = await runHpAssertionChecks(
      this.env,
      "revokeOperatorCredential",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      return rejectHpAssertion(
        this.env,
        access.email,
        "revokeOperatorCredential",
        check,
      );
    }

    const targetId = args.credential_id;
    if (typeof targetId !== "string" || targetId.length === 0) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "revokeOperatorCredential",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "credential_not_found");
    }
    const target = await readOperatorCredential(this.env.DB, targetId);
    if (target === null) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "revokeOperatorCredential",
        targetId,
        check.assertionSha256,
      );
      return rejected(version, "credential_not_found");
    }

    await finishHpAssertion(
      this.env,
      access.email,
      "revokeOperatorCredential",
      check,
    );

    if (target.status !== "revoked") {
      await this.env.DB.prepare(
        `UPDATE operator_credential SET status = 'revoked', revoked_by = ?
         WHERE credential_id = ?`,
      )
        .bind(access.email, targetId)
        .run();
    }

    const row = await readOperatorCredential(this.env.DB, targetId);
    if (row === null) {
      return rejected(version, "credential_not_found");
    }

    await raiseAl13(this.env, {
      credentialId: targetId,
      operatorEmail: row.operator_email,
      kind: "revoke",
      operation: check.operation,
    });

    return ok(version, rowToDetail(row));
  }

  async listOperatorCredentials(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    await promoteAllDueCredentials(this.env);

    const { results } = await this.env.DB.prepare(
      `SELECT credential_id, public_key_cose, alg
       FROM operator_credential
       WHERE status = 'active'
       ORDER BY credential_id ASC`,
    ).all<{ credential_id: string; public_key_cose: string; alg: string }>();

    const keys = (results ?? []).map((row) => ({
      credential_id: row.credential_id,
      public_key_cose: row.public_key_cose,
      alg: row.alg,
    }));

    return ok(version, JSON.stringify(keys));
  }

  async registerIssuerKey(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const check = await runHpAssertionChecks(
      this.env,
      "registerIssuerKey",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      return rejectHpAssertion(
        this.env,
        access.email,
        "registerIssuerKey",
        check,
      );
    }

    const kid = args.kid;
    const publicKey = args.public_key;
    const notBefore = args.not_before;
    const notAfter = args.not_after;
    if (
      typeof kid !== "string" ||
      kid.length === 0 ||
      typeof publicKey !== "string" ||
      typeof notBefore !== "string" ||
      notBefore.length === 0 ||
      typeof notAfter !== "string" ||
      notAfter.length === 0
    ) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "registerIssuerKey",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "assertion_invalid");
    }

    if (!isValidEd25519PublicKeyEncoding(publicKey)) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "registerIssuerKey",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "public_key_invalid");
    }

    const existing = await readIssuerKey(this.env.DB, kid);
    if (existing !== null) {
      if (existing.public_key !== publicKey) {
        await writeEntrypointAudit(
          this.env.DB,
          access.email,
          "registerIssuerKey",
          check.auditTarget,
          check.assertionSha256,
        );
        return conflict(version, "public_key_mismatch");
      }
      await finishHpAssertion(
        this.env,
        access.email,
        "registerIssuerKey",
        check,
      );
      return ok(version, issuerKeyRowToDetail(existing));
    }

    await finishHpAssertion(
      this.env,
      access.email,
      "registerIssuerKey",
      check,
    );

    await this.env.DB.prepare(
      `INSERT INTO issuer_key
         (kid, issuer, public_key, status, not_before, not_after, registered_by, assertion_sha256)
       VALUES (?, ?, ?, 'active', ?, ?, ?, ?)`,
    )
      .bind(
        kid,
        this.env.ISSUER_ID,
        publicKey,
        notBefore,
        notAfter,
        access.email,
        check.assertionSha256,
      )
      .run();

    const row = await readIssuerKey(this.env.DB, kid);
    if (row === null) {
      return rejected(version, "assertion_invalid");
    }

    await raiseAl13IssuerKey(this.env, {
      kid,
      kind: "register",
      operation: check.operation,
    });

    return ok(version, issuerKeyRowToDetail(row));
  }

  async listIssuerKeys(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const { results } = await this.env.DB.prepare(
      `SELECT kid, public_key, status, not_before, not_after
       FROM issuer_key
       WHERE status IN ('active', 'retiring')
       ORDER BY kid ASC`,
    ).all<{
      kid: string;
      public_key: string;
      status: string;
      not_before: string;
      not_after: string;
    }>();

    const keys = (results ?? []).map((row) => ({
      kid: row.kid,
      public_key: row.public_key,
      status: row.status,
      not_before: row.not_before,
      not_after: row.not_after,
    }));

    return ok(version, JSON.stringify(keys));
  }

  async retireIssuerKey(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const check = await runHpAssertionChecks(
      this.env,
      "retireIssuerKey",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      return rejectHpAssertion(
        this.env,
        access.email,
        "retireIssuerKey",
        check,
      );
    }

    const kid = args.kid;
    if (typeof kid !== "string" || kid.length === 0) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "retireIssuerKey",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "kid_not_found");
    }

    const existing = await readIssuerKey(this.env.DB, kid);
    if (existing === null) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "retireIssuerKey",
        kid,
        check.assertionSha256,
      );
      return rejected(version, "kid_not_found");
    }

    if (existing.status === "revoked") {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "retireIssuerKey",
        kid,
        check.assertionSha256,
      );
      return rejected(version, "kid_revoked");
    }

    await finishHpAssertion(
      this.env,
      access.email,
      "retireIssuerKey",
      check,
    );

    if (existing.status === "active") {
      await this.env.DB.prepare(
        `UPDATE issuer_key SET status = 'retiring' WHERE kid = ?`,
      )
        .bind(kid)
        .run();
    }

    const row = await readIssuerKey(this.env.DB, kid);
    if (row === null) {
      return rejected(version, "kid_not_found");
    }

    await raiseAl13IssuerKey(this.env, {
      kid,
      kind: "retire",
      operation: check.operation,
    });

    return ok(version, issuerKeyRowToDetail(row));
  }

  async revokeIssuerKey(
    args: Record<string, unknown>,
  ): Promise<VendorResultEnvelope> {
    const requested = parseRequestedVersion(args);
    const negotiated = negotiate(VENDOR_CHANNEL, requested);
    if (!negotiated.ok) {
      return rejected(VENDOR_CHANNEL, negotiated.code);
    }
    const version = negotiated.version;

    const access = await verifyHpAccess(this.env, args.access_jwt);
    if (!access.ok) {
      return rejected(version, "unauthenticated");
    }

    const check = await runHpAssertionChecks(
      this.env,
      "revokeIssuerKey",
      args,
      access.email,
      version,
    );
    if (!check.ok) {
      return rejectHpAssertion(
        this.env,
        access.email,
        "revokeIssuerKey",
        check,
      );
    }

    const kid = args.kid;
    if (typeof kid !== "string" || kid.length === 0) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "revokeIssuerKey",
        check.auditTarget,
        check.assertionSha256,
      );
      return rejected(version, "kid_not_found");
    }

    const existing = await readIssuerKey(this.env.DB, kid);
    if (existing === null) {
      await writeEntrypointAudit(
        this.env.DB,
        access.email,
        "revokeIssuerKey",
        kid,
        check.assertionSha256,
      );
      return rejected(version, "kid_not_found");
    }

    await finishHpAssertion(
      this.env,
      access.email,
      "revokeIssuerKey",
      check,
    );

    if (existing.status !== "revoked") {
      await this.env.DB.prepare(
        `UPDATE issuer_key SET status = 'revoked' WHERE kid = ?`,
      )
        .bind(kid)
        .run();
    }

    const row = await readIssuerKey(this.env.DB, kid);
    if (row === null) {
      return rejected(version, "kid_not_found");
    }

    await raiseAl13IssuerKey(this.env, {
      kid,
      kind: "revoke",
      operation: check.operation,
    });

    return ok(version, issuerKeyRowToDetail(row));
  }
}
