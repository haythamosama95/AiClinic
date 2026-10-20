import { describe, expect, it } from "vitest";
import { createPlatformReceiptSigner } from "vendor-contracts/testkit";
import { verifyTransferReceipt } from "../../src/work/transfer-receipt.js";

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/u, "");
}

describe("transfer receipt validation", () => {
  it("R9-REC2 verifies signed terminal transfer receipt identity and rejects altered linkage", async () => {
    const signer = await createPlatformReceiptSigner();
    const raw = new Uint8Array(await crypto.subtle.exportKey("raw", signer.publicKey));
    const platformPublicKeys = JSON.stringify([
      { kid: signer.kid, public_key: base64Url(raw) },
    ]);
    const input = {
      transferId: "tr-r9-receipt",
      orgId: "a4110002-0002-4011-8011-000000000002",
      installationId: "install-r9-target",
      contractVersion: 7,
    };
    const unsigned = {
      contract_version: input.contractVersion,
      transfer_id: input.transferId,
      installation_id: input.installationId,
      org_id: input.orgId,
      result: "applied",
      term_ids: ["term-r9-1"],
      applied_at: "2026-10-20T12:00:00.000Z",
      ledger_seq: 4,
      envelope_sha256: "a".repeat(64),
    };
    const receipt = {
      ...unsigned,
      kid: signer.kid,
      signature: await signer.sign(unsigned),
    };
    expect(await verifyTransferReceipt({ platformPublicKeys, receipt, ...input })).toBe(true);
    expect(await verifyTransferReceipt({
      platformPublicKeys,
      receipt: { ...receipt, transfer_id: "tr-other" },
      ...input,
    })).toBe(false);
  });
});
