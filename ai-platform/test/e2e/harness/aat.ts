import { queryOne } from "./d1";
import { AAT_AUDIENCE, TOKEN_CONTRACT_VER } from "./env";
import {
  nowSeconds,
  signJwt,
  type TestKeypair,
} from "./crypto";
import type { Scenario } from "./types";

export type AatClaims = {
  iss: string;
  aud: string;
  sub: string;
  org: string;
  branch: string;
  role: string;
  scopes: string[];
  jti: string;
  iat: number;
  exp: number;
  ver: string;
};

export type MintAatOptions = {
  /** Sign with this keypair (default: `scenario.keypair`). */
  keypair?: TestKeypair;
  /** JWT header `kid`. Defaults to the signing keypair's kid. */
  kid?: string;
  /** JWT header `alg`. Default `EdDSA`. */
  alg?: string;
  /** Extra / overriding header fields (merged after alg/kid defaults). */
  header?: Record<string, unknown>;
  /**
   * Claim overrides. Unspecified claims keep defaults.
   * The live JWT claim is `role` (singular), not `roles`.
   * Pass wrong types or extra keys here — they are serialized as given.
   */
  claims?: Record<string, unknown>;
  /** Delete these claim names after applying defaults + `claims`. */
  omitClaims?: string[];
  /** Delete these header names after applying defaults + `header`. */
  omitHeaderFields?: string[];
  /** Skip waiting for `installation_key.valid_from` (needed for "too soon" cases). */
  skipValidityWait?: boolean;
  /** Replace the signature segment instead of signing. */
  signatureB64?: string;
};

async function ensureInstallationKeyActive(
  installationId: string,
): Promise<void> {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const key = await queryOne<{ valid_from: string }>(
      "SELECT valid_from FROM installation_key WHERE installation_id = ?",
      [installationId],
    );
    const validFromMs = Date.parse(String(key?.valid_from));
    const verifierNowMs = Math.floor(Date.now() / 1000) * 1000;
    if (!Number.isNaN(validFromMs) && verifierNowMs >= validFromMs) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error("installation key not yet within validity window");
}

function defaultClaims(scenario: Scenario): AatClaims {
  const iat = nowSeconds() - 30;
  return {
    iss: scenario.installationId,
    aud: AAT_AUDIENCE,
    sub: scenario.actorId,
    org: scenario.orgId,
    branch: scenario.branchId,
    role: "clinician",
    scopes: ["ai.visit_summary", "ai.access"],
    jti: crypto.randomUUID(),
    iat,
    exp: iat + 330,
    ver: TOKEN_CONTRACT_VER,
  };
}

/**
 * Mint a compact EdDSA JWS signed by the installation key enrolled through
 * the real control-plane enroll path (or `options.keypair` if supplied).
 *
 * Full claim control: `kid` / `alg` (header), `iss`, `aud`, `exp`/`iat`,
 * `ver`, `scopes`, `role`, plus any extra payload keys.
 */
export async function mintAat(
  scenario: Scenario,
  options: MintAatOptions = {},
): Promise<string> {
  if (!options.skipValidityWait) {
    await ensureInstallationKeyActive(scenario.installationId);
  }

  const keypair = options.keypair ?? scenario.keypair;
  const header: Record<string, unknown> = {
    alg: options.alg ?? "EdDSA",
    kid: options.kid ?? keypair.kid,
    ...options.header,
  };
  if (options.alg !== undefined) {
    header.alg = options.alg;
  }
  if (options.kid !== undefined) {
    header.kid = options.kid;
  }
  for (const field of options.omitHeaderFields ?? []) {
    delete header[field];
  }

  const payload: Record<string, unknown> = {
    ...defaultClaims(scenario),
    ...options.claims,
  };
  for (const field of options.omitClaims ?? []) {
    delete payload[field];
  }

  const token = await signJwt({
    header,
    payload,
    privateKey: keypair.privateKey,
  });

  if (options.signatureB64 !== undefined) {
    const parts = token.split(".");
    return `${parts[0]}.${parts[1]}.${options.signatureB64}`;
  }
  return token;
}

export { ensureInstallationKeyActive };
