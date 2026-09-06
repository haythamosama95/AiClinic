/**
 * Size-capped capture of raw provider response bodies for the R2 diagnostic
 * envelope (§7.4.1 — one object per request). Not a store.
 */

export const ENVELOPE_RAW_BODY_BYTE_LIMIT = 16 * 1024;

export type CapturedRawBody = {
  payload: unknown;
  truncated: boolean;
};

export function captureRawProviderBody(
  text: string,
  byteLimit: number = ENVELOPE_RAW_BODY_BYTE_LIMIT,
): CapturedRawBody {
  const encoded = new TextEncoder().encode(text);
  if (encoded.byteLength <= byteLimit) {
    try {
      return { payload: JSON.parse(text) as unknown, truncated: false };
    } catch {
      return { payload: text, truncated: false };
    }
  }
  // Slice-then-decode can split a multi-byte UTF-8 sequence. The decoder
  // inserts U+FFFD, and re-encoding that replacement can exceed byteLimit.
  let decoded = new TextDecoder().decode(encoded.slice(0, byteLimit));
  decoded = decoded.replace(/\uFFFD+$/, "");
  while (
    decoded.length > 0 &&
    new TextEncoder().encode(decoded).byteLength > byteLimit
  ) {
    decoded = decoded.slice(0, -1);
  }
  return { payload: decoded, truncated: true };
}

export function withRawBody<T extends { rawBody?: CapturedRawBody }>(
  result: T,
  text: string | undefined,
): T {
  if (text === undefined) {
    return result;
  }
  return { ...result, rawBody: captureRawProviderBody(text) };
}
