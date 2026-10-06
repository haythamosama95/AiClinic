import { CHANNEL_VERSIONS } from "vendor-contracts";
import { env } from "./env";
import { mintVendorAccessJwt } from "./aat";

export type VendorResultEnvelope = {
  contract_version?: number;
  result: string;
  code: string;
  detail: string;
  receipt?: unknown;
};

export type VendorMethod =
  | "publishRoutingPolicy"
  | "canaryRoutingPolicy"
  | "promoteRoutingPolicy"
  | "rollbackRoutingPolicy"
  | "armKillSwitch"
  | "disarmKillSwitch"
  | "deprecateCapability"
  | "retireCapability"
  | "activateCohort"
  | "promoteCohort"
  | "beginTokenContractRotation"
  | "retireTokenContract"
  | "supportLookup"
  | "suspend"
  | "resume"
  | "deleteInstallation";

const VENDOR_CONTRACT_VERSION = CHANNEL_VERSIONS.vendorEntrypoint;

export function vendorEnvelopeToHttp(
  envelope: VendorResultEnvelope,
): { status: number; json: Record<string, unknown> } {
  if (envelope.result === "ok") {
    const json =
      envelope.detail.length > 0
        ? (JSON.parse(envelope.detail) as Record<string, unknown>)
        : {};
    return { status: 200, json };
  }
  if (envelope.result === "conflict") {
    return { status: 409, json: { error: envelope.code } };
  }
  if (envelope.code === "unauthenticated") {
    return { status: 401, json: { error: "unauthorized" } };
  }
  return { status: 400, json: { error: envelope.code } };
}

export async function vendorCall(
  method: VendorMethod,
  args: Record<string, unknown>,
  opts: {
    accessJwt?: string;
    assertion?: Record<string, unknown>;
  } = {},
): Promise<VendorResultEnvelope> {
  const payload: Record<string, unknown> = {
    contract_version: VENDOR_CONTRACT_VERSION,
    ...args,
  };
  if (opts.accessJwt !== undefined) {
    payload.access_jwt = opts.accessJwt;
  }
  if (opts.assertion !== undefined) {
    payload.assertion = opts.assertion;
  }
  const vendor = env.VENDOR as Record<
    string,
    (args: Record<string, unknown>) => Promise<VendorResultEnvelope>
  >;
  return vendor[method](payload);
}

export type ControlAuthVariant =
  | "operator"
  | "none"
  | "wrong"
  | "empty"
  | "basic"
  | "no-scheme"
  | { bearer: string }
  | { authorization: string | null };

export async function vendorAccessJwtForControlAuth(
  auth: ControlAuthVariant,
): Promise<string | undefined> {
  if (auth === "none" || auth === "wrong" || auth === "empty" || auth === "basic") {
    return undefined;
  }
  if (auth === "no-scheme") {
    return undefined;
  }
  if (typeof auth === "object" && "bearer" in auth) {
    return undefined;
  }
  if (typeof auth === "object" && "authorization" in auth) {
    return undefined;
  }
  return mintVendorAccessJwt();
}
