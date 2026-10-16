import { describe, expect, it } from "vitest";
import * as vendorContracts from "vendor-contracts";
import * as testkit from "vendor-contracts/testkit";
import operationVector from "../vectors/operation.json";

function requireExport(
  exports: Record<string, unknown>,
  name: string,
): (...args: never[]) => unknown {
  expect(exports[name], `${name} export`).toBeTypeOf("function");
  return exports[name] as (...args: never[]) => unknown;
}

function operationPrime(): typeof operationVector.operation {
  const prime = structuredClone(operationVector.operation);
  prime.params = { ...prime.params, plan_id: "live-annual" };
  return prime;
}

async function registrationPublicKey(authenticator: {
  attest: () => Promise<{ alg: string; publicKey: Uint8Array }>;
}): Promise<CryptoKey> {
  const parseRegistrationAttestation = requireExport(
    vendorContracts,
    "parseRegistrationAttestation",
  );
  const attestation = await authenticator.attest();
  const parsed = (await parseRegistrationAttestation(attestation)) as {
    ok: boolean;
    publicKey?: CryptoKey;
  };
  expect(parsed.ok).toBe(true);
  return parsed.publicKey as CryptoKey;
}

describe("webauthn", () => {
  it("E2E-P2.2-01 A testkit assertion over operation O verifies; the same assertion against O′ (one param changed) fails", async () => {
    const verifyAssertion = requireExport(vendorContracts, "verifyAssertion");
    const createSoftwareAuthenticator = requireExport(
      testkit as Record<string, unknown>,
      "createSoftwareAuthenticator",
    );

    const { operation, rp_id: rpId, origin } = operationVector;
    const authenticator = (await createSoftwareAuthenticator("ES256")) as {
      attest: () => Promise<{ alg: string; publicKey: Uint8Array }>;
      assert: (input: {
        operation: unknown;
        rpId: string;
        origin: string;
        up: boolean;
        uv: boolean;
      }) => Promise<unknown>;
    };
    const publicKey = await registrationPublicKey(authenticator);
    const assertion = await authenticator.assert({
      operation,
      rpId,
      origin,
      up: true,
      uv: true,
    });

    expect(
      await verifyAssertion({
        assertion,
        operation,
        rpId,
        origin,
        publicKey,
      }),
    ).toEqual({ ok: true });

    expect(
      await verifyAssertion({
        assertion,
        operation: operationPrime(),
        rpId,
        origin,
        publicKey,
      }),
    ).toEqual({ ok: false });
  });

  it("E2E-P2.2-02 UV flag cleared, wrong origin, or wrong rpId → each fails", async () => {
    const verifyAssertion = requireExport(vendorContracts, "verifyAssertion");
    const createSoftwareAuthenticator = requireExport(
      testkit as Record<string, unknown>,
      "createSoftwareAuthenticator",
    );

    const {
      operation,
      rp_id: rpId,
      origin,
      wrong_origin: wrongOrigin,
      wrong_rp_id: wrongRpId,
    } = operationVector;
    const authenticator = (await createSoftwareAuthenticator("ES256")) as {
      attest: () => Promise<{ alg: string; publicKey: Uint8Array }>;
      assert: (input: {
        operation: unknown;
        rpId: string;
        origin: string;
        up: boolean;
        uv: boolean;
      }) => Promise<unknown>;
    };
    const publicKey = await registrationPublicKey(authenticator);

    const uvCleared = await authenticator.assert({
      operation,
      rpId,
      origin,
      up: true,
      uv: false,
    });
    expect(
      await verifyAssertion({
        assertion: uvCleared,
        operation,
        rpId,
        origin,
        publicKey,
      }),
    ).toEqual({ ok: false });

    const wrongOriginAssertion = await authenticator.assert({
      operation,
      rpId,
      origin: wrongOrigin,
      up: true,
      uv: true,
    });
    expect(
      await verifyAssertion({
        assertion: wrongOriginAssertion,
        operation,
        rpId,
        origin,
        publicKey,
      }),
    ).toEqual({ ok: false });

    const wrongRpIdAssertion = await authenticator.assert({
      operation,
      rpId: wrongRpId,
      origin,
      up: true,
      uv: true,
    });
    expect(
      await verifyAssertion({
        assertion: wrongRpIdAssertion,
        operation,
        rpId,
        origin,
        publicKey,
      }),
    ).toEqual({ ok: false });
  });

  it("E2E-P2.2-03 ES256 and EdDSA credentials both verify; another alg is rejected", async () => {
    const verifyAssertion = requireExport(vendorContracts, "verifyAssertion");
    const parseRegistrationAttestation = requireExport(
      vendorContracts,
      "parseRegistrationAttestation",
    );
    const createSoftwareAuthenticator = requireExport(
      testkit as Record<string, unknown>,
      "createSoftwareAuthenticator",
    );

    const { operation, rp_id: rpId, origin } = operationVector;

    for (const alg of ["ES256", "EdDSA"] as const) {
      const authenticator = (await createSoftwareAuthenticator(alg)) as {
        attest: () => Promise<{ alg: string; publicKey: Uint8Array }>;
        assert: (input: {
          operation: unknown;
          rpId: string;
          origin: string;
          up: boolean;
          uv: boolean;
        }) => Promise<unknown>;
      };
      const attestation = await authenticator.attest();
      expect(await parseRegistrationAttestation(attestation)).toEqual({
        ok: true,
        alg,
        publicKey: expect.any(Object),
      });
      const parsed = (await parseRegistrationAttestation(attestation)) as {
        ok: true;
        publicKey: CryptoKey;
      };
      const assertion = await authenticator.assert({
        operation,
        rpId,
        origin,
        up: true,
        uv: true,
      });
      expect(
        await verifyAssertion({
          assertion,
          operation,
          rpId,
          origin,
          publicKey: parsed.publicKey,
        }),
      ).toEqual({ ok: true });
    }

    expect(
      await parseRegistrationAttestation({
        alg: "RS256",
        publicKey: new Uint8Array(32),
      }),
    ).toEqual({ ok: false });
  });
});
