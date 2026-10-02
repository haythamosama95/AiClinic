import { canonicalize } from "../canonical.js";
import { base64UrlEncode } from "../base64url.js";
import { TESTKIT_MARKER } from "./index.js";

const textEncoder = new TextEncoder();

type TokenAudience = "ai-platform" | "abo" | "ai-platform-feed";

async function signJwt(input: {
  privateKey: CryptoKey;
  kid: string;
  audience: TokenAudience;
  issuerId: string;
  claims: Record<string, unknown>;
}): Promise<string> {
  const headerBytes = canonicalize({
    alg: "EdDSA",
    kid: input.kid,
    typ: "JWT",
  });
  const payload = {
    iss: input.issuerId,
    ver: "2",
    aud: input.audience,
    ...input.claims,
  };
  const payloadBytes = canonicalize(payload);
  const headerSegment = base64UrlEncode(headerBytes);
  const payloadSegment = base64UrlEncode(payloadBytes);
  const signingInput = textEncoder.encode(`${headerSegment}.${payloadSegment}`);
  const signature = await crypto.subtle.sign(
    { name: "Ed25519" },
    input.privateKey,
    signingInput,
  );
  const signatureSegment = base64UrlEncode(new Uint8Array(signature));
  return `${headerSegment}.${payloadSegment}.${signatureSegment}`;
}

export async function createIssuer(input: {
  issuerId: string;
}): Promise<{
  kid: string;
  publicKey: CryptoKey;
  mintAi(claims: {
    sub: string;
    org: string;
    role: string;
    branch: string;
    scopes: string[];
    iat: number;
    exp: number;
    jti: string;
  }): Promise<string>;
  mintBilling(claims: {
    sub: string;
    org: string;
    role: string;
    branch: string;
    iat: number;
    exp: number;
    jti: string;
  }): Promise<string>;
  mintFeed(claims: {
    iat: number;
    exp: number;
    jti: string;
    org?: string;
  }): Promise<string>;
}> {
  void TESTKIT_MARKER;
  const pair = await crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"],
  );
  const kid = crypto.randomUUID();

  const signForAudience = (
    audience: TokenAudience,
    claims: Record<string, unknown>,
  ): Promise<string> =>
    signJwt({
      privateKey: pair.privateKey,
      kid,
      audience,
      issuerId: input.issuerId,
      claims,
    });

  return {
    kid,
    publicKey: pair.publicKey,
    async mintAi(claims) {
      void TESTKIT_MARKER;
      return signForAudience("ai-platform", claims);
    },
    async mintBilling(claims) {
      void TESTKIT_MARKER;
      return signForAudience("abo", claims);
    },
    async mintFeed(claims) {
      void TESTKIT_MARKER;
      const { org, ...rest } = claims;
      const payload: Record<string, unknown> = {
        sub: "backend-feed",
        ...rest,
      };
      if (org !== undefined) {
        payload.org = org;
      }
      return signForAudience("ai-platform-feed", payload);
    },
  };
}
