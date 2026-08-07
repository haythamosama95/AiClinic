export type ConnectionConfig = {
  platformBaseUrl: string;
  operatorBearer: string;
  aat: string;
};

const STORAGE_KEY = "ai-platform-ops.connection";

export const DEFAULT_CONNECTION: ConnectionConfig = {
  platformBaseUrl: "http://127.0.0.1:8787",
  operatorBearer: "",
  aat: "",
};

export function loadConnection(): ConnectionConfig {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    if (!raw) return { ...DEFAULT_CONNECTION };
    const parsed = JSON.parse(raw) as Partial<ConnectionConfig>;
    return {
      platformBaseUrl:
        typeof parsed.platformBaseUrl === "string"
          ? parsed.platformBaseUrl
          : DEFAULT_CONNECTION.platformBaseUrl,
      operatorBearer:
        typeof parsed.operatorBearer === "string"
          ? parsed.operatorBearer
          : "",
      aat: typeof parsed.aat === "string" ? parsed.aat : "",
    };
  } catch {
    return { ...DEFAULT_CONNECTION };
  }
}

export function saveConnection(config: ConnectionConfig): void {
  sessionStorage.setItem(STORAGE_KEY, JSON.stringify(config));
}
