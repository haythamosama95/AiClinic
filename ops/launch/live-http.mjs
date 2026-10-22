// R9-RT1 (01 §3.8 D-6): the only HTTP path used by the live launch-check and the audit watcher's
// read. Every request is a GET. A response that times out, is not accepted, is not JSON, or
// carries a Date header more than 60 seconds away from the local clock is a SourceError, and its
// caller discards everything it had observed from that source.

export const REQUEST_TIMEOUT_MS = 10_000;
export const MAX_CLOCK_SKEW_MS = 60_000;

export class SourceError extends Error {
  constructor(source, reason) {
    super(`${source}: ${reason}`);
    this.name = "SourceError";
    this.source = source;
    this.reason = reason;
  }
}

const isSuccess = (status) => status >= 200 && status < 300;

function isTimeout(error) {
  return error?.name === "TimeoutError" || error?.name === "AbortError";
}

function checkDate(header, receivedMs, source) {
  if (typeof header !== "string") {
    throw new SourceError(source, "no-date-header");
  }
  const serverMs = Date.parse(header);
  if (!Number.isFinite(serverMs)) {
    throw new SourceError(source, "bad-date-header");
  }
  if (Math.abs(serverMs - receivedMs) > MAX_CLOCK_SKEW_MS) {
    throw new SourceError(source, "clock-skew");
  }
}

// Returns { status, body, receivedMs }. body is null when expectJson is false.
export async function httpGet({
  source,
  fetchImpl,
  url,
  headers = {},
  clock,
  acceptStatus = isSuccess,
  expectJson = true,
}) {
  let response;
  try {
    response = await fetchImpl(url, {
      method: "GET",
      headers,
      redirect: "error",
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
  } catch (error) {
    throw new SourceError(source, isTimeout(error) ? "timeout" : "network-error");
  }
  const receivedMs = clock.now();

  if (!acceptStatus(response.status)) {
    throw new SourceError(source, `http-${response.status}`);
  }
  checkDate(response.headers.get("date"), receivedMs, source);
  if (!expectJson) {
    return { status: response.status, body: null, receivedMs };
  }

  let body;
  try {
    body = JSON.parse(await response.text());
  } catch (error) {
    throw new SourceError(source, isTimeout(error) ? "timeout" : "non-json");
  }
  return { status: response.status, body, receivedMs };
}

export function schemaError(source) {
  return new SourceError(source, "schema-mismatch");
}
