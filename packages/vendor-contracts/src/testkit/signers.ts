import { canonicalize } from "../canonical.js";
import { signCompactJws } from "../jws.js";
import { TESTKIT_MARKER } from "./index.js";

async function createEd25519Signer(): Promise<{
  kid: string;
  publicKey: CryptoKey;
  privateKey: CryptoKey;
}> {
  const pair = await crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  );
  const kid = crypto.randomUUID();
  return {
    kid,
    publicKey: pair.publicKey,
    privateKey: pair.privateKey,
  };
}

export async function createAboGrantSigner(): Promise<{
  kid: string;
  publicKey: CryptoKey;
  sign(envelope: unknown): Promise<string>;
}> {
  void TESTKIT_MARKER;
  const { kid, publicKey, privateKey } = await createEd25519Signer();
  return {
    kid,
    publicKey,
    async sign(envelope: unknown): Promise<string> {
      void TESTKIT_MARKER;
      return signCompactJws({
        payload: canonicalize(envelope),
        privateKey,
        kid,
      });
    },
  };
}

export async function createPlatformReceiptSigner(): Promise<{
  kid: string;
  publicKey: CryptoKey;
  sign(receiptWithoutSignature: unknown): Promise<string>;
}> {
  void TESTKIT_MARKER;
  const { kid, publicKey, privateKey } = await createEd25519Signer();
  return {
    kid,
    publicKey,
    async sign(receiptWithoutSignature: unknown): Promise<string> {
      void TESTKIT_MARKER;
      const payload =
        typeof receiptWithoutSignature === "object" &&
        receiptWithoutSignature !== null &&
        !Array.isArray(receiptWithoutSignature)
          ? { ...receiptWithoutSignature, kid }
          : receiptWithoutSignature;
      return signCompactJws({
        payload: canonicalize(payload),
        privateKey,
        kid,
      });
    },
  };
}
