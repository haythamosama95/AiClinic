import { verifyReceiptSignature } from "vendor-contracts";

export async function verifyTransferReceipt(input: {
  platformPublicKeys: string;
  receipt: unknown;
  transferId: string;
  orgId: string;
  installationId: string;
  contractVersion: number;
}): Promise<boolean> {
  if (typeof input.receipt !== "object" || input.receipt === null || Array.isArray(input.receipt)) {
    return false;
  }
  const receipt = input.receipt as Record<string, unknown>;
  if (
    receipt.transfer_id !== input.transferId ||
    receipt.org_id !== input.orgId ||
    receipt.installation_id !== input.installationId ||
    receipt.contract_version !== input.contractVersion ||
    receipt.result !== "applied" ||
    typeof receipt.signature !== "string" ||
    typeof receipt.kid !== "string" ||
    typeof receipt.envelope_sha256 !== "string" ||
    !/^[a-f0-9]{64}$/u.test(receipt.envelope_sha256) ||
    !Number.isSafeInteger(receipt.ledger_seq) || Number(receipt.ledger_seq) <= 0 ||
    typeof receipt.applied_at !== "string" || !Number.isSafeInteger(Date.parse(receipt.applied_at)) ||
    !Array.isArray(receipt.term_ids) ||
    !receipt.term_ids.every((value) => typeof value === "string" && value.length > 0)
  ) return false;

  let keys: unknown;
  try {
    keys = JSON.parse(input.platformPublicKeys) as unknown;
  } catch {
    return false;
  }
  if (!Array.isArray(keys)) return false;
  const key = keys.find((value) =>
    typeof value === "object" && value !== null &&
    (value as Record<string, unknown>).kid === receipt.kid &&
    typeof (value as Record<string, unknown>).public_key === "string",
  ) as Record<string, unknown> | undefined;
  if (key === undefined) return false;
  const encoded = key.public_key as string;
  if (!/^[A-Za-z0-9_-]+$/u.test(encoded)) return false;
  const base64 = encoded.replace(/-/g, "+").replace(/_/g, "/");
  let raw: Uint8Array;
  try {
    const binary = atob(base64 + "=".repeat((4 - (base64.length % 4 || 4)) % 4));
    raw = Uint8Array.from(binary, (char) => char.charCodeAt(0));
  } catch {
    return false;
  }
  let publicKey: CryptoKey;
  try {
    publicKey = await crypto.subtle.importKey(
      "raw", raw, { name: "Ed25519" }, false, ["verify"],
    );
  } catch {
    return false;
  }
  return verifyReceiptSignature({ receipt, publicKey });
}
