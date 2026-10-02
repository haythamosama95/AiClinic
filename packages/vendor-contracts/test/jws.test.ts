import { describe, expect, it } from "vitest";
import * as vendorContracts from "vendor-contracts";
import jwsVector from "../vectors/jws.json";

function bytesFromHex(hex: string): Uint8Array {
  return Uint8Array.from(Buffer.from(hex, "hex"));
}

async function importPrivateKey(pkcs8Hex: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "pkcs8",
    bytesFromHex(pkcs8Hex),
    { name: "Ed25519" },
    false,
    ["sign"],
  );
}

async function importPublicKey(rawHex: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    bytesFromHex(rawHex),
    { name: "Ed25519" },
    false,
    ["verify"],
  );
}

describe("jws", () => {
  it("E2E-P2.1-02 reproduces the fixture JWS and verifies it; rejects tampering", async () => {
    const { signCompactJws, verifyCompactJws } = vendorContracts;
    expect(signCompactJws).toBeTypeOf("function");
    expect(verifyCompactJws).toBeTypeOf("function");

    const privateKey = await importPrivateKey(jwsVector.private_key_pkcs8_hex);
    const publicKey = await importPublicKey(jwsVector.public_key_raw_hex);
    const payload = bytesFromHex(jwsVector.payload_canonical_hex);

    const signed = await signCompactJws({
      payload,
      privateKey,
      kid: jwsVector.kid,
    });
    expect(signed).toBe(jwsVector.compact_jws);

    expect(
      await verifyCompactJws({
        jws: jwsVector.compact_jws,
        publicKey,
        kid: jwsVector.kid,
      }),
    ).toBe(true);

    const tamperedPayload = new Uint8Array(payload);
    tamperedPayload[0] ^= 0xff;
    const tamperedJws = await signCompactJws({
      payload: tamperedPayload,
      privateKey,
      kid: jwsVector.kid,
    });
    expect(
      await verifyCompactJws({
        jws: tamperedJws,
        publicKey,
        kid: jwsVector.kid,
      }),
    ).toBe(false);

    expect(
      await verifyCompactJws({
        jws: jwsVector.compact_jws,
        publicKey,
        kid: "wrong-kid",
      }),
    ).toBe(false);
  });
});
