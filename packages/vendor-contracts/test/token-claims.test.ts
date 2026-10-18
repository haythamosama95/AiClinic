import { describe, expect, it } from "vitest";
import * as vendorContracts from "vendor-contracts";
import * as testkit from "vendor-contracts/testkit";
import tokenClaimsVector from "../vectors/token-claims.json";

function requireExport(
  exports: Record<string, unknown>,
  name: string,
): (...args: never[]) => unknown {
  expect(exports[name], `${name} export`).toBeTypeOf("function");
  return exports[name] as (...args: never[]) => unknown;
}

type IssuerHarness = {
  kid: string;
  publicKey: CryptoKey;
  mintBilling: (claims: Record<string, unknown>) => Promise<string>;
  mintFeed: (claims: Record<string, unknown>) => Promise<string>;
};

async function createHarness(): Promise<IssuerHarness> {
  const createIssuer = requireExport(
    testkit as Record<string, unknown>,
    "createIssuer",
  );
  return (await createIssuer({
    issuerId: tokenClaimsVector.issuer_id,
  })) as IssuerHarness;
}

type ValidateInput = {
  jwt: string;
  audience: "abo" | "ai-platform-feed";
  publicKey: CryptoKey;
  kid: string;
  nowSeconds: number;
  clockSkewSeconds?: number;
};

async function validate(input: ValidateInput): Promise<unknown> {
  const validateTokenClaims = requireExport(
    vendorContracts,
    "validateTokenClaims",
  ) as (args: Record<string, unknown>) => Promise<unknown>;
  return validateTokenClaims({
    issuerId: tokenClaimsVector.issuer_id,
    clockSkewSeconds: 60,
    ...input,
  });
}

describe("token claims", () => {
  it("E2E-P2.2-07 Claim validators: billing token with lifetime > 300 s rejected; feed token carrying org rejected", async () => {
    const issuer = await createHarness();

    const billingJwt = await issuer.mintBilling(
      tokenClaimsVector.billing_over_lifetime,
    );
    expect(
      await validate({
        jwt: billingJwt,
        audience: "abo",
        publicKey: issuer.publicKey,
        kid: issuer.kid,
        nowSeconds: 1700000200,
      }),
    ).toEqual({ ok: false });

    const feedJwt = await issuer.mintFeed(tokenClaimsVector.feed_with_org);
    expect(
      await validate({
        jwt: feedJwt,
        audience: "ai-platform-feed",
        publicKey: issuer.publicKey,
        kid: issuer.kid,
        nowSeconds: 1700000020,
      }),
    ).toEqual({ ok: false });
  });

  it("R1-C1: freshly minted billing and feed tokens authenticate", async () => {
    const issuer = await createHarness();
    const now = 1_900_000_000;

    const billingJwt = await issuer.mintBilling({
      sub: "staff-001",
      org: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      role: "administrator",
      branch: "main",
      iat: now,
      exp: now + 300,
      jti: "a1b2c3d4-e5f6-7890-abcd-ef1234567893",
    });
    expect(
      await validate({
        jwt: billingJwt,
        audience: "abo",
        publicKey: issuer.publicKey,
        kid: issuer.kid,
        nowSeconds: now,
      }),
    ).toEqual({ ok: true });

    const feedJwt = await issuer.mintFeed({
      iat: now,
      exp: now + 120,
      jti: "a1b2c3d4-e5f6-7890-abcd-ef1234567894",
    });
    expect(
      await validate({
        jwt: feedJwt,
        audience: "ai-platform-feed",
        publicKey: issuer.publicKey,
        kid: issuer.kid,
        nowSeconds: now,
      }),
    ).toEqual({ ok: true });
  });

  it("R1-C1: billing token expired by more than 60 seconds is rejected", async () => {
    const issuer = await createHarness();
    const now = 1_900_000_000;

    const billingJwt = await issuer.mintBilling({
      sub: "staff-001",
      org: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      role: "administrator",
      branch: "main",
      iat: now - 361,
      exp: now - 61,
      jti: "a1b2c3d4-e5f6-7890-abcd-ef1234567895",
    });
    expect(
      await validate({
        jwt: billingJwt,
        audience: "abo",
        publicKey: issuer.publicKey,
        kid: issuer.kid,
        nowSeconds: now,
      }),
    ).toEqual({ ok: false });
  });

  it("R1-C1: billing token future-issued by more than 60 seconds is rejected", async () => {
    const issuer = await createHarness();
    const now = 1_900_000_000;

    const billingJwt = await issuer.mintBilling({
      sub: "staff-001",
      org: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      role: "administrator",
      branch: "main",
      iat: now + 61,
      exp: now + 361,
      jti: "a1b2c3d4-e5f6-7890-abcd-ef1234567896",
    });
    expect(
      await validate({
        jwt: billingJwt,
        audience: "abo",
        publicKey: issuer.publicKey,
        kid: issuer.kid,
        nowSeconds: now,
      }),
    ).toEqual({ ok: false });
  });

  it("R1-C1: feed token at the exp+60s skew boundary is rejected; one second inside the skew window authenticates", async () => {
    const issuer = await createHarness();
    const now = 1_900_000_000;

    const boundaryJwt = await issuer.mintFeed({
      iat: now - 180,
      exp: now - 60,
      jti: "a1b2c3d4-e5f6-7890-abcd-ef1234567897",
    });
    expect(
      await validate({
        jwt: boundaryJwt,
        audience: "ai-platform-feed",
        publicKey: issuer.publicKey,
        kid: issuer.kid,
        nowSeconds: now,
      }),
    ).toEqual({ ok: false });

    const insideJwt = await issuer.mintFeed({
      iat: now - 179,
      exp: now - 59,
      jti: "a1b2c3d4-e5f6-7890-abcd-ef1234567898",
    });
    expect(
      await validate({
        jwt: insideJwt,
        audience: "ai-platform-feed",
        publicKey: issuer.publicKey,
        kid: issuer.kid,
        nowSeconds: now,
      }),
    ).toEqual({ ok: true });
  });

  it("R1-C1: nonfinite nowSeconds or negative clockSkewSeconds always fail", async () => {
    const issuer = await createHarness();
    const now = 1_900_000_000;

    const billingJwt = await issuer.mintBilling({
      sub: "staff-001",
      org: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      role: "administrator",
      branch: "main",
      iat: now,
      exp: now + 300,
      jti: "a1b2c3d4-e5f6-7890-abcd-ef1234567899",
    });

    expect(
      await validate({
        jwt: billingJwt,
        audience: "abo",
        publicKey: issuer.publicKey,
        kid: issuer.kid,
        nowSeconds: Number.NaN,
      }),
    ).toEqual({ ok: false });

    expect(
      await validate({
        jwt: billingJwt,
        audience: "abo",
        publicKey: issuer.publicKey,
        kid: issuer.kid,
        nowSeconds: now,
        clockSkewSeconds: -1,
      }),
    ).toEqual({ ok: false });
  });
});
