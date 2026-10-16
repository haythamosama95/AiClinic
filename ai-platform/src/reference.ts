const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const REFERENCE_PATTERN = /^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/;

export function generateRequestReference(): string {
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  return (
    ALPHABET[bytes[0] % 32] +
    ALPHABET[bytes[1] % 32] +
    ALPHABET[bytes[2] % 32] +
    ALPHABET[bytes[3] % 32] +
    "-" +
    ALPHABET[bytes[4] % 32] +
    ALPHABET[bytes[5] % 32] +
    ALPHABET[bytes[6] % 32] +
    ALPHABET[bytes[7] % 32]
  );
}

export function normalizeRequestReference(input: string): string {
  return input
    .toUpperCase()
    .replace(/I/g, "1")
    .replace(/L/g, "1")
    .replace(/O/g, "0");
}

/** True when `normalized` already matches the Crockford base32 reference format. */
export function isValidRequestReference(normalized: string): boolean {
  return REFERENCE_PATTERN.test(normalized);
}
