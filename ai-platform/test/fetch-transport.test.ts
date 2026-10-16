import { describe, expect, it } from "vitest";
import { createFetchTransport } from "../src/provider/fetch-transport";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const WORKER_PATH = path.join(ROOT, "src", "worker.ts");

describe("createFetchTransport", () => {
  it("passes Response.body through as a ReadableStream without buffering via text()", async () => {
    const encoder = new TextEncoder();
    let textCalled = false;
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(encoder.encode("data: {\"delta\":\"x\"}\n\n"));
        controller.close();
      },
    });
    const fakeFetch = async (): Promise<Response> => {
      const response = new Response(stream, {
        status: 200,
        headers: { "content-type": "text/event-stream" },
      });
      const originalText = response.text.bind(response);
      response.text = async () => {
        textCalled = true;
        return originalText();
      };
      return response;
    };

    const transport = createFetchTransport(fakeFetch);
    const result = await transport.fetch("https://example.invalid/v1", {
      url: "https://example.invalid/v1",
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    });

    expect(result.status).toBe(200);
    expect(result.headers["content-type"]).toBe("text/event-stream");
    expect(result.body).toBeInstanceOf(ReadableStream);
    expect(typeof result.body).not.toBe("string");
    expect(textCalled).toBe(false);
  });
});

describe("production fetch transport wiring", () => {
  it("wires createFetchTransport into provider adapters, not fetch-as-never", () => {
    const source = fs.readFileSync(WORKER_PATH, "utf8");
    expect(source).toMatch(/createFetchTransport\s*\(/);
    expect(source).not.toMatch(/transport:\s*fetch\s+as\s+never/);
  });
});
