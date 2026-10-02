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

describe("token claims", () => {
  it("E2E-P2.2-07 Claim validators: billing token with lifetime > 300 s rejected; feed token carrying org rejected", async () => {
    const validateTokenClaims = requireExport(
      vendorContracts,
      "validateTokenClaims",
    );
    const createIssuer = requireExport(
      testkit as Record<string, unknown>,
      "createIssuer",
    );

    const issuer = (await createIssuer({
      issuerId: tokenClaimsVector.issuer_id,
    })) as {
      kid: string;
      publicKey: CryptoKey;
      mintBilling: (claims: Record<string, unknown>) => Promise<string>;
      mintFeed: (claims: Record<string, unknown>) => Promise<string>;
    };

    const billingJwt = await issuer.mintBilling(
      tokenClaimsVector.billing_over_lifetime,
    );
    expect(
      await validateTokenClaims({
        jwt: billingJwt,
        audience: "abo",
        issuerId: tokenClaimsVector.issuer_id,
        publicKey: issuer.publicKey,
        kid: issuer.kid,
      }),
    ).toEqual({ ok: false });

    const feedJwt = await issuer.mintFeed(tokenClaimsVector.feed_with_org);
    expect(
      await validateTokenClaims({
        jwt: feedJwt,
        audience: "ai-platform-feed",
        issuerId: tokenClaimsVector.issuer_id,
        publicKey: issuer.publicKey,
        kid: issuer.kid,
      }),
    ).toEqual({ ok: false });
  });
});
