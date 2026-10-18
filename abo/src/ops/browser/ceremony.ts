/**
 * Console passkey ceremony producer (R2-P4 / R2-ABO-03).
 *
 * Pure helpers that build exactly the operations the ABO console signs:
 * the six ABO-local HP actions (the frozen R2-P1 param maps), the
 * first-credential bootstrap registration, and the reusable platform-HP
 * preparation interface (including the explicit bound
 * `ceiling_override_operation` form required after RM04's R2-P2).
 *
 * The browser shell (`./shell.ts`) embeds the same frozen descriptors and
 * glue as source-bundled JavaScript; the field names here are the single
 * source of truth for both.
 */

import {
  canonicalize,
  CHANNEL_VERSIONS,
  sha256Hex,
  validateOperation,
} from "vendor-contracts";

/** Wire shape of an operator assertion operation (04 §1.5). */
export type HpOperationWire = {
  op: string;
  params: Record<string, unknown>;
  actor_email: string;
  issued_at: string;
  nonce: string;
  contract_version: number;
};

export type LocalHpActionId =
  | "publish_offer"
  | "retire_offer"
  | "reinstate_offer"
  | "release_payment"
  | "manual_chargeback"
  | "erase_contact";

export type LocalHpActionField = {
  /** Form field name in the console shell. */
  name: string;
  /** `string` (nonempty), `integer` (positive safe integer) or `text` (nonempty). */
  kind: "string" | "integer" | "text";
  /** Human label rendered next to the input. */
  label: string;
  /** Dot path inside the signed params this input fills. */
  paramPath: string;
};

export type LocalHpActionDescriptor = {
  action: LocalHpActionId;
  /** Route template with the signed subject placeholder (04 §2.2). */
  routeTemplate: string;
  /** Signed params field that must equal the route subject (R2-P1). */
  subjectKey: string;
  /** The exact signed-param key set, frozen by R2-P1. */
  paramKeys: readonly string[];
  fields: readonly LocalHpActionField[];
};

export type CeremonyCredential = {
  credential_id: string;
  alg: string;
};

export function base64UrlDecode(segment: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]*$/u.test(segment)) {
    return null;
  }
  const base64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4);
  try {
    return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
  } catch {
    return null;
  }
}

export function base64UrlEncodeBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/u, "");
}

function bytesEqual(bytes: Uint8Array, other: Uint8Array): boolean {
  if (bytes.byteLength !== other.byteLength) {
    return false;
  }
  for (let index = 0; index < bytes.byteLength; index += 1) {
    if (bytes[index] !== other[index]) {
      return false;
    }
  }
  return true;
}

function nonEmptyText(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function setParamPath(
  params: Record<string, unknown>,
  path: string,
  value: unknown,
): void {
  const segments = path.split(".");
  let cursor: Record<string, unknown> = params;
  for (let index = 0; index < segments.length - 1; index += 1) {
    const segment = segments[index]!;
    const existing = cursor[segment];
    if (
      typeof existing !== "object" ||
      existing === null ||
      Array.isArray(existing)
    ) {
      cursor[segment] = {};
    }
    cursor = cursor[segment] as Record<string, unknown>;
  }
  cursor[segments[segments.length - 1]!] = value;
}

/** The six ABO-local HP actions with their R2-P1 frozen maps. */
export const LOCAL_HP_ACTIONS: readonly LocalHpActionDescriptor[] = [
  {
    action: "publish_offer",
    routeTemplate: "/ops/offers/{subject}/publish",
    subjectKey: "offer_id",
    paramKeys: ["offer_id", "price_minor", "terms_text", "copy"],
    fields: [
      {
        name: "subject",
        kind: "string",
        label: "Offer ID",
        paramPath: "offer_id",
      },
      {
        name: "price_minor",
        kind: "integer",
        label: "Price (minor units)",
        paramPath: "price_minor",
      },
      {
        name: "terms_text",
        kind: "text",
        label: "Terms text",
        paramPath: "terms_text",
      },
      {
        name: "copy_name",
        kind: "string",
        label: "Display name (en)",
        paramPath: "copy.en.name",
      },
      {
        name: "copy_summary",
        kind: "string",
        label: "Summary (en)",
        paramPath: "copy.en.summary",
      },
    ],
  },
  {
    action: "retire_offer",
    routeTemplate: "/ops/offers/{subject}/retire",
    subjectKey: "offer_id",
    paramKeys: ["offer_id"],
    fields: [
      {
        name: "subject",
        kind: "string",
        label: "Offer ID",
        paramPath: "offer_id",
      },
    ],
  },
  {
    action: "reinstate_offer",
    routeTemplate: "/ops/offers/{subject}/reinstate",
    subjectKey: "offer_id",
    paramKeys: ["offer_id"],
    fields: [
      {
        name: "subject",
        kind: "string",
        label: "Offer ID",
        paramPath: "offer_id",
      },
    ],
  },
  {
    action: "release_payment",
    routeTemplate: "/ops/payments/{subject}/release",
    subjectKey: "payment_id",
    paramKeys: ["payment_id"],
    fields: [
      {
        name: "subject",
        kind: "string",
        label: "Payment ID",
        paramPath: "payment_id",
      },
    ],
  },
  {
    action: "manual_chargeback",
    routeTemplate: "/ops/payments/{subject}/chargeback",
    subjectKey: "payment_id",
    paramKeys: ["payment_id"],
    fields: [
      {
        name: "subject",
        kind: "string",
        label: "Payment ID",
        paramPath: "payment_id",
      },
    ],
  },
  {
    action: "erase_contact",
    routeTemplate: "/ops/orgs/{subject}/erase-contact",
    subjectKey: "org_id",
    paramKeys: ["org_id"],
    fields: [
      {
        name: "subject",
        kind: "string",
        label: "Org ID",
        paramPath: "org_id",
      },
    ],
  },
];

export function localHpAction(
  action: LocalHpActionId,
): LocalHpActionDescriptor {
  const found = LOCAL_HP_ACTIONS.find(
    (descriptor) => descriptor.action === action,
  );
  if (found === undefined) {
    throw new TypeError(`Unknown local HP action: ${action}`);
  }
  return found;
}

export function localHpActionOrNull(
  action: string,
): LocalHpActionDescriptor | null {
  const found = LOCAL_HP_ACTIONS.find(
    (descriptor) => descriptor.action === action,
  );
  return found ?? null;
}

export function localHpRoute(action: LocalHpActionId, subject: string): string {
  return localHpAction(action).routeTemplate.replace("{subject}", subject);
}

/**
 * R2-P1 receiver-side validation: the signed params must carry the exact
 * frozen key set for the action and must bind the route subject, so a
 * legitimate assertion for one target can never authorize a different
 * URL-selected target. Used by `verifyHpRequest` before replay consumption.
 */
export function signedHpParamsBound(
  op: string,
  params: Record<string, unknown>,
  subject: string,
): boolean {
  const descriptor = localHpActionOrNull(op);
  if (descriptor === null) {
    return false;
  }
  const keys = Object.keys(params);
  if (keys.length !== descriptor.paramKeys.length) {
    return false;
  }
  for (const key of descriptor.paramKeys) {
    if (!Object.prototype.hasOwnProperty.call(params, key)) {
      return false;
    }
  }
  const signedSubject = params[descriptor.subjectKey];
  return typeof signedSubject === "string" && signedSubject === subject;
}

/**
 * Build the exact frozen signed params for a local HP action from form
 * values. Returns null when a required field is missing or malformed; the
 * caller then rejects before starting any ceremony.
 */
export function buildLocalHpParams(
  action: LocalHpActionId,
  values: Record<string, string>,
): { params: Record<string, unknown>; subject: string } | null {
  const descriptor = localHpAction(action);
  const subject = nonEmptyText(values.subject);
  if (subject === null) {
    return null;
  }
  const params: Record<string, unknown> = {};
  for (const field of descriptor.fields) {
    const value = values[field.name];
    if (typeof value !== "string" || value.trim().length === 0) {
      return null;
    }
    if (field.kind === "integer") {
      const parsed = Number(value.trim());
      if (!Number.isInteger(parsed) || parsed <= 0) {
        return null;
      }
      setParamPath(params, field.paramPath, parsed);
    } else {
      setParamPath(params, field.paramPath, value.trim());
    }
  }
  const paramKeys = Object.keys(params);
  if (paramKeys.length !== descriptor.paramKeys.length) {
    return null;
  }
  for (const key of descriptor.paramKeys) {
    if (!Object.prototype.hasOwnProperty.call(params, key)) {
      return null;
    }
  }
  if (params[descriptor.subjectKey] !== subject) {
    return null;
  }
  return { params, subject };
}

/** Strict values validator for a local ceremony before any passkey touch. */
export function validateLocalHpValues(
  action: LocalHpActionId,
  values: Record<string, string>,
): boolean {
  return buildLocalHpParams(action, values) !== null;
}

/** Build the complete operation object the passkey signs (04 §1.5). */
export function buildOperation(input: {
  op: string;
  params: Record<string, unknown>;
  actorEmail: string;
  contractVersion: number;
  issuedAt?: string;
  nonce?: string;
}): HpOperationWire | null {
  const operation: HpOperationWire = {
    op: input.op,
    params: input.params,
    actor_email: input.actorEmail,
    issued_at: input.issuedAt ?? new Date().toISOString(),
    nonce: input.nonce ?? crypto.randomUUID(),
    contract_version: input.contractVersion,
  };
  return validateOperation(operation).ok ? operation : null;
}

/** Prebuild a local HP ceremony: params, subject, route and operation. */
export function buildLocalHpCeremony(input: {
  action: LocalHpActionId;
  values: Record<string, string>;
  actorEmail: string;
  contractVersion: number;
  issuedAt?: string;
  nonce?: string;
}): { operation: HpOperationWire; subject: string; route: string } | null {
  const bound = buildLocalHpParams(input.action, input.values);
  if (bound === null) {
    return null;
  }
  const operation = buildOperation({
    op: input.action,
    params: bound.params,
    actorEmail: input.actorEmail,
    contractVersion: input.contractVersion,
    issuedAt: input.issuedAt,
    nonce: input.nonce,
  });
  if (operation === null) {
    return null;
  }
  return {
    operation,
    subject: bound.subject,
    route: localHpRoute(input.action, bound.subject),
  };
}

/** Raw SHA-256 digest over the canonical operation (the WebAuthn challenge). */
export async function operationChallengeBytes(
  operation: HpOperationWire,
): Promise<Uint8Array | null> {
  if (validateOperation(operation).ok !== true) {
    return null;
  }
  const hexDigest = await sha256Hex(canonicalize(operation));
  const bytes = new Uint8Array(hexDigest.length / 2);
  for (let index = 0; index < bytes.byteLength; index += 1) {
    bytes[index] = Number.parseInt(
      hexDigest.slice(index * 2, index * 2 + 2),
      16,
    );
  }
  return bytes;
}

/** The exact `navigator.credentials.get` request for a ceremony. */
export async function credentialGetRequest(input: {
  operation: HpOperationWire;
  rpId: string;
  credentials: readonly CeremonyCredential[];
}): Promise<{
  publicKey: {
    challenge: Uint8Array;
    rpId: string;
    userVerification: "required";
    allowCredentials: Array<{ id: Uint8Array; type: "public-key" }>;
  };
} | null> {
  const challenge = await operationChallengeBytes(input.operation);
  if (challenge === null) {
    return null;
  }
  const allowCredentials: Array<{ id: Uint8Array; type: "public-key" }> = [];
  for (const credential of input.credentials) {
    const id = base64UrlDecode(credential.credential_id);
    if (
      id === null ||
      (credential.alg !== "ES256" && credential.alg !== "EdDSA")
    ) {
      continue;
    }
    allowCredentials.push({ id, type: "public-key" });
  }
  return {
    publicKey: {
      challenge,
      rpId: input.rpId,
      userVerification: "required",
      allowCredentials,
    },
  };
}

/**
 * Serialize a WebAuthn `get` result into the wire assertion consumed by the
 * existing `decodeAssertion`. The credential id must match one of the
 * ceremony-context credentials; its `alg` is the assertion's `alg`.
 */
export function serializeAssertion(input: {
  credentials: readonly CeremonyCredential[];
  rawId: Uint8Array;
  authenticatorData: Uint8Array;
  clientDataJSON: Uint8Array;
  signature: Uint8Array;
}): {
  assertion: {
    alg: "ES256" | "EdDSA";
    authenticator_data: string;
    client_data_json: string;
    signature: string;
  };
  signerCredentialId: string;
} | null {
  const matched = input.credentials.find((credential) => {
    const id = base64UrlDecode(credential.credential_id);
    return id !== null && bytesEqual(id, input.rawId);
  });
  if (matched === undefined) {
    return null;
  }
  if (matched.alg !== "ES256" && matched.alg !== "EdDSA") {
    return null;
  }
  return {
    assertion: {
      alg: matched.alg,
      authenticator_data: base64UrlEncodeBytes(input.authenticatorData),
      client_data_json: base64UrlEncodeBytes(input.clientDataJSON),
      signature: base64UrlEncodeBytes(input.signature),
    },
    signerCredentialId: matched.credential_id,
  };
}

/**
 * Reusable platform-HP preparation (R2-P4 step 4): accept an explicitly
 * validated method-argument map, the applicable vendor channel version,
 * and build the operation the platform's `operationParamsMatch` expects.
 * The caller keeps the operation unchanged through submission; R8 supplies
 * the exact per-method forms and policy. The method-argument map must
 * already contain the exact fields the platform method binds (including
 * `access_jwt` and `envelope` where those methods require them).
 */
export function preparePlatformHpOperation(input: {
  op: string;
  methodArgs: Record<string, unknown>;
  actorEmail: string;
  vendorVersion?: number;
  issuedAt?: string;
  nonce?: string;
}): HpOperationWire | null {
  const vendorVersion = input.vendorVersion ?? CHANNEL_VERSIONS.vendorEntrypoint;
  const methodArgs = { ...input.methodArgs };
  if (
    methodArgs.contract_version !== undefined &&
    methodArgs.contract_version !== vendorVersion
  ) {
    return null;
  }
  const operation = buildOperation({
    op: input.op,
    params: {
      contract_version: vendorVersion,
      ...methodArgs,
    },
    actorEmail: input.actorEmail,
    contractVersion: vendorVersion,
    issuedAt: input.issuedAt,
    nonce: input.nonce,
  });
  if (operation === null) {
    return null;
  }
  if (operation.params.contract_version !== vendorVersion) {
    return null;
  }
  return operation;
}

/**
 * The explicit, separately approved `ceiling_override_operation` in the
 * exact bound form the platform accepts after RM04 (R2-P2): op
 * `ceiling_override`, top-level negotiated vendor version, params exactly
 * `{contract_version, access_jwt, envelope}` where the envelope is the
 * grant envelope minus `ceiling_override`, and the same Access actor. Only
 * `issued_at` and `nonce` are free for the separate ceremony.
 */
export function buildCeilingOverrideOperation(input: {
  actorEmail: string;
  accessJwt: string;
  envelope: Record<string, unknown>;
  vendorVersion?: number;
  issuedAt?: string;
  nonce?: string;
}): HpOperationWire | null {
  const vendorVersion = input.vendorVersion ?? CHANNEL_VERSIONS.vendorEntrypoint;
  const envelope: Record<string, unknown> = { ...input.envelope };
  delete envelope.ceiling_override;
  return buildOperation({
    op: "ceiling_override",
    params: {
      contract_version: vendorVersion,
      access_jwt: input.accessJwt,
      envelope,
    },
    actorEmail: input.actorEmail,
    contractVersion: vendorVersion,
    issuedAt: input.issuedAt,
    nonce: input.nonce,
  });
}