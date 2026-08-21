/**
 * Incremental UTF-8 / SSE body readers for provider transports.
 * Not a store, service, or queue — byte parsing only.
 */

export type ReadBodyResult =
  | { ok: true; text: string; bytesRead: number }
  | { ok: false; reason: "over_limit" | "aborted" };

export type SseReadResult = {
  overLimit: boolean;
  aborted: boolean;
  sawDone: boolean;
  bytesRead: number;
};

export function asReadableStream(
  body: string | ReadableStream<Uint8Array>,
): ReadableStream<Uint8Array> {
  if (typeof body !== "string") {
    return body;
  }
  const bytes = new TextEncoder().encode(body);
  return new ReadableStream<Uint8Array>({
    start(controller) {
      if (bytes.byteLength > 0) {
        controller.enqueue(bytes);
      }
      controller.close();
    },
  });
}

async function cancelQuietly(
  reader: ReadableStreamDefaultReader<Uint8Array>,
): Promise<void> {
  try {
    await reader.cancel();
  } catch {
    // Already closed or cancelled.
  }
}

/**
 * Read a provider body to a UTF-8 string, aborting if {@link byteLimit} is
 * exceeded. String bodies are returned without copying when under the limit.
 */
export async function readUtf8Body(
  body: string | ReadableStream<Uint8Array>,
  options: { byteLimit: number; signal?: AbortSignal },
): Promise<ReadBodyResult> {
  if (typeof body === "string") {
    const bytesRead = new TextEncoder().encode(body).byteLength;
    if (bytesRead > options.byteLimit) {
      return { ok: false, reason: "over_limit" };
    }
    if (options.signal?.aborted) {
      return { ok: false, reason: "aborted" };
    }
    return { ok: true, text: body, bytesRead };
  }

  const stream = asReadableStream(body);
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let text = "";
  let bytesRead = 0;

  const onAbort = (): void => {
    void cancelQuietly(reader);
  };
  options.signal?.addEventListener("abort", onAbort, { once: true });

  try {
    if (options.signal?.aborted) {
      await cancelQuietly(reader);
      return { ok: false, reason: "aborted" };
    }
    while (true) {
      const { done, value } = await reader.read();
      if (options.signal?.aborted) {
        return { ok: false, reason: "aborted" };
      }
      if (done) {
        text += decoder.decode();
        break;
      }
      bytesRead += value.byteLength;
      if (bytesRead > options.byteLimit) {
        await cancelQuietly(reader);
        return { ok: false, reason: "over_limit" };
      }
      text += decoder.decode(value, { stream: true });
    }
    return { ok: true, text, bytesRead };
  } catch {
    if (options.signal?.aborted) {
      return { ok: false, reason: "aborted" };
    }
    throw new Error("provider body read failed");
  } finally {
    options.signal?.removeEventListener("abort", onAbort);
    try {
      reader.releaseLock();
    } catch {
      // Lock already released by cancel.
    }
  }
}

/**
 * Feed complete SSE `data:` payloads as they arrive from a string or
 * ReadableStream body. `[DONE]` sets {@link SseReadResult.sawDone} and is
 * still delivered to {@link onPayload}.
 */
export async function readSseDataPayloads(
  body: string | ReadableStream<Uint8Array>,
  options: {
    byteLimit: number;
    signal?: AbortSignal;
    onPayload: (payload: string) => void | Promise<void>;
  },
): Promise<SseReadResult> {
  const stream = asReadableStream(body);
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let bytesRead = 0;
  let sawDone = false;

  const onAbort = (): void => {
    void cancelQuietly(reader);
  };
  options.signal?.addEventListener("abort", onAbort, { once: true });

  const flushLines = async (flushRemainder: boolean): Promise<void> => {
    const lines = buffer.split("\n");
    if (!flushRemainder) {
      buffer = lines.pop() ?? "";
    } else {
      buffer = "";
    }
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed.startsWith("data:")) {
        continue;
      }
      const payload = trimmed.slice("data:".length).trim();
      if (payload.length === 0) {
        continue;
      }
      if (payload === "[DONE]") {
        sawDone = true;
      }
      await options.onPayload(payload);
    }
  };

  try {
    if (options.signal?.aborted) {
      await cancelQuietly(reader);
      return { overLimit: false, aborted: true, sawDone, bytesRead };
    }
    while (true) {
      const { done, value } = await reader.read();
      if (options.signal?.aborted) {
        return { overLimit: false, aborted: true, sawDone, bytesRead };
      }
      if (done) {
        buffer += decoder.decode();
        await flushLines(true);
        break;
      }
      bytesRead += value.byteLength;
      if (bytesRead > options.byteLimit) {
        await cancelQuietly(reader);
        return { overLimit: true, aborted: false, sawDone, bytesRead };
      }
      buffer += decoder.decode(value, { stream: true });
      await flushLines(false);
    }
    return {
      overLimit: false,
      aborted: Boolean(options.signal?.aborted),
      sawDone,
      bytesRead,
    };
  } catch {
    if (options.signal?.aborted) {
      return { overLimit: false, aborted: true, sawDone, bytesRead };
    }
    throw new Error("provider SSE body read failed");
  } finally {
    options.signal?.removeEventListener("abort", onAbort);
    try {
      reader.releaseLock();
    } catch {
      // Lock already released by cancel.
    }
  }
}
