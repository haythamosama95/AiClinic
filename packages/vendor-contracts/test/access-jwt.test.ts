import { describe, expect, it } from "vitest";
import * as vendorContracts from "vendor-contracts";
import * as testkit from "vendor-contracts/testkit";

function requireExport(
  exports: Record<string, unknown>,
  name: string,
): (...args: never[]) => unknown {
  expect(exports[name], `${name} export`).toBeTypeOf("function");
  return exports[name] as (...args: never[]) => unknown;
}

const accessFixture = {
  issuer: "https://example.cloudflareaccess.com",
  aud: "abo-gateway",
  email: "operator@example.com",
  now_seconds: 1_700_000_100,
  iat: 1_700_000_000,
  exp: 1_700_003_600,
  wrong_aud: "wrong-audience",
  unknown_kid: "unknown-kid-1",
};

describe("access jwt", () => {
  it("E2E-P2.2-04 Access JWT: valid → email; wrong aud tag, expired, or unknown cert kid → fails", async () => {
    const verifyAccessJwt = requireExport(vendorContracts, "verifyAccessJwt");
    const createAccessTeam = requireExport(
      testkit as Record<string, unknown>,
      "createAccessTeam",
    );

    const team = (await createAccessTeam({ issuer: accessFixture.issuer })) as {
      certs: unknown;
      mint: (input: {
        email: string;
        aud: string;
        exp: number;
        iat: number;
        kid?: string;
      }) => Promise<string>;
    };

    const validJwt = await team.mint({
      email: accessFixture.email,
      aud: accessFixture.aud,
      exp: accessFixture.exp,
      iat: accessFixture.iat,
    });
    expect(
      await verifyAccessJwt({
        jwt: validJwt,
        certs: team.certs,
        aud: accessFixture.aud,
        nowSeconds: accessFixture.now_seconds,
      }),
    ).toEqual({ ok: true, email: accessFixture.email });

    const wrongAudJwt = await team.mint({
      email: accessFixture.email,
      aud: accessFixture.wrong_aud,
      exp: accessFixture.exp,
      iat: accessFixture.iat,
    });
    expect(
      await verifyAccessJwt({
        jwt: wrongAudJwt,
        certs: team.certs,
        aud: accessFixture.aud,
        nowSeconds: accessFixture.now_seconds,
      }),
    ).toEqual({ ok: false });

    const expiredJwt = await team.mint({
      email: accessFixture.email,
      aud: accessFixture.aud,
      exp: accessFixture.now_seconds,
      iat: accessFixture.iat,
    });
    expect(
      await verifyAccessJwt({
        jwt: expiredJwt,
        certs: team.certs,
        aud: accessFixture.aud,
        nowSeconds: accessFixture.now_seconds,
      }),
    ).toEqual({ ok: false });

    const unknownKidJwt = await team.mint({
      email: accessFixture.email,
      aud: accessFixture.aud,
      exp: accessFixture.exp,
      iat: accessFixture.iat,
      kid: accessFixture.unknown_kid,
    });
    expect(
      await verifyAccessJwt({
        jwt: unknownKidJwt,
        certs: team.certs,
        aud: accessFixture.aud,
        nowSeconds: accessFixture.now_seconds,
      }),
    ).toEqual({ ok: false });
  });
});
