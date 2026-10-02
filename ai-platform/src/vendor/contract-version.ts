import { CHANNEL_VERSIONS, negotiate } from "vendor-contracts";

const AIP_CONTRACT_VERSION_HEADER = "Aip-Contract-Version";

function parseRequestedVersion(request: Request): number | null {
  const raw = request.headers.get(AIP_CONTRACT_VERSION_HEADER);
  if (raw === null) {
    return null;
  }
  if (!/^(0|[1-9][0-9]*)$/.test(raw)) {
    return Number.MIN_SAFE_INTEGER;
  }
  return Number(raw);
}

export function requireAipContractVersion(
  request: Request,
):
  | { ok: true; version: number }
  | { ok: false; response: Response } {
  const requested = parseRequestedVersion(request);
  const result = negotiate(CHANNEL_VERSIONS.platformClinic, requested);
  if (!result.ok) {
    return {
      ok: false,
      response: Response.json(
        {
          code: result.code,
          accepted_versions: result.accepted_versions,
        },
        { status: 400 },
      ),
    };
  }
  return { ok: true, version: result.version };
}

export function withAipContractVersion(
  response: Response,
  version: number,
): Response {
  const headers = new Headers(response.headers);
  headers.set(AIP_CONTRACT_VERSION_HEADER, String(version));
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
