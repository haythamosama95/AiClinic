import { describe, expect, it } from "vitest";
import { createPlatformReceiptSigner } from "vendor-contracts/testkit";
import { validateGrantReceipt } from "../../src/work/grant-receipt.js";

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/u, "");
}

describe("grant receipt validation", () => {
  it("R4-A2: validates signed request linkage and rejects altered schema or identity", async () => {
    const signer = await createPlatformReceiptSigner();
    const raw = new Uint8Array(await crypto.subtle.exportKey("raw", signer.publicKey));
    const publicKeys = JSON.stringify([{ kid: signer.kid, public_key: base64Url(raw) }]);
    const request = {
      grant_id: "a".repeat(64),
      org_id: "a4440001-0001-4001-8001-000000000001",
      envelope_sha256: "b".repeat(64),
      envelope: JSON.stringify({ contract_version: 7 }),
    };
    const receipt = async (overrides: Record<string, unknown> = {}) => {
      const unsigned = {
        contract_version: 7,
        grant_id: request.grant_id,
        installation_id: "a4440001-0002-4001-8001-000000000002",
        org_id: request.org_id,
        result: "applied",
        term_ids: ["term-1"],
        applied_at: "2026-10-19T12:00:00.000Z",
        ledger_seq: 1,
        envelope_sha256: request.envelope_sha256,
        ...overrides,
      };
      return { ...unsigned, kid: signer.kid, signature: await signer.sign(unsigned) };
    };

    expect(await validateGrantReceipt({ platformPublicKeys: publicKeys, request, receipt: await receipt() })).toBe(true);
    expect(await validateGrantReceipt({
      platformPublicKeys: publicKeys,
      request,
      receipt: await receipt({ org_id: "a4440002-0001-4002-8002-000000000002" }),
    })).toBe(false);
    expect(await validateGrantReceipt({
      platformPublicKeys: publicKeys,
      request,
      receipt: await receipt({ ledger_seq: 0 }),
    })).toBe(false);
    expect(await validateGrantReceipt({
      platformPublicKeys: publicKeys,
      request,
      receipt: await receipt({ term_ids: [] }),
    })).toBe(false);
  });
});
