/**
 * Production HTTP transport: pass through `Response.body` as a ReadableStream
 * so adapters can parse SSE incrementally. Does not buffer via `.text()`.
 */

export type FetchLike = (
  input: string,
  init?: RequestInit,
) => Promise<Response>;

export type FetchTransportRequest = {
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: string;
  signal?: AbortSignal;
};

export type FetchTransportResponse = {
  status: number;
  headers: Record<string, string>;
  body: string | ReadableStream<Uint8Array>;
};

export type FetchTransport = {
  fetch(
    url: string,
    init: FetchTransportRequest,
  ): Promise<FetchTransportResponse>;
};

export function createFetchTransport(
  fetchImpl: FetchLike = globalThis.fetch.bind(globalThis),
): FetchTransport {
  return {
    async fetch(
      url: string,
      init: FetchTransportRequest,
    ): Promise<FetchTransportResponse> {
      const response = await fetchImpl(url, {
        method: init.method,
        headers: init.headers,
        body: init.body,
        signal: init.signal,
      });
      const headers: Record<string, string> = {};
      response.headers.forEach((value, key) => {
        headers[key] = value;
      });
      return {
        status: response.status,
        headers,
        body: response.body ?? "",
      };
    },
  };
}
