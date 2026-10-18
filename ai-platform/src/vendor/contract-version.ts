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
          contract_version: CHANNEL_VERSIONS.platformClinic,
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

  // Version the JSON payload without consuming it here. Keeping the rewrite in
  // the response stream lets callers return immediately with the negotiated
  // header, which matters for routes that may otherwise hold a stream open.
  const contentType = headers.get("content-type")?.toLowerCase() ?? "";
  const shouldVersionJson =
    response.body !== null &&
    response.status !== 304 &&
    contentType.includes("application/json");

  if (shouldVersionJson) {
    headers.delete("content-length");
    const source = response.body!;
    const body = new ReadableStream<Uint8Array>({
      async pull(controller) {
        const reader = source.getReader();
        const chunks: Uint8Array[] = [];
        let size = 0;
        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            chunks.push(value);
            size += value.byteLength;
          }

          const bytes = new Uint8Array(size);
          let offset = 0;
          for (const chunk of chunks) {
            bytes.set(chunk, offset);
            offset += chunk.byteLength;
          }

          let output = bytes;
          try {
            const parsed: unknown = JSON.parse(new TextDecoder().decode(bytes));
            if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed)) {
              output = new TextEncoder().encode(
                JSON.stringify({ ...parsed, contract_version: version }),
              );
            }
          } catch {
            // Preserve malformed or non-object JSON payloads byte-for-byte;
            // the version header still identifies the negotiated channel.
          }
          controller.enqueue(output);
          controller.close();
        } catch (error) {
          controller.error(error);
        } finally {
          reader.releaseLock();
        }
      },
    }, { highWaterMark: 0 });
    return new Response(body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  }

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
