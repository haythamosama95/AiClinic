import { describe, expect, it } from "vitest";
import * as vendorContracts from "vendor-contracts";
import * as testkit from "vendor-contracts/testkit";
import receiptVector from "../vectors/receipt.json";
import resultEnvelopeVector from "../vectors/result-envelope.json";

function requireExport(
  exports: Record<string, unknown>,
  name: string,
): (...args: never[]) => unknown {
  expect(exports[name], `${name} export`).toBeTypeOf("function");
  return exports[name] as (...args: never[]) => unknown;
}

describe("receipt", () => {
  it("E2E-P2.2-06 Receipt signature verifies; tampered term_ids fails", async () => {
    const validateReceipt = requireExport(vendorContracts, "validateReceipt");
    const verifyReceiptSignature = requireExport(
      vendorContracts,
      "verifyReceiptSignature",
    );
    const validateResultEnvelope = requireExport(
      vendorContracts,
      "validateResultEnvelope",
    );
    const createPlatformReceiptSigner = requireExport(
      testkit as Record<string, unknown>,
      "createPlatformReceiptSigner",
    );

    expect(validateResultEnvelope(resultEnvelopeVector)).toEqual({ ok: true });

    const receipt = structuredClone(receiptVector) as Record<string, unknown>;
    const { signature: _ignored, ...receiptWithoutSignature } = receipt;
    void _ignored;

    const signer = (await createPlatformReceiptSigner()) as {
      kid: string;
      publicKey: CryptoKey;
      sign: (value: unknown) => Promise<string>;
    };
    receipt.kid = signer.kid;
    receipt.signature = await signer.sign(receiptWithoutSignature);

    expect(validateReceipt(receipt)).toEqual({ ok: true });
    expect(
      await verifyReceiptSignature({
        receipt,
        publicKey: signer.publicKey,
      }),
    ).toBe(true);

    const tampered = structuredClone(receipt) as Record<string, unknown>;
    tampered.term_ids = ["TERM-001", "TERM-TAMPERED"];
    expect(
      await verifyReceiptSignature({
        receipt: tampered,
        publicKey: signer.publicKey,
      }),
    ).toBe(false);
  });
});
