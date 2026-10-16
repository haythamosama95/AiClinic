/**
 * Human-readable operational logger for the AI platform worker.
 *
 * Verbosity tiers:
 * - V0: errors only
 * - V1: errors + operational info
 * - V2: errors + info + debug detail
 *
 * Output format:
 *   [hh:mm:ss] [file.ts] [Status] message [optional data]
 *
 * Configure via LOG_VERBOSITY env var: 0/V0, 1/V1, or 2/V2.
 */

/** Operational log verbosity: V0 = errors only, V1 = +info, V2 = +debug. */
export type LogVerbosity = 0 | 1 | 2;

export type LogStatus = "Error" | "Info" | "Debug";

export type LogData = Record<string, unknown>;

export interface Logger {
  error(message: string, data?: LogData): void;
  info(message: string, data?: LogData): void;
  debug(message: string, data?: LogData): void;
  /** Returns a logger with merged default data (e.g. trace_id). */
  child(data: LogData): Logger;
}

export type LoggerFactory = (file: string, context?: LogData) => Logger;

const noopEmit = (): void => {};

/** Silent logger for optional makeLog fallbacks and tests. */
export const noopLogger: Logger = {
  error: noopEmit,
  info: noopEmit,
  debug: noopEmit,
  child: () => noopLogger,
};

export interface CreateLoggerOptions {
  /** Source file label, e.g. "worker.ts". Required — Workers cannot resolve this reliably at runtime. */
  file: string;
  verbosity?: LogVerbosity;
  /** Merged into every log line's data payload. */
  context?: LogData;
  /** Inject for tests; defaults to console.log / console.error. */
  sink?: LogSink;
}

export interface LogSink {
  write(line: string, status: LogStatus): void;
}

export interface LoggerFactoryConfig {
  verbosity: LogVerbosity;
  context?: LogData;
  sink?: LogSink;
}

const STATUS_METHOD: Record<LogStatus, "log" | "error"> = {
  Error: "error",
  Info: "log",
  Debug: "log",
};

/** Minimum verbosity required to emit each status. Errors always pass at V0. */
const STATUS_MIN_VERBOSITY: Record<LogStatus, LogVerbosity> = {
  Error: 0,
  Info: 1,
  Debug: 2,
};

export function resolveLogVerbosity(
  raw: string | undefined | null,
  fallback: LogVerbosity = 0,
): LogVerbosity {
  if (raw == null || raw.trim() === "") {
    return fallback;
  }
  const normalized = raw.trim().toUpperCase();
  if (normalized === "0" || normalized === "V0") {
    return 0;
  }
  if (normalized === "1" || normalized === "V1") {
    return 1;
  }
  if (normalized === "2" || normalized === "V2") {
    return 2;
  }
  return fallback;
}

/** Map Worker env to verbosity; development defaults to V2, else V0. */
export function verbosityFromEnv(env: {
  LOG_VERBOSITY?: string;
  ENVIRONMENT?: string;
}): LogVerbosity {
  if (env.LOG_VERBOSITY != null && env.LOG_VERBOSITY !== "") {
    return resolveLogVerbosity(env.LOG_VERBOSITY, 0);
  }
  return env.ENVIRONMENT === "development" ? 2 : 0;
}

function defaultSink(): LogSink {
  return {
    write(line: string, status: LogStatus): void {
      const method = STATUS_METHOD[status];
      console[method](line);
    },
  };
}

function formatTime(date: Date): string {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}:${pad(date.getUTCSeconds())}`;
}

function formatScalar(value: unknown): string {
  if (value === null) {
    return "null";
  }
  if (value === undefined) {
    return "undefined";
  }
  if (typeof value === "string") {
    return value;
  }
  if (
    typeof value === "number" ||
    typeof value === "boolean" ||
    typeof value === "bigint"
  ) {
    return String(value);
  }
  if (value instanceof Error) {
    return `${value.name}: ${value.message}`;
  }
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

/** V1: flat key=value; V2: JSON blob for richer nested data. */
function formatData(
  data: LogData | undefined,
  verbosity: LogVerbosity,
): string {
  if (!data || Object.keys(data).length === 0) {
    return "";
  }

  if (verbosity >= 2) {
    try {
      return ` ${JSON.stringify(data)}`;
    } catch {
      return ` ${String(data)}`;
    }
  }

  const pairs = Object.entries(data).map(
    ([key, value]) => `${key}=${formatScalar(value)}`,
  );
  return ` ${pairs.join(" ")}`;
}

export function formatLogLine(
  file: string,
  status: LogStatus,
  message: string,
  data: LogData | undefined,
  verbosity: LogVerbosity,
  now: () => Date = () => new Date(),
): string {
  const time = formatTime(now());
  const payload = formatData(data, verbosity);
  return `[${time}] [${file}] [${status}] ${message}${payload}`;
}

function mergeData(
  base: LogData | undefined,
  extra: LogData | undefined,
): LogData | undefined {
  if (!base && !extra) {
    return undefined;
  }
  if (!base) {
    return extra;
  }
  if (!extra) {
    return base;
  }
  return { ...base, ...extra };
}

function createLoggerInternal(
  file: string,
  verbosity: LogVerbosity,
  context: LogData | undefined,
  sink: LogSink,
): Logger {
  const emit = (status: LogStatus, message: string, data?: LogData): void => {
    if (verbosity < STATUS_MIN_VERBOSITY[status]) {
      return;
    }
    const merged = mergeData(context, data);
    const line = formatLogLine(file, status, message, merged, verbosity);
    sink.write(line, status);
  };

  const logger: Logger = {
    error: (message, data) => emit("Error", message, data),
    info: (message, data) => emit("Info", message, data),
    debug: (message, data) => emit("Debug", message, data),
    child: (childData) =>
      createLoggerInternal(
        file,
        verbosity,
        mergeData(context, childData),
        sink,
      ),
  };

  return logger;
}

export function createLogger(options: CreateLoggerOptions): Logger {
  return createLoggerInternal(
    options.file,
    options.verbosity ?? 0,
    options.context,
    options.sink ?? defaultSink(),
  );
}

/** Bind env verbosity once; call the returned function per module file. */
export function createLoggerFactory(
  config: LoggerFactoryConfig,
): (file: string, context?: LogData) => Logger {
  const sink = config.sink ?? defaultSink();
  return (file: string, context?: LogData) =>
    createLoggerInternal(
      file,
      config.verbosity,
      mergeData(config.context, context),
      sink,
    );
}
