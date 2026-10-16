/**
 * Fixed Access team material for H-XW (shared by vitest fetchMock and harness JWT mint).
 */

const ACCESS_ISSUER = "https://access.test";

const ACCESS_CERTS = {
  keys: [
    {
      kid: "hxw-access-test",
      kty: "RSA",
      alg: "RS256",
      n:
        "xMIKMmlJKgCRxRFWgQP8LHgKowKzsqtskoLWlxdqvkTv1Vb5j_6v2BhjHHPiv1awOMyUuOPKEpgvw3FgFwxeRXuDF0KJiMLArnF5IOBPx-srym9drWlPbZjntkN6bl-ZxEosMvzyt5V2ZuFipgQuOIQya9EWe_APEXby2BcAOB8_g1iB0yEl1GPK2a3Kt-5NjqTrePI-P6seXvt3qFfN9qIByiH0A0_5clAjRBup_8zBLTT2oPMA25WrnVdUsH3WzMO2qBzs3C9xewH90DuvlQzFCxWPs5HkgyP4miA2daEwiXMQsK97UMx3PANyUXt3tBtLU9otWbmWZJY6_Ql46w",
      e: "AQAB",
    },
  ],
} as const;

const ACCESS_PKCS8_B64 =
  "MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDEwgoyaUkqAJHFEVaBA/wseAqjArOyq2ySgtaXF2q+RO/VVvmP/q/YGGMcc+K/VrA4zJS448oSmC/DcWAXDF5Fe4MXQomIwsCucXkg4E/H6yvKb12taU9tmOe2Q3puX5nESiwy/PK3lXZm4WKmBC44hDJr0RZ78A8RdvLYFwA4Hz+DWIHTISXUY8rZrcq37k2OpOt48j4/qx5e+3eoV832ogHKIfQDT/lyUCNEG6n/zMEtNPag8wDblaudV1SwfdbMw7aoHOzcL3F7Af3QO6+VDMULFY+zkeSDI/iaIDZ1oTCJcxCwr3tQzHc8A3JRe3e0G0tT2i1ZuZZkljr9CXjrAgMBAAECggEAFqYfdl4YRfV60iyEwKUsyhGnZ8xP0ylYfiUBfrL7Xpug3/X7FFBE/aMRBZ1xZIUeE+u40u+luy45kU3jucN6tpTZKjxGiK+ibnIxd09a37B6gfr/1Y5hzkPjqF9sIHhwwt+m5tenOOrDjmQzbtjcWTUeeLrA09N2aJRAsA81vz/lhr/tMONl3KQr+pDMGCf2/qtwJHZUlyBC8dsVSmx4uUo2GgJmG5H4T8b/wG5NnzTpuo+GLPglPnnkZceBlNo98u+wL3FLozXJZ+DmTLp1PMeEvHxzv/BEJaNiBEfwSlcJDpOCywEZ1+Cv79N28jkTl+D5/Igb4BAdA3IaUChaAQKBgQD+AvxtM1HU6dL3/kDT9PIZzV36RlwGQ5h5Eon1Ady2Q5BXwTQEtkj6fHU3WqYQXGpJuMUh2SGlmvep27HDkeoWDfCYQuhUT+RQKJIF/ul9dWSJ3BLQ1GT+NSXuLiS+JmsgozqkCTFVlxx0c4wxC71z0S+rQGNpHmAssAvhOm/zSwKBgQDGTFK3eyQO8l6UdgD2dTSylGa+tPI2cS9aB0jRdl7Aod3VU9bbAl6M4cobKvNb0575PL39nuHXXOE8Im41NpvNVDcvzJY41hYJPXSlGTxpQj6TjFuCdJ8NMlFlGwRGAmgrZjN9zrlviHcB84PI0QH1McOnwwlZQ+atuXT68GNs4QKBgQDdIv5dl0MTqCj5q4kGvgWTPv4k5+IvteNk7CXcfi2HI9TjARlnTMbGA1oMwcc3ES2bVteQOzcWtI4Oe2wMBdkUMDiYZg9bb14mBtvxilX92hiYCFb9JRtzUBPggp2MSWgUNubTbglcKT0liH6xKDZcQO5OGbUyC7bQ0MbW4wgZdwKBgFROaLB3Wyo7ozhtPxWJWSE/dLtJxNyenGojRLNBJyGw79ZdsbAlPruY10tbpGF7BFCkoYXtgckFRQFDBiX7lJvkXR4mVgvOAUpmZWw34XZC4sXqW5GIMYLzzKU2qkd1iIJDDktDk5U2qJocxP+g1LtBMBToF9Zqxu0/NtvlTfAhAoGBAKL83SSkJWdK9CR61gfnFJJRWMWQNtnuodNHtP4qXXg6xugq9IrrC5uAtY0n/rV5M2s8/v8p6oKDkglfDRzZdeDdvlFOnXQFTfz4QZ4TZdJo7618hQGtR905eWlCQTQovxQ4KngJay7rtE8QOQjDFWs7HqldPorKcp3B7qbLtjDA";

let privateKeyPromise: Promise<CryptoKey> | null = null;

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/u, "");
}

async function accessPrivateKey(): Promise<CryptoKey> {
  if (privateKeyPromise === null) {
    const pkcs8 = Uint8Array.from(atob(ACCESS_PKCS8_B64), (c) => c.charCodeAt(0));
    privateKeyPromise = crypto.subtle.importKey(
      "pkcs8",
      pkcs8,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );
  }
  return privateKeyPromise;
}

export function hxwAccessCertsJson(): string {
  return JSON.stringify({ keys: ACCESS_CERTS.keys });
}

export async function mintHxwVendorAccessJwt(
  aud: string,
  email: string,
  nowSeconds?: number,
  options?: { iss?: string },
): Promise<string> {
  const now = nowSeconds ?? Math.floor(Date.now() / 1000);
  const header = {
    alg: "RS256",
    kid: ACCESS_CERTS.keys[0].kid,
    typ: "JWT",
  };
  const payload = {
    iss: options?.iss ?? ACCESS_ISSUER,
    aud,
    email,
    jti: crypto.randomUUID(),
    iat: now - 60,
    exp: now + 3600,
  };
  const headerSegment = base64UrlEncode(
    new TextEncoder().encode(JSON.stringify(header)),
  );
  const payloadSegment = base64UrlEncode(
    new TextEncoder().encode(JSON.stringify(payload)),
  );
  const signingInput = new TextEncoder().encode(
    `${headerSegment}.${payloadSegment}`,
  );
  const signature = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    await accessPrivateKey(),
    signingInput,
  );
  const signatureSegment = base64UrlEncode(new Uint8Array(signature));
  return `${headerSegment}.${payloadSegment}.${signatureSegment}`;
}
