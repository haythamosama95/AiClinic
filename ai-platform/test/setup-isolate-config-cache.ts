import { beforeEach } from "vitest";
import { isolateConfigCache } from "../src/config-cache";

beforeEach(() => {
  isolateConfigCache.clear();
});
