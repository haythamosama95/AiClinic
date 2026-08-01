/**
 * Context validator — manifest-driven key presence, shape, size, and tenant checks (§5.2 / B2 C2).
 */

import {
  VISIT_CHIEF_COMPLAINT_V1,
  VISIT_CHIEF_COMPLAINT_V1_SHAPE,
  type KeyShape,
  validatePayload,
} from "./index";
import { buildErrorBody } from "../errors";
import type { Principal } from "../identity";
import type { Manifest } from "../manifest";

export type ValidateResult =
  | { ok: true; filteredContext: Record<string, unknown> }
  | {
      ok: false;
      code: "context_required";
      missingKeys: string[];
      shapes: Record<string, KeyShape>;
      manifestVersion: string;
      manifestCapabilityId: string;
    }
  | { ok: false; code: "context_invalid" };

const PUBLISHED_SHAPES: ReadonlyMap<string, KeyShape> = new Map([
  [VISIT_CHIEF_COMPLAINT_V1, VISIT_CHIEF_COMPLAINT_V1_SHAPE],
]);

function publishedShapeForKey(key: string): KeyShape | undefined {
  return PUBLISHED_SHAPES.get(key);
}

function jsonByteLength(value: unknown): number {
  return new TextEncoder().encode(JSON.stringify(value)).byteLength;
}

function buildShapesForMissingKeys(
  missingKeys: readonly string[],
): Record<string, KeyShape> {
  const shapes: Record<string, KeyShape> = {};
  for (const key of missingKeys) {
    const shape = publishedShapeForKey(key);
    if (shape !== undefined) {
      shapes[key] = shape;
    }
  }
  return shapes;
}

export function validateContext(
  manifest: Manifest,
  suppliedContext: Record<string, unknown>,
  principal: Principal,
): ValidateResult {
  const contextRequirements = manifest["Context requirements"];
  const maxSizeByKey = new Map<string, number>();

  for (const entry of contextRequirements) {
    maxSizeByKey.set(String(entry.key), Number(entry.maxSize));
  }

  const missingKeys: string[] = [];
  for (const entry of contextRequirements) {
    const key = String(entry.key);
    if (
      entry.required === true &&
      !Object.prototype.hasOwnProperty.call(suppliedContext, key)
    ) {
      missingKeys.push(key);
    }
  }

  if (missingKeys.length > 0) {
    return {
      ok: false,
      code: "context_required",
      missingKeys,
      shapes: buildShapesForMissingKeys(missingKeys),
      manifestVersion: String(manifest.Identity.version),
      manifestCapabilityId: String(manifest.Identity.capabilityId),
    };
  }

  if (
    suppliedContext.org !== principal.organizationId ||
    suppliedContext.branch !== principal.branchId
  ) {
    return { ok: false, code: "context_invalid" };
  }

  for (const entry of contextRequirements) {
    const key = String(entry.key);
    if (!Object.prototype.hasOwnProperty.call(suppliedContext, key)) {
      continue;
    }

    const value = suppliedContext[key];
    const payloadResult = validatePayload(key, value);
    if (!payloadResult.ok && payloadResult.code !== "unknown_shape") {
      return { ok: false, code: "context_invalid" };
    }

    const maxSize = maxSizeByKey.get(key);
    if (maxSize !== undefined && jsonByteLength(value) > maxSize) {
      return { ok: false, code: "context_invalid" };
    }
  }

  const filteredContext: Record<string, unknown> = {};
  for (const entry of contextRequirements) {
    const key = String(entry.key);
    if (Object.prototype.hasOwnProperty.call(suppliedContext, key)) {
      filteredContext[key] = suppliedContext[key];
    }
  }

  return { ok: true, filteredContext };
}

export function buildContextRequiredResponse(
  result: Extract<ValidateResult, { ok: false; code: "context_required" }>,
  requestReference: string,
  traceId: string,
): Record<string, unknown> {
  const body = buildErrorBody({
    code: "context_required",
    requestReference,
    traceId,
  });

  return {
    ...body,
    missing_keys: result.missingKeys,
    shapes: result.shapes,
    manifest_version: result.manifestVersion,
    manifest_capability_id: result.manifestCapabilityId,
  };
}
