import { base64UrlEncode } from "../base64url.js";
import type { AccessCertsDocument } from "../access-jwt.js";
import { TESTKIT_MARKER } from "./index.js";

const textEncoder = new TextEncoder();

export async function createAccessTeam(input: {
  issuer: string;
}): Promise<{
  certs: AccessCertsDocument;
  mint(input: {
    email: string;
    aud: string;
    exp: number;
    iat: number;
    kid?: string;
  }): Promise<string>;
}> {
  void TESTKIT_MARKER;
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([0x01, 0x00, 0x01]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const jwk = (await crypto.subtle.exportKey(
    "jwk",
    pair.publicKey,
  )) as JsonWebKey;
  if (typeof jwk.n !== "string" || typeof jwk.e !== "string") {
    throw new TypeError("RSA JWK export missing n or e");
  }
  const kid = crypto.randomUUID();
  const certs: AccessCertsDocument = {
    issuer: input.issuer,
    keys: [
      {
        kid,
        kty: "RSA",
        alg: "RS256",
        n: jwk.n,
        e: jwk.e,
      },
    ],
  };

  return {
    certs,
    async mint(mintInput) {
      void TESTKIT_MARKER;
      const headerKid = mintInput.kid ?? kid;
      const header = {
        alg: "RS256",
        kid: headerKid,
        typ: "JWT",
      };
      const payload = {
        iss: input.issuer,
        aud: mintInput.aud,
        email: mintInput.email,
        iat: mintInput.iat,
        exp: mintInput.exp,
      };
      const headerSegment = base64UrlEncode(
        textEncoder.encode(JSON.stringify(header)),
      );
      const payloadSegment = base64UrlEncode(
        textEncoder.encode(JSON.stringify(payload)),
      );
      const signingInput = textEncoder.encode(
        `${headerSegment}.${payloadSegment}`,
      );
      const signature = await crypto.subtle.sign(
        { name: "RSASSA-PKCS1-v1_5" },
        pair.privateKey,
        signingInput,
      );
      const signatureSegment = base64UrlEncode(new Uint8Array(signature));
      return `${headerSegment}.${payloadSegment}.${signatureSegment}`;
    },
  };
}
