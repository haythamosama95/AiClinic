export const CHANNEL_VERSIONS = {
  aboClinic: 1,
  aboConsole: 1,
  backendRpc: 1,
  platformClinic: 1,
  platformFeed: 1,
  vendorEntrypoint: 1,
  platformDo: 1,
  paymobReturn: 1,
  paymobAdapter: 1,
} as const;

export function acceptedVersions(current: number): number[] {
  return [current - 1, current];
}

export function negotiate(
  current: number,
  requested: number | null,
):
  | { ok: true; version: number }
  | {
      ok: false;
      code: "contract_version_unsupported";
      accepted_versions: number[];
    } {
  const accepted = acceptedVersions(current);
  if (requested === null) {
    return {
      ok: false,
      code: "contract_version_unsupported",
      accepted_versions: accepted,
    };
  }
  if (requested === current || requested === current - 1) {
    return { ok: true, version: requested };
  }
  return {
    ok: false,
    code: "contract_version_unsupported",
    accepted_versions: accepted,
  };
}
