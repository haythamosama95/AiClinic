export function base64urlEncode(data: string | Uint8Array): string {
  const bytes =
    typeof data === "string" ? new TextEncoder().encode(data) : data;
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/u, "");
}

export function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

export type TestKeypair = {
  publicKey: CryptoKey;
  privateKey: CryptoKey;
  kid: string;
  publicKeyB64: string;
};

export async function generateTestKeypair(
  kid: string = crypto.randomUUID(),
): Promise<TestKeypair> {
  const keyPair = (await crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  const rawPublicKey = await crypto.subtle.exportKey("raw", keyPair.publicKey);
  return {
    publicKey: keyPair.publicKey,
    privateKey: keyPair.privateKey,
    kid,
    publicKeyB64: base64urlEncode(new Uint8Array(rawPublicKey)),
  };
}

export async function signBytes(
  privateKey: CryptoKey,
  data: Uint8Array | string,
): Promise<Uint8Array> {
  const bytes =
    typeof data === "string" ? new TextEncoder().encode(data) : data;
  const signature = await crypto.subtle.sign(
    { name: "Ed25519" },
    privateKey,
    bytes,
  );
  return new Uint8Array(signature);
}

/**
 * Compact JWS (EdDSA). `header` and `payload` are serialized with
 * `JSON.stringify` as given — key order is the caller's.
 */
export async function signJwt(input: {
  header: Record<string, unknown>;
  payload: Record<string, unknown>;
  privateKey: CryptoKey;
}): Promise<string> {
  const headerB64 = base64urlEncode(JSON.stringify(input.header));
  const payloadB64 = base64urlEncode(JSON.stringify(input.payload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const signature = await signBytes(input.privateKey, signingInput);
  return `${signingInput}.${base64urlEncode(signature)}`;
}
