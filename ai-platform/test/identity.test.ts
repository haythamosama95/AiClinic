import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import migrationSql from "../migrations/20260731120000_platform_schema.sql?raw";
import tokenContractMigrationSql from "../migrations/20260803120000_token_contract.sql?raw";
import { ConfigCache, type D1Reader } from "../src/config-cache";
import {
  EnrolledKeyVerifier,
  type Principal,
  type TokenVerifier,
  type VerifyContext,
  type VerifyResult,
} from "../src/identity";

// ---------------------------------------------------------------------------
// §5.6 claim set (B1 aat-token contract)
// ---------------------------------------------------------------------------

type AatClaims = {
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

type TestKeypair = {
  publicKey: CryptoKey;
  privateKey: CryptoKey;
  kid: string;
  publicKeyB64: string;
  jwk: { kty: "OKP"; crv: "Ed25519"; x: string; kid: string };
};

type ReaderSpy = D1Reader & {
  read: ReturnType<typeof vi.fn<(key: string) => Promise<Record<string, unknown> | "miss">>>;
  readCount: () => number;
};

const AUDIENCE = "ai-platform";
const CLOCK_SKEW_SECONDS = 60;
const NOW = 1_720_000_450;

const FIXTURE_ISS = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
const FIXTURE_ISS_B = "b1b2c3d4-e5f6-7890-abcd-ef1234567891";
const FIXTURE_KID = "f47ac10b-58cc-4372-a567-0e02b2c3d479";
const FIXTURE_KID_B = "a47ac10b-58cc-4372-a567-0e02b2c3d480";
const FIXTURE_SUB = "c1000000-0000-4000-8000-000000000001";
const FIXTURE_ORG = "d2000000-0000-4000-8000-000000000001";
const FIXTURE_BRANCH = "e3000000-0000-4000-8000-000000000001";
const FIXTURE_JTI = "f4000000-0000-4000-8000-000000000001";

const DEFAULT_CLAIMS: AatClaims = {
  iss: FIXTURE_ISS,
  aud: AUDIENCE,
  sub: FIXTURE_SUB,
  org: FIXTURE_ORG,
  branch: FIXTURE_BRANCH,
  role: "doctor",
  scopes: ["ai.access"],
  jti: FIXTURE_JTI,
  iat: NOW - 30,
  exp: NOW + 600,
  ver: "1",
};

let fixtureKeypair: TestKeypair;

// ---------------------------------------------------------------------------
// Base64url + JWS helpers (B1 §2–3)
// ---------------------------------------------------------------------------

function base64urlEncode(data: string | Uint8Array): string {
  const bytes =
    typeof data === "string" ? new TextEncoder().encode(data) : data;
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/u, "");
}

function base64urlDecode(segment: string): string {
  const padded =
    segment + "=".repeat((4 - (segment.length % 4)) % 4);
  const binary = atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
  const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

async function generateTestKeypair(kid: string = FIXTURE_KID): Promise<TestKeypair> {
  const keyPair = await crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  );
  const exportedJwk = await crypto.subtle.exportKey("jwk", keyPair.publicKey);
  const rawPublicKey = await crypto.subtle.exportKey("raw", keyPair.publicKey);

  if (!exportedJwk.x) {
    throw new Error("Ed25519 public key JWK missing x coordinate");
  }

  return {
    publicKey: keyPair.publicKey,
    privateKey: keyPair.privateKey,
    kid,
    publicKeyB64: base64urlEncode(new Uint8Array(rawPublicKey)),
    jwk: {
      kty: "OKP",
      crv: "Ed25519",
      x: exportedJwk.x,
      kid,
    },
  };
}

type MintTokenOptions = {
  claims?: Partial<AatClaims>;
  header?: Partial<{ alg: string; kid: string }>;
  corruptSignature?: boolean;
};

/** Mint a three-segment EdDSA JWS per B1 `aat-token.md` §2–3. */
export async function mintToken(
  keypair: TestKeypair,
  claims: Partial<AatClaims> = {},
  options: MintTokenOptions = {},
): Promise<string> {
  const payload: AatClaims = { ...DEFAULT_CLAIMS, ...claims };
  const header = {
    alg: "EdDSA",
    kid: keypair.kid,
    ...options.header,
  };

  const headerB64 = base64urlEncode(JSON.stringify(header));
  const payloadB64 = base64urlEncode(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;

  const signature = await crypto.subtle.sign(
    { name: "Ed25519" },
    keypair.privateKey,
    new TextEncoder().encode(signingInput),
  );

  const signatureBytes = new Uint8Array(signature);
  if (options.corruptSignature) {
    // Corrupt raw bytes, not the base64url tail: the last encoding character
    // often carries padding bits, so swapping it for a fixed letter is a no-op
    // ~25% of the time and lets verify() succeed intermittently.
    signatureBytes[0] ^= 0xff;
  }
  const signatureB64 = base64urlEncode(signatureBytes);

  return `${signingInput}.${signatureB64}`;
}

function mutateTokenHeaderAlg(token: string, alg: string): string {
  const [headerB64, payloadB64, signatureB64] = token.split(".");
  const header = JSON.parse(base64urlDecode(headerB64)) as { alg: string; kid: string };
  header.alg = alg;
  return `${base64urlEncode(JSON.stringify(header))}.${payloadB64}.${signatureB64}`;
}

// ---------------------------------------------------------------------------
// Reader spy (A5 `config-cache.test.ts` shape)
// ---------------------------------------------------------------------------

function makeReader(
  source:
    | Record<string, unknown>
    | "miss"
    | Record<string, Record<string, unknown> | "miss">
    | ((key: string) => Record<string, unknown> | "miss"),
): ReaderSpy {
  const read = vi.fn(async (key: string): Promise<Record<string, unknown> | "miss"> => {
    if (source === "miss") {
      return "miss";
    }
    if (typeof source === "function") {
      return source(key);
    }
    if (key in source) {
      return source[key] as Record<string, unknown> | "miss";
    }
    return source as Record<string, unknown>;
  });

  return {
    read,
    readCount: () => read.mock.calls.length,
  };
}

function installationRow(
  status: string = "active",
  installationId: string = FIXTURE_ISS,
): Record<string, unknown> {
  return {
    installation_id: installationId,
    org_id: FIXTURE_ORG,
    display_name: "Test Clinic",
    status,
    region: "us-east-1",
    enrolled_at: new Date(NOW * 1000).toISOString(),
  };
}

function keyRow(
  keypair: TestKeypair,
  installationId: string = FIXTURE_ISS,
  overrides: Partial<Record<string, unknown>> = {},
): Record<string, unknown> {
  return {
    key_id: keypair.kid,
    installation_id: installationId,
    public_key: keypair.publicKeyB64,
    algorithm: "EdDSA",
    valid_from: new Date((NOW - 3600) * 1000).toISOString(),
    valid_until: null,
    revoked_at: null,
    jwk: keypair.jwk,
    ...overrides,
  };
}

const DEFAULT_TOKEN_CONTRACT: Record<string, unknown> = {
  ver: "1",
  added_at: "2026-08-03T00:00:00.000Z",
  retired_at: null,
  changed_by: "seed",
};

function makeIdentityReader(
  keypair: TestKeypair,
  overrides: {
    installation?: Record<string, unknown> | "miss";
    installationId?: string;
    key?: Record<string, unknown> | "miss";
    contract?: Record<string, unknown> | "miss" | ((ver: string) => Record<string, unknown> | "miss");
    /** Extra prefixed rows (e.g. a second installation/key for cross-iss cases). */
    extra?: Record<string, Record<string, unknown> | "miss">;
  } = {},
): ReaderSpy {
  const installationId = overrides.installationId ?? FIXTURE_ISS;
  return makeReader((lookupKey) => {
    if (overrides.extra && lookupKey in overrides.extra) {
      return overrides.extra[lookupKey]!;
    }
    if (lookupKey === `installations:${installationId}`) {
      return overrides.installation ?? installationRow("active", installationId);
    }
    if (lookupKey === `keys:${keypair.kid}`) {
      return overrides.key ?? keyRow(keypair, installationId);
    }
    if (lookupKey.startsWith("token_contracts:")) {
      const ver = lookupKey.slice("token_contracts:".length);
      const contractLookup =
        overrides.contract ??
        ((contractVer: string) =>
          contractVer === "1" ? DEFAULT_TOKEN_CONTRACT : "miss");
      if (typeof contractLookup === "function") {
        return contractLookup(ver);
      }
      return contractLookup;
    }
    return "miss";
  });
}

function buildVerifyContext(
  reader: D1Reader,
  overrides: Partial<VerifyContext> = {},
): VerifyContext {
  return {
    audience: AUDIENCE,
    clockSkewSeconds: CLOCK_SKEW_SECONDS,
    now: NOW,
    cache: new ConfigCache(),
    reader,
    ...overrides,
  };
}

function expectPrincipalFromClaims(principal: Principal, claims: AatClaims): void {
  expect(principal.installationId).toBe(claims.iss);
  expect(principal.organizationId).toBe(claims.org);
  expect(principal.branchId).toBe(claims.branch);
  expect(principal.actorId).toBe(claims.sub);
  expect(principal.role).toBe(claims.role);
  expect([...principal.scopes]).toEqual(claims.scopes);
  expect(principal.jti).toBe(claims.jti);
  expect(principal.iat).toBe(claims.iat);
  expect(principal.exp).toBe(claims.exp);
  expect(principal.ver).toBe(claims.ver);
}

function expectRejected(
  result: VerifyResult,
  code: "unauthenticated" | "installation_suspended" = "unauthenticated",
): void {
  expect(result.ok).toBe(false);
  if (!result.ok) {
    expect(result.code).toBe(code);
  }
}

// ---------------------------------------------------------------------------
// D1 harness (B2 Miniflare pattern from `control.test.ts`)
// ---------------------------------------------------------------------------

async function applyPlatformSchema(db: D1Database, sql: string): Promise<void> {
  const statements = sql
    .replace(/--.*$/gm, "")
    .split(";")
    .map((statement) => statement.trim())
    .filter((statement) => statement.length > 0);

  for (const statement of statements) {
    await db.prepare(statement).run();
  }
}

async function clearIdentityTables(db: D1Database): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM installation_key"),
    db.prepare("DELETE FROM installation"),
  ]);
}

function createPlatformD1Reader(db: D1Database): D1Reader {
  return {
    async read(prefixedKey: string): Promise<Record<string, unknown> | "miss"> {
      const separator = prefixedKey.indexOf(":");
      if (separator === -1) {
        return "miss";
      }

      const kind = prefixedKey.slice(0, separator);
      const key = prefixedKey.slice(separator + 1);

      switch (kind) {
        case "installations": {
          const installation = await db
            .prepare("SELECT * FROM installation WHERE installation_id = ?")
            .bind(key)
            .first<Record<string, unknown>>();
          return installation ?? "miss";
        }
        case "keys": {
          const installationKey = await db
            .prepare("SELECT * FROM installation_key WHERE key_id = ?")
            .bind(key)
            .first<Record<string, unknown>>();
          return installationKey ?? "miss";
        }
        case "token_contracts": {
          const tokenContract = await db
            .prepare("SELECT * FROM token_contract WHERE ver = ?")
            .bind(key)
            .first<Record<string, unknown>>();
          return tokenContract ?? "miss";
        }
        default:
          return "miss";
      }
    },
  };
}

async function seedSuspendedInstallation(
  db: D1Database,
  keypair: TestKeypair,
  installationId: string = FIXTURE_ISS,
): Promise<void> {
  const enrolledAt = new Date(NOW * 1000).toISOString();
  const validFrom = new Date((NOW - 3600) * 1000).toISOString();

  await db
    .prepare(
      `INSERT INTO installation
        (installation_id, org_id, display_name, status, region, enrolled_at)
       VALUES (?, ?, ?, 'suspended', ?, ?)`,
    )
    .bind(installationId, FIXTURE_ORG, "Suspended Clinic", "us-east-1", enrolledAt)
    .run();

  await db
    .prepare(
      `INSERT INTO installation_key
        (key_id, installation_id, public_key, algorithm, valid_from, valid_until, revoked_at)
       VALUES (?, ?, ?, 'EdDSA', ?, NULL, NULL)`,
    )
    .bind(keypair.kid, installationId, keypair.publicKeyB64, validFrom)
    .run();
}

// ---------------------------------------------------------------------------
// T002 — valid token + seven data-driven rejection cases
// ---------------------------------------------------------------------------

beforeAll(async () => {
  fixtureKeypair = await generateTestKeypair();
});

describe("identity_valid_token_accepted", () => {
  it("returns ok:true with a principal carrying every §5.6 claim", async () => {
    const verifier = new EnrolledKeyVerifier();
    const claims = { ...DEFAULT_CLAIMS };
    const token = await mintToken(fixtureKeypair, claims);
    const ctx = buildVerifyContext(makeIdentityReader(fixtureKeypair));

    const result = await verifier.verify(token, ctx);

    expect(result.ok).toBe(true);
    if (result.ok) {
      expectPrincipalFromClaims(result.principal, claims);
    }
  });
});

describe("identity token rejection cases", () => {
  const cases: Array<{
    name: string;
    mutate: (token: string, keypair: TestKeypair) => Promise<string> | string;
    reader?: (keypair: TestKeypair) => ReaderSpy;
    ctx?: (reader: ReaderSpy) => VerifyContext;
    expectOk?: boolean;
    expectedClaims?: Partial<AatClaims>;
    code?: "unauthenticated" | "installation_suspended";
  }> = [
    {
      name: "identity_rejects_non_eddsa_alg",
      mutate: async (token) => mutateTokenHeaderAlg(token, "none"),
    },
    {
      name: "identity_rejects_hmac_alg",
      mutate: async (token) => mutateTokenHeaderAlg(token, "HS256"),
    },
    {
      name: "identity_rejects_bad_signature",
      mutate: async (_token, keypair) =>
        mintToken(keypair, {}, { corruptSignature: true }),
    },
    {
      name: "identity_rejects_wrong_audience",
      mutate: async (_token, keypair) =>
        mintToken(keypair, { aud: "wrong-audience" }),
    },
    {
      name: "identity_rejects_expired_token",
      mutate: async (_token, keypair) =>
        mintToken(keypair, {
          iat: NOW - 900,
          exp: NOW - CLOCK_SKEW_SECONDS - 1,
        }),
    },
    {
      name: "identity_accepts_notyetvalid_inside_skew",
      mutate: async (_token, keypair) =>
        mintToken(keypair, {
          iat: NOW + CLOCK_SKEW_SECONDS - 5,
          exp: NOW + 600,
        }),
      expectOk: true,
      expectedClaims: {
        iat: NOW + CLOCK_SKEW_SECONDS - 5,
        exp: NOW + 600,
      },
    },
    {
      name: "identity_accepts_expired_inside_skew",
      mutate: async (_token, keypair) =>
        mintToken(keypair, {
          iat: NOW - 900,
          exp: NOW - CLOCK_SKEW_SECONDS + 1,
        }),
      expectOk: true,
      expectedClaims: {
        iat: NOW - 900,
        exp: NOW - CLOCK_SKEW_SECONDS + 1,
      },
    },
    {
      name: "identity_rejects_outside_skew",
      mutate: async (_token, keypair) =>
        mintToken(keypair, {
          iat: NOW + CLOCK_SKEW_SECONDS + 120,
          exp: NOW + 900,
        }),
    },
    {
      name: "identity_rejects_unknown_issuer",
      mutate: async (_token, keypair) =>
        mintToken(keypair, { iss: "00000000-0000-4000-8000-000000009999" }),
      reader: (keypair) =>
        makeIdentityReader(keypair, { installation: "miss" }),
    },
    {
      name: "identity_rejects_unknown_kid",
      mutate: async (_token, keypair) =>
        mintToken(keypair, {}, { header: { kid: "00000000-0000-4000-8000-00000000kid0" } }),
      reader: (keypair) => makeIdentityReader(keypair, { key: "miss" }),
    },
    {
      name: "identity_rejects_revoked_key",
      mutate: async (_token, keypair) => mintToken(keypair),
      reader: (keypair) =>
        makeIdentityReader(keypair, {
          key: keyRow(keypair, FIXTURE_ISS, {
            revoked_at: new Date(NOW * 1000).toISOString(),
          }),
        }),
    },
    {
      name: "identity_rejects_deleted_installation",
      mutate: async (_token, keypair) => mintToken(keypair),
      reader: (keypair) =>
        makeIdentityReader(keypair, {
          installation: installationRow("deleted"),
        }),
    },
  ];

  for (const testCase of cases) {
    describe(testCase.name, () => {
      it(testCase.expectOk ? "accepts inside skew window" : "rejects with unauthenticated", async () => {
        const verifier = new EnrolledKeyVerifier();
        const reader =
          testCase.reader?.(fixtureKeypair) ??
          makeIdentityReader(fixtureKeypair);
        const ctx = testCase.ctx?.(reader) ?? buildVerifyContext(reader);
        const validToken = await mintToken(fixtureKeypair);
        const token = await testCase.mutate(validToken, fixtureKeypair);

        const result = await verifier.verify(token, ctx);

        if (testCase.expectOk) {
          expect(result.ok).toBe(true);
          if (result.ok) {
            expectPrincipalFromClaims(result.principal, {
              ...DEFAULT_CLAIMS,
              ...testCase.expectedClaims,
            });
          }
          return;
        }

        expectRejected(result, testCase.code ?? "unauthenticated");
      });
    });
  }
});

// ---------------------------------------------------------------------------
// Cross-installation key binding (review Critical 1)
// ---------------------------------------------------------------------------

describe("identity_rejects_cross_installation_key", () => {
  it("rejects when kid belongs to a different installation than iss", async () => {
    const keypairB = await generateTestKeypair(FIXTURE_KID_B);
    const verifier = new EnrolledKeyVerifier();

    // Sign with installation B's key while claiming iss = A.
    const token = await mintToken(keypairB, { iss: FIXTURE_ISS });
    const reader = makeIdentityReader(fixtureKeypair, {
      extra: {
        [`keys:${keypairB.kid}`]: keyRow(keypairB, FIXTURE_ISS_B),
        [`installations:${FIXTURE_ISS_B}`]: installationRow("active", FIXTURE_ISS_B),
      },
    });

    const result = await verifier.verify(token, buildVerifyContext(reader));

    expectRejected(result, "unauthenticated");
  });
});

// ---------------------------------------------------------------------------
// Malformed-token gauntlet (parse / claim branches)
// ---------------------------------------------------------------------------

describe("identity_rejects_malformed_token", () => {
  const gauntlet: Array<{ name: string; token: () => Promise<string> | string }> = [
    {
      name: "two-segment token",
      token: () => {
        const headerB64 = base64urlEncode(JSON.stringify({ alg: "EdDSA", kid: FIXTURE_KID }));
        const payloadB64 = base64urlEncode(JSON.stringify(DEFAULT_CLAIMS));
        return `${headerB64}.${payloadB64}`;
      },
    },
    {
      name: "invalid base64url",
      token: () => "!!!.!!!.!!!",
    },
    {
      name: "non-JSON header",
      token: async () => {
        const headerB64 = base64urlEncode("not-json");
        const payloadB64 = base64urlEncode(JSON.stringify(DEFAULT_CLAIMS));
        return `${headerB64}.${payloadB64}.sig`;
      },
    },
    {
      name: "non-JSON payload",
      token: async () => {
        const headerB64 = base64urlEncode(
          JSON.stringify({ alg: "EdDSA", kid: FIXTURE_KID }),
        );
        const payloadB64 = base64urlEncode("not-json");
        return `${headerB64}.${payloadB64}.sig`;
      },
    },
    {
      name: "missing claim",
      token: async () => {
        const { org: _omit, ...withoutOrg } = DEFAULT_CLAIMS;
        const headerB64 = base64urlEncode(
          JSON.stringify({ alg: "EdDSA", kid: FIXTURE_KID }),
        );
        const payloadB64 = base64urlEncode(JSON.stringify(withoutOrg));
        // Unsigned — claim parse rejects before signature verify.
        return `${headerB64}.${payloadB64}.${base64urlEncode(new Uint8Array(64))}`;
      },
    },
    {
      name: "empty kid",
      token: async () =>
        mintToken(fixtureKeypair, {}, { header: { kid: "" } }),
    },
  ];

  for (const testCase of gauntlet) {
    it(`rejects ${testCase.name} as unauthenticated`, async () => {
      const verifier = new EnrolledKeyVerifier();
      const token = await testCase.token();
      const result = await verifier.verify(
        token,
        buildVerifyContext(makeIdentityReader(fixtureKeypair)),
      );
      expectRejected(result, "unauthenticated");
    });
  }
});

// ---------------------------------------------------------------------------
// T003 — verifier port substitution
// ---------------------------------------------------------------------------

class FixedResultVerifier implements TokenVerifier {
  constructor(private readonly outcomes: Map<string, VerifyResult>) {}

  verify(token: string, _ctx: VerifyContext): Promise<VerifyResult> {
    const outcome = this.outcomes.get(token);
    if (!outcome) {
      throw new Error(`FixedResultVerifier missing outcome for token: ${token}`);
    }
    return Promise.resolve(outcome);
  }
}

function expectedPrincipal(claims: AatClaims = DEFAULT_CLAIMS): Principal {
  return Object.freeze({
    installationId: claims.iss,
    organizationId: claims.org,
    branchId: claims.branch,
    actorId: claims.sub,
    role: claims.role,
    scopes: Object.freeze([...claims.scopes]),
    jti: claims.jti,
    iat: claims.iat,
    exp: claims.exp,
    ver: claims.ver,
  });
}

describe("verifier_swap_changes_no_outcome", () => {
  it("returns identical outcomes for fake and enrolled-key verifiers", async () => {
    const enrolledVerifier = new EnrolledKeyVerifier();

    const validClaims = { ...DEFAULT_CLAIMS };
    const validToken = await mintToken(fixtureKeypair, validClaims);
    const badSignatureToken = await mintToken(
      fixtureKeypair,
      {},
      { corruptSignature: true },
    );
    const wrongAudienceToken = await mintToken(fixtureKeypair, {
      aud: "wrong-audience",
    });
    const unknownIssuerToken = await mintToken(fixtureKeypair, {
      iss: "00000000-0000-4000-8000-000000009999",
    });

    // Independent expectation table — not seeded from enrolledVerifier outcomes.
    const cases: Array<{
      label: string;
      token: string;
      reader: ReaderSpy;
      expected: VerifyResult;
    }> = [
      {
        label: "valid",
        token: validToken,
        reader: makeIdentityReader(fixtureKeypair),
        expected: { ok: true, principal: expectedPrincipal(validClaims) },
      },
      {
        label: "badSignature",
        token: badSignatureToken,
        reader: makeIdentityReader(fixtureKeypair),
        expected: { ok: false, code: "unauthenticated" },
      },
      {
        label: "wrongAudience",
        token: wrongAudienceToken,
        reader: makeIdentityReader(fixtureKeypair),
        expected: { ok: false, code: "unauthenticated" },
      },
      {
        label: "unknownIssuer",
        token: unknownIssuerToken,
        reader: makeIdentityReader(fixtureKeypair, { installation: "miss" }),
        expected: { ok: false, code: "unauthenticated" },
      },
    ];

    const fakeVerifier = new FixedResultVerifier(
      new Map(cases.map((testCase) => [testCase.token, testCase.expected])),
    );

    for (const testCase of cases) {
      const ctx = buildVerifyContext(testCase.reader);
      const enrolled = await enrolledVerifier.verify(testCase.token, ctx);
      const swapped = await fakeVerifier.verify(testCase.token, ctx);

      expect(enrolled).toEqual(testCase.expected);
      expect(swapped).toEqual(testCase.expected);
      expect(swapped).toEqual(enrolled);
    }
  });
});

// ---------------------------------------------------------------------------
// T004 — principal immutability spy
// ---------------------------------------------------------------------------

describe("principal_immutable_to_later_stage", () => {
  it("ignores or throws on mutation attempts and preserves original values", async () => {
    const verifier = new EnrolledKeyVerifier();
    const token = await mintToken(fixtureKeypair);
    const result = await verifier.verify(
      token,
      buildVerifyContext(makeIdentityReader(fixtureKeypair)),
    );

    expect(result.ok).toBe(true);
    if (!result.ok) {
      return;
    }

    const principal = result.principal;
    const snapshot = {
      installationId: principal.installationId,
      organizationId: principal.organizationId,
      branchId: principal.branchId,
      actorId: principal.actorId,
      role: principal.role,
      scopes: [...principal.scopes],
      jti: principal.jti,
      iat: principal.iat,
      exp: principal.exp,
      ver: principal.ver,
    };

    const mutablePrincipal = principal as Principal & {
      installationId: string;
      organizationId: string;
      branchId: string;
      actorId: string;
      role: string;
      scopes: string[];
      jti: string;
      iat: number;
      exp: number;
      ver: string;
    };

    const mutationAttempts: Array<() => void> = [
      () => {
        mutablePrincipal.installationId = "mutated-installation";
      },
      () => {
        mutablePrincipal.organizationId = "mutated-org";
      },
      () => {
        mutablePrincipal.branchId = "mutated-branch";
      },
      () => {
        mutablePrincipal.actorId = "mutated-actor";
      },
      () => {
        mutablePrincipal.role = "mutated-role";
      },
      () => {
        mutablePrincipal.jti = "mutated-jti";
      },
      () => {
        mutablePrincipal.iat = 0;
      },
      () => {
        mutablePrincipal.exp = 0;
      },
      () => {
        mutablePrincipal.ver = "mutated-ver";
      },
      () => {
        mutablePrincipal.scopes.push("ai.mutated");
      },
      () => {
        mutablePrincipal.scopes.pop();
      },
    ];

    for (const attempt of mutationAttempts) {
      try {
        attempt();
      } catch {
        // Frozen objects may throw in strict mode — either throw or no-op is acceptable.
      }
    }

    const laterReader = {
      installationId: principal.installationId,
      organizationId: principal.organizationId,
      branchId: principal.branchId,
      actorId: principal.actorId,
      role: principal.role,
      scopes: [...principal.scopes],
      jti: principal.jti,
      iat: principal.iat,
      exp: principal.exp,
      ver: principal.ver,
    };

    expect(laterReader).toEqual(snapshot);
    expect(principal.scopes).toEqual(snapshot.scopes);
    expect(principal.scopes).not.toBe(snapshot.scopes);
  });
});

// ---------------------------------------------------------------------------
// T005 — suspended installation integration (workers pool / Miniflare D1)
// ---------------------------------------------------------------------------

describe("identity_rejects_suspended_installation", () => {
  let db: D1Database;

  beforeAll(async () => {
    const workers = await import("cloudflare:test");
    db = workers.env.DB;
    await applyPlatformSchema(db, migrationSql);
    await applyPlatformSchema(db, tokenContractMigrationSql);
  });

  beforeEach(async () => {
    await clearIdentityTables(db);
  });

  it("returns installation_suspended for a suspended installation", async () => {
    const keypair = await generateTestKeypair();
    await seedSuspendedInstallation(db, keypair);

    const verifier = new EnrolledKeyVerifier();
    const token = await mintToken(keypair);
    const ctx = buildVerifyContext(createPlatformD1Reader(db));

    const result = await verifier.verify(token, ctx);

    expectRejected(result, "installation_suspended");
  });
});
