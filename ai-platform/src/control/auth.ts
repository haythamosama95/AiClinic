import type { OperatorAuth } from "./types";

/** Constant-time UTF-8 compare so bearer verification does not short-circuit on length. */
function timingSafeEqualString(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  const len = Math.max(a.byteLength, b.byteLength);
  let diff = a.byteLength ^ b.byteLength;
  for (let i = 0; i < len; i++) {
    diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return diff === 0;
}

/**
 * Production operator auth: verify `Authorization: Bearer` against a Workers secret
 * and return the configured stable operator id — never the credential itself.
 */
export function createSecretOperatorAuth(options: {
  bearerToken: string;
  operatorId: string;
}): OperatorAuth {
  const configuredToken = options.bearerToken;
  const configuredOperatorId = options.operatorId;
  return {
    resolve(request: Request) {
      if (!configuredToken || !configuredOperatorId) {
        return null;
      }
      const authorization = request.headers.get("authorization");
      if (!authorization?.startsWith("Bearer ")) {
        return null;
      }
      const token = authorization.slice("Bearer ".length).trim();
      if (!token) {
        return null;
      }
      if (!timingSafeEqualString(token, configuredToken)) {
        return null;
      }
      return { operatorId: configuredOperatorId };
    },
  };
}
