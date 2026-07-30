const ENCODING = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

function encodeTime(timestamp: number, length: number): string {
  let value = timestamp;
  let result = "";
  for (let index = 0; index < length; index += 1) {
    result = ENCODING[value % 32] + result;
    value = Math.floor(value / 32);
  }
  return result;
}

function encodeRandom(length: number): string {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => ENCODING[byte % 32]).join("");
}

export function generateUlid(): string {
  return encodeTime(Date.now(), 10) + encodeRandom(16);
}

export function resolveTraceId(supplied: string | null | undefined): string {
  if (supplied) {
    return supplied;
  }
  return generateUlid();
}

export interface StructuredLoggerContext {
  traceId: string;
  requestReference: string;
  installation: string;
  capability: string;
  promptVersion: string;
}

export interface StructuredLogLine {
  trace_id: string;
  request_reference: string;
  installation: string;
  capability: string;
  prompt_version: string;
  level: string;
  message: string;
  [key: string]: unknown;
}

export interface StructuredLogger {
  info(message: string, extra?: Record<string, unknown>): void;
  error(message: string, extra?: Record<string, unknown>): void;
}

export function createStructuredLogger(
  context: StructuredLoggerContext,
): { logs: StructuredLogLine[]; logger: StructuredLogger } {
  const logs: StructuredLogLine[] = [];

  const baseFields = (): Omit<StructuredLogLine, "level" | "message"> => ({
    trace_id: context.traceId,
    request_reference: context.requestReference,
    installation: context.installation,
    capability: context.capability,
    prompt_version: context.promptVersion,
  });

  const emit = (
    level: string,
    message: string,
    extra?: Record<string, unknown>,
  ): void => {
    const line: StructuredLogLine = {
      ...baseFields(),
      level,
      message,
      ...extra,
    };
    logs.push(line);
    console.log(JSON.stringify(line));
  };

  const logger: StructuredLogger = {
    info: (message, extra) => emit("info", message, extra),
    error: (message, extra) => emit("error", message, extra),
  };

  return { logs, logger };
}
