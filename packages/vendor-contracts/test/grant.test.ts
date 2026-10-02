import { describe, expect, it } from "vitest";
import * as vendorContracts from "vendor-contracts";
import * as testkit from "vendor-contracts/testkit";
import coverageSnapshotVector from "../vectors/coverage-snapshot.json";
import feedEventVector from "../vectors/feed-event.json";
import grantVector from "../vectors/grant-envelope.json";
import identifierVectors from "../vectors/identifiers.json";

function requireExport(
  exports: Record<string, unknown>,
  name: string,
): (...args: never[]) => unknown {
  expect(exports[name], `${name} export`).toBeTypeOf("function");
  return exports[name] as (...args: never[]) => unknown;
}

describe("grant envelope", () => {
  it("E2E-P2.2-05 Grant envelope: canonical hash stable; ABO signature verifies, and fails after any field mutation", async () => {
    const validateGrantEnvelope = requireExport(
      vendorContracts,
      "validateGrantEnvelope",
    );
    const grantEnvelopeHash = requireExport(
      vendorContracts,
      "grantEnvelopeHash",
    );
    const verifyGrantSignature = requireExport(
      vendorContracts,
      "verifyGrantSignature",
    );
    const validateCoverageSnapshot = requireExport(
      vendorContracts,
      "validateCoverageSnapshot",
    );
    const validateFeedEvent = requireExport(
      vendorContracts,
      "validateFeedEvent",
    );
    const createAboGrantSigner = requireExport(
      testkit as Record<string, unknown>,
      "createAboGrantSigner",
    );

    const { grantIdPaid, CHANNEL_VERSIONS, coverageEventId } = vendorContracts;
    expect(grantIdPaid).toBeTypeOf("function");
    expect(CHANNEL_VERSIONS.vendorEntrypoint).toBeTypeOf("number");
    expect(coverageEventId).toBeTypeOf("function");

    const { payment_id, envelope, hash_hex: hashHex } = grantVector;
    expect(await grantIdPaid(payment_id)).toBe(envelope.grant_id);
    expect(envelope.contract_version).toBe(CHANNEL_VERSIONS.vendorEntrypoint);
    expect(validateGrantEnvelope(envelope)).toEqual({ ok: true });

    expect(await grantEnvelopeHash(envelope)).toBe(hashHex);
    expect(await grantEnvelopeHash(envelope)).toBe(hashHex);

    const signer = (await createAboGrantSigner()) as {
      kid: string;
      publicKey: CryptoKey;
      sign: (value: unknown) => Promise<string>;
    };
    const jws = await signer.sign(envelope);
    expect(
      await verifyGrantSignature({
        envelope,
        jws,
        publicKey: signer.publicKey,
        kid: signer.kid,
      }),
    ).toBe(true);

    for (const key of Object.keys(envelope)) {
      const mutated = structuredClone(envelope) as Record<string, unknown>;
      const value = mutated[key];
      if (typeof value === "string") {
        mutated[key] = `${value}x`;
      } else if (typeof value === "number") {
        mutated[key] = value + 1;
      } else if (value !== null && typeof value === "object") {
        const nested = value as Record<string, unknown>;
        const nestedKey = Object.keys(nested)[0];
        const nestedValue = nested[nestedKey];
        if (typeof nestedValue === "string") {
          nested[nestedKey] = `${nestedValue}x`;
        } else if (typeof nestedValue === "number") {
          nested[nestedKey] = (nestedValue as number) + 1;
        }
      }
      expect(
        await verifyGrantSignature({
          envelope: mutated,
          jws,
          publicKey: signer.publicKey,
          kid: signer.kid,
        }),
      ).toBe(false);
    }

    expect(validateCoverageSnapshot(coverageSnapshotVector)).toEqual({
      ok: true,
    });

    expect(validateFeedEvent(feedEventVector)).toEqual({ ok: true });
    const altKind = { ...feedEventVector, kind: "coverage_updated" };
    expect(validateFeedEvent(altKind)).toEqual({ ok: true });

    const { installation_id, clinic_seq } = identifierVectors.coverage_event_id;
    expect(await coverageEventId(installation_id, clinic_seq)).toBe(
      feedEventVector.event_id,
    );
  });
});
