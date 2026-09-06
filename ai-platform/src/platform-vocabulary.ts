/** Closed commercial tier vocabulary — shared by control-plane enroll and entitlement guard. */
export const PLAN_TIERS = [
  "starter",
  "standard",
  "professional",
  "enterprise",
] as const;

export type PlanTier = (typeof PLAN_TIERS)[number];

/** Only algorithm accepted for clinic installation keys and AAT verification. */
export const INSTALLATION_KEY_ALGORITHM = "EdDSA" as const;

/** Upper bound for identifier strings stored in D1 and used as cache keys. */
export const MAX_IDENTIFIER_LENGTH = 128;

/** Raw Ed25519 public key material length (bytes). */
export const ED25519_PUBLIC_KEY_BYTE_LENGTH = 32;

const CANONICAL_UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isWithinIdentifierLength(value: string): boolean {
  return value.length > 0 && value.length <= MAX_IDENTIFIER_LENGTH;
}

export function isKnownPlanTier(plan: string): plan is PlanTier {
  return (PLAN_TIERS as readonly string[]).includes(plan);
}

export function isSupportedInstallationKeyAlgorithm(algorithm: string): boolean {
  return algorithm === INSTALLATION_KEY_ALGORITHM;
}

export function isCanonicalUuid(value: string): boolean {
  return isWithinIdentifierLength(value) && CANONICAL_UUID_RE.test(value);
}

/** RFC 4122 hex is case-insensitive; persist and look up the lowercase form. */
export function toCanonicalUuid(value: string): string {
  return value.toLowerCase();
}

export function decodeBase64url(segment: string): Uint8Array | null {
  try {
    const padded = segment + "=".repeat((4 - (segment.length % 4)) % 4);
    const binary = atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  } catch {
    return null;
  }
}

export function isEd25519PublicKeyByteLength(value: string): boolean {
  if (!isWithinIdentifierLength(value)) {
    return false;
  }
  const decoded = decodeBase64url(value);
  return (
    decoded !== null && decoded.length === ED25519_PUBLIC_KEY_BYTE_LENGTH
  );
}

export async function isImportableEd25519PublicKeyBase64url(
  value: string,
): Promise<boolean> {
  if (!isEd25519PublicKeyByteLength(value)) {
    return false;
  }
  const decoded = decodeBase64url(value);
  if (!decoded) {
    return false;
  }
  try {
    await crypto.subtle.importKey(
      "raw",
      decoded,
      { name: "Ed25519" },
      false,
      ["verify"],
    );
    return true;
  } catch {
    return false;
  }
}

export function planTierMeetsMinimum(plan: string, minimum: string): boolean {
  const planRank = PLAN_TIERS.indexOf(plan as PlanTier);
  const minimumRank = PLAN_TIERS.indexOf(minimum as PlanTier);
  if (planRank === -1 || minimumRank === -1) {
    return false;
  }
  return planRank >= minimumRank;
}
