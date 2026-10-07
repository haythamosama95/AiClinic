import {
  CHANNEL_VERSIONS,
  acceptedVersions,
  negotiate,
} from "vendor-contracts";

export type ContractChannel = "aboClinic" | "aboConsole";

export type VersionEnv = {
  DB?: D1Database;
};

export function parseContractVersionHeader(
  request: Request,
): number | null {
  const raw = request.headers.get("Abo-Contract-Version");
  if (raw === null || raw.trim() === "") {
    return null;
  }
  const parsed = Number(raw);
  if (!Number.isInteger(parsed)) {
    return null;
  }
  return parsed;
}

export function currentChannelVersion(channel: ContractChannel): number {
  return CHANNEL_VERSIONS[channel];
}

export type VersionGateSuccess = {
  ok: true;
  version: number;
  current: number;
};

export type VersionGateFailure = {
  ok: false;
  response: Response;
};

async function recordChannelVersionSeen(
  env: VersionEnv,
  channel: ContractChannel,
  contractVersion: number,
  unsupported: boolean,
): Promise<void> {
  if (env.DB === undefined) {
    return;
  }
  try {
    await env.DB.prepare(
      `INSERT INTO channel_version_seen (
         channel, contract_version, received, unsupported
       ) VALUES (?, ?, 1, ?)
       ON CONFLICT(channel, contract_version) DO UPDATE SET
         received = received + 1,
         unsupported = unsupported + excluded.unsupported`,
    )
      .bind(channel, contractVersion, unsupported ? 1 : 0)
      .run();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (/no such table/i.test(message)) {
      return;
    }
    throw error;
  }
}

export function checkContractVersion(
  request: Request,
  channel: ContractChannel,
  env?: VersionEnv,
): VersionGateSuccess | VersionGateFailure {
  const current = currentChannelVersion(channel);
  const requested = parseContractVersionHeader(request);
  const result = negotiate(current, requested);
  if (!result.ok) {
    if (env !== undefined) {
      void recordChannelVersionSeen(env, channel, current, true).catch(() => {
        // Version-gate recording failures must not block the refusal.
      });
    }
    const body = {
      code: result.code,
      message: result.code,
      contract_version: current,
      accepted_versions: result.accepted_versions,
    };
    return {
      ok: false,
      response: new Response(JSON.stringify(body), {
        status: 400,
        headers: {
          "content-type": "application/json",
          "Abo-Contract-Version": String(current),
        },
      }),
    };
  }
  if (env !== undefined) {
    void recordChannelVersionSeen(env, channel, result.version, false).catch(
      () => {
        // Version-gate recording failures must not block the request.
      },
    );
  }
  return { ok: true, version: result.version, current };
}

export function clinicJsonResponse(
  body: Record<string, unknown>,
  status: number,
  contractVersion: number,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "Abo-Contract-Version": String(contractVersion),
    },
  });
}

export function clinicErrorResponse(
  code: string,
  status: number,
  contractVersion: number,
  extra?: Record<string, unknown>,
): Response {
  return clinicJsonResponse(
    {
      code,
      message: code,
      contract_version: contractVersion,
      ...extra,
    },
    status,
    contractVersion,
  );
}
