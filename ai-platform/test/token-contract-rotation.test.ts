import { beforeAll, describe, expect, it, vi } from "vitest";
import { ConfigCache, type D1Reader } from "../src/config-cache";
import {
  EnrolledKeyVerifier,
  type Principal,
  type VerifyContext,
  type VerifyResult,
} from "../src/identity";

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
const FIXTURE_KID = "f47ac10b-58cc-4372-a567-0e02b2c3d479";
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

async function mintToken(
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
    signatureBytes[0] ^= 0xff;
  }
  const signatureB64 = base64urlEncode(signatureBytes);

  return `${signingInput}.${signatureB64}`;
}

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

function installationRow(status: string = "active"): Record<string, unknown> {
  return {
    installation_id: FIXTURE_ISS,
    org_id: FIXTURE_ORG,
    display_name: "Test Clinic",
    status,
    region: "us-east-1",
    enrolled_at: new Date(NOW * 1000).toISOString(),
  };
}

function keyRow(keypair: TestKeypair): Record<string, unknown> {
  return {
    key_id: keypair.kid,
    installation_id: FIXTURE_ISS,
    public_key: keypair.publicKeyB64,
    algorithm: "EdDSA",
    valid_from: new Date((NOW - 3600) * 1000).toISOString(),
    valid_until: null,
    revoked_at: null,
    jwk: keypair.jwk,
  };
}

function acceptedContractRow(ver: string): Record<string, unknown> {
  return {
    ver,
    added_at: "2026-08-03T12:00:00.000Z",
    retired_at: null,
    changed_by: "operator-test",
  };
}

function retiredContractRow(ver: string): Record<string, unknown> {
  return {
    ver,
    added_at: "2026-08-03T12:00:00.000Z",
    retired_at: "2026-08-03T13:00:00.000Z",
    changed_by: "operator-test",
  };
}

function makeRotationReader(
  keypair: TestKeypair,
  contractLookup: (ver: string) => Record<string, unknown> | "miss",
): ReaderSpy {
  return makeReader((lookupKey) => {
    if (lookupKey === `installations:${FIXTURE_ISS}`) {
      return installationRow("active");
    }
    if (lookupKey === `keys:${keypair.kid}`) {
      return keyRow(keypair);
    }
    if (lookupKey.startsWith("token_contracts:")) {
      const ver = lookupKey.slice("token_contracts:".length);
      return contractLookup(ver);
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

function expectRejected(
  result: VerifyResult,
  code: "unauthenticated" | "installation_suspended" = "unauthenticated",
): void {
  expect(result.ok).toBe(false);
  if (!result.ok) {
    expect(result.code).toBe(code);
  }
}

function expectPrincipalVer(principal: Principal, ver: string): void {
  expect(principal.ver).toBe(ver);
}

beforeAll(async () => {
  fixtureKeypair = await generateTestKeypair();
});

describe("T-J4-01 both_ver_values_verify_during_rotation_window", () => {
  it("accepts AATs for every ver in the overlapping accepted set", async () => {
    const verifier = new EnrolledKeyVerifier();
    const reader = makeRotationReader(fixtureKeypair, (ver) => {
      if (ver === "1" || ver === "2") {
        return acceptedContractRow(ver);
      }
      return "miss";
    });
    const ctx = buildVerifyContext(reader);

    const tokenVer1 = await mintToken(fixtureKeypair, { ver: "1" });
    const tokenVer2 = await mintToken(fixtureKeypair, { ver: "2" });

    const result1 = await verifier.verify(tokenVer1, ctx);
    const result2 = await verifier.verify(tokenVer2, ctx);

    expect(result1.ok).toBe(true);
    expect(result2.ok).toBe(true);
    if (result1.ok) {
      expectPrincipalVer(result1.principal, "1");
    }
    if (result2.ok) {
      expectPrincipalVer(result2.principal, "2");
    }

    const readKeys = reader.read.mock.calls.map((call) => call[0]);
    expect(readKeys).toContain("token_contracts:1");
    expect(readKeys).toContain("token_contracts:2");
  });
});

describe("T-J4-02 retired_ver_refused_as_unauthenticated", () => {
  it("refuses a retired ver with existing unauthenticated code only", async () => {
    const verifier = new EnrolledKeyVerifier();
    const reader = makeRotationReader(fixtureKeypair, (ver) => {
      if (ver === "1") {
        return retiredContractRow("1");
      }
      if (ver === "2") {
        return acceptedContractRow("2");
      }
      return "miss";
    });
    const ctx = buildVerifyContext(reader);
    const token = await mintToken(fixtureKeypair, { ver: "1" });

    const result = await verifier.verify(token, ctx);

    expectRejected(result, "unauthenticated");
    if (!result.ok) {
      expect(Object.keys(result)).toEqual(["ok", "code"]);
    }
  });
});

describe("T-J4-03 unknown_ver_refused_as_unauthenticated", () => {
  it("refuses a never-accepted ver with the same unauthenticated path", async () => {
    const verifier = new EnrolledKeyVerifier();
    const reader = makeRotationReader(fixtureKeypair, (ver) => {
      if (ver === "1") {
        return acceptedContractRow("1");
      }
      return "miss";
    });
    const ctx = buildVerifyContext(reader);
    const token = await mintToken(fixtureKeypair, { ver: "never-accepted" });

    const result = await verifier.verify(token, ctx);

    expectRejected(result, "unauthenticated");
    if (!result.ok) {
      expect(result.code).toBe("unauthenticated");
    }
  });
});

describe("T-J4-07 request_path_never_writes_token_contract", () => {
  it("verifies without writing token_contract or auto-retiring a ver", async () => {
    const contractState = new Map<string, Record<string, unknown>>([
      ["1", acceptedContractRow("1")],
    ]);
    const reader = makeRotationReader(fixtureKeypair, (ver) => {
      const row = contractState.get(ver);
      return row ?? "miss";
    });
    const verifier = new EnrolledKeyVerifier();
    const ctx = buildVerifyContext(reader);
    const token = await mintToken(fixtureKeypair, { ver: "1" });

    const before = structuredClone(Object.fromEntries(contractState));
    const result = await verifier.verify(token, ctx);
    const after = Object.fromEntries(contractState);

    expect(result.ok).toBe(true);
    expect(after).toEqual(before);
    const readKeys = reader.read.mock.calls.map((call) => call[0]);
    expect(readKeys).toContain("token_contracts:1");
    expect("write" in reader).toBe(false);
    expect("run" in reader).toBe(false);
  });
});

describe("T-J4-10 rotation_requires_no_re_enrollment", () => {
  it("same enrolled iss and kid verify under both accepted ver values after begin-rotation", async () => {
    const verifier = new EnrolledKeyVerifier();
    const reader = makeRotationReader(fixtureKeypair, (ver) => {
      if (ver === "1" || ver === "2") {
        return acceptedContractRow(ver);
      }
      return "miss";
    });
    const ctx = buildVerifyContext(reader);

    const tokenVer1 = await mintToken(fixtureKeypair, {
      ver: "1",
      jti: "a0000000-0000-4000-8000-000000000001",
    });
    const tokenVer2 = await mintToken(fixtureKeypair, {
      ver: "2",
      jti: "b0000000-0000-4000-8000-000000000001",
    });

    const result1 = await verifier.verify(tokenVer1, ctx);
    const result2 = await verifier.verify(tokenVer2, ctx);

    expect(result1.ok).toBe(true);
    expect(result2.ok).toBe(true);
    if (result1.ok && result2.ok) {
      expect(result1.principal.installationId).toBe(FIXTURE_ISS);
      expect(result2.principal.installationId).toBe(FIXTURE_ISS);
      expect(result1.principal.installationId).toBe(result2.principal.installationId);
    }

    const readKeys = reader.read.mock.calls.map((call) => call[0]);
    expect(readKeys).toContain("token_contracts:1");
    expect(readKeys).toContain("token_contracts:2");
    expect(readKeys).toContain(`keys:${fixtureKeypair.kid}`);
  });
});
