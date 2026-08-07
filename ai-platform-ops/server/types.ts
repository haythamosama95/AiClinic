import type { BuiltRequest } from "../src/catalog/types";

export type OpsRunResult = {
  status: number;
  contentType: string;
  bodyText: string;
  headers: Record<string, string>;
  durationMs: number;
};

export type ConnectionConfig = {
  platformBaseUrl: string;
  operatorBearer: string;
  aat: string;
};

export type OpsRunBody = {
  request: BuiltRequest;
  connection: ConnectionConfig;
};

export type GapNotice = {
  available: false;
  reason: string;
  gap: string;
};
