const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

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
