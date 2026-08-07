import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { tsImport } from "tsx/esm/api";
import type { ConnectionConfig, GapNotice, OpsRunResult } from "./types";
import {
  ALL_TAXONOMY_CODES,
  getTaxonomyEntry,
  isTaxonomyCode,
} from "./taxonomy-data";

const JSON_HEADERS = { "content-type": "application/json" };

/** Crockford base32 reference helpers — mirrored from ai-platform/src/reference.ts */
const REFERENCE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const REFERENCE_PATTERN = /^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/;

function generateRequestReference(): string {
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  return (
    REFERENCE_ALPHABET[bytes[0]! % 32]! +
    REFERENCE_ALPHABET[bytes[1]! % 32]! +
    REFERENCE_ALPHABET[bytes[2]! % 32]! +
    REFERENCE_ALPHABET[bytes[3]! % 32]! +
    "-" +
    REFERENCE_ALPHABET[bytes[4]! % 32]! +
    REFERENCE_ALPHABET[bytes[5]! % 32]! +
    REFERENCE_ALPHABET[bytes[6]! % 32]! +
    REFERENCE_ALPHABET[bytes[7]! % 32]!
  );
}

function normalizeRequestReference(input: string): string {
  return input
    .toUpperCase()
    .replace(/I/g, "1")
    .replace(/L/g, "1")
    .replace(/O/g, "0");
}

function isValidRequestReference(normalized: string): boolean {
  return REFERENCE_PATTERN.test(normalized);
}

function jsonResult(
  status: number,
  body: unknown,
  started: number,
): OpsRunResult {
  return {
    status,
    contentType: "application/json",
    bodyText: JSON.stringify(body, null, 2),
    headers: JSON_HEADERS,
    durationMs: Date.now() - started,
  };
}

function gapResult(
  reason: string,
  gap = "library-only until bindings / Worker mount",
  started = Date.now(),
): OpsRunResult {
  const body: GapNotice = { available: false, reason, gap };
  return jsonResult(501, body, started);
}

async function importPlatform<T>(
  repoRoot: string,
  modulePath: string,
): Promise<T> {
  const absolute = path.join(repoRoot, "ai-platform/src", modulePath);
  const href = pathToFileURL(absolute).href;
  return (await tsImport(href, import.meta.url)) as T;
}

function decodeAatPayload(token: string): Record<string, unknown> {
  const parts = token.split(".");
  if (parts.length < 2) {
    throw new Error("Invalid JWT structure");
  }
  const payload = parts[1];
  const padded = payload.replace(/-/g, "+").replace(/_/g, "/");
  const padLen = (4 - (padded.length % 4)) % 4;
  const normalized = padded + "=".repeat(padLen);
  const decoded = Buffer.from(normalized, "base64").toString("utf8");
  return JSON.parse(decoded) as Record<string, unknown>;
}

async function loadPublishedManifest(
  repoRoot: string,
  capabilityId: string,
  capabilityVersion: string,
): Promise<Record<string, unknown> | null> {
  const filePath = path.join(
    repoRoot,
    "ai-platform/manifests/published",
    `${capabilityId}@${capabilityVersion}.json`,
  );
  try {
    const raw = await fs.readFile(filePath, "utf8");
    return JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return null;
  }
}

async function loadAllPublishedManifests(
  repoRoot: string,
): Promise<Record<string, unknown>[]> {
  const manifestsDir = path.join(
    repoRoot,
    "ai-platform/manifests/published",
  );
  const names = await fs.readdir(manifestsDir);
  const out: Record<string, unknown>[] = [];
  for (const name of names.filter((entry) => entry.endsWith(".json"))) {
    const raw = await fs.readFile(path.join(manifestsDir, name), "utf8");
    out.push(JSON.parse(raw) as Record<string, unknown>);
  }
  return out;
}

function asString(value: unknown, field: string): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`Field "${field}" must be a non-empty string`);
  }
  return value.trim();
}

function asRecord(value: unknown, field: string): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`Field "${field}" must be a JSON object`);
  }
  return value as Record<string, unknown>;
}

export async function handleLocal(
  handler: string,
  input: Record<string, unknown>,
  repoRoot: string,
  connection: ConnectionConfig,
): Promise<OpsRunResult> {
  const started = Date.now();

  try {
    switch (handler) {
      case "decode-aat":
        return handleDecodeAat(input, connection, started);
      case "taxonomy":
        return handleTaxonomy(input, started);
      case "reference":
        return handleReference(input, repoRoot, started);
      case "discover":
        return await handleDiscover(input, repoRoot, started);
      case "compose":
        return await handleCompose(input, repoRoot, started);
      case "context-validate":
        return await handleContextValidate(input, repoRoot, started);
      case "route-dry-run":
        return await handleRouteDryRun(input, repoRoot, started);
      case "canonical-lint":
        return await handleCanonicalLint(input, repoRoot, started);
      default:
        return jsonResult(404, { error: `Unknown local handler: ${handler}` }, started);
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResult(400, { error: message }, started);
  }
}

function handleDecodeAat(
  input: Record<string, unknown>,
  connection: ConnectionConfig,
  started: number,
): OpsRunResult {
  const token =
    (typeof input.aat === "string" ? input.aat.trim() : "") ||
    connection.aat.trim();
  if (!token) {
    return jsonResult(400, { error: "Missing credential: aat" }, started);
  }

  const claims = decodeAatPayload(token);
  return jsonResult(200, { claims }, started);
}

function handleTaxonomy(
  input: Record<string, unknown>,
  started: number,
): OpsRunResult {
  const code =
    typeof input.code === "string" && input.code.trim()
      ? input.code.trim()
      : undefined;

  if (code === undefined) {
    return jsonResult(
      200,
      {
        codes: ALL_TAXONOMY_CODES,
        entries: ALL_TAXONOMY_CODES.map((entry) => getTaxonomyEntry(entry)),
      },
      started,
    );
  }

  if (!isTaxonomyCode(code)) {
    return jsonResult(404, { error: `Unknown taxonomy code: ${code}` }, started);
  }

  return jsonResult(200, getTaxonomyEntry(code), started);
}

function handleReference(
  input: Record<string, unknown>,
  _repoRoot: string,
  started: number,
): OpsRunResult {
  const action = asString(input.action, "action");

  if (action === "generate") {
    return jsonResult(200, { reference: generateRequestReference() }, started);
  }

  if (action === "normalize") {
    const raw = asString(input.reference, "reference");
    const normalized = normalizeRequestReference(raw);
    return jsonResult(
      200,
      {
        reference: raw,
        normalized,
        valid: isValidRequestReference(normalized),
      },
      started,
    );
  }

  return jsonResult(400, { error: `Unknown action: ${action}` }, started);
}

async function handleDiscover(
  input: Record<string, unknown>,
  repoRoot: string,
  started: number,
): Promise<OpsRunResult> {
  try {
    const capability = await importPlatform<{
      createCapabilityRegistry: (manifests: unknown[]) => unknown;
      discover: (
        principal: unknown,
        cache: unknown,
        reader: unknown,
      ) => Promise<{ manifests: unknown[]; etag: string }>;
      setCapabilityRegistry: (
        registry: unknown,
        options?: { replace?: boolean },
      ) => void;
    }>(repoRoot, "capability/index.ts");
    const manifestMod = await importPlatform<{
      load: (json: Record<string, unknown>) => unknown;
    }>(repoRoot, "manifest/index.ts");
    const { ConfigCache } = await importPlatform<{
      ConfigCache: new () => { consult: () => undefined };
    }>(repoRoot, "config-cache/index.ts");

    const installationId = asString(input.installation_id, "installation_id");
    const orgId = asString(input.org_id, "org_id");
    const branchId = asString(input.branch_id, "branch_id");
    const actorId = asString(input.actor_id, "actor_id");
    const role = asString(input.role, "role");
    const scopes = Array.isArray(input.scopes)
      ? input.scopes.filter((entry): entry is string => typeof entry === "string")
      : [];

    const rawManifests = await loadAllPublishedManifests(repoRoot);
    const manifests = rawManifests.map((json) => manifestMod.load(json));
    capability.setCapabilityRegistry(
      capability.createCapabilityRegistry(manifests),
      { replace: true },
    );

    const allowedCapabilities = manifests
      .map((manifest) => {
        const identity = (manifest as { Identity?: { capabilityId?: string } })
          .Identity;
        return identity?.capabilityId;
      })
      .filter((id): id is string => typeof id === "string");

    const reader = {
      async read(key: string) {
        if (key === installationId) {
          return {
            status: "active",
            plan: "enterprise",
            allowed_capabilities: JSON.stringify(allowedCapabilities),
          };
        }

        for (const manifest of manifests) {
          const identity = (manifest as {
            Identity?: { capabilityId?: string; version?: string };
          }).Identity;
          const capabilityId = identity?.capabilityId;
          const version = identity?.version;
          if (
            typeof capabilityId === "string" &&
            key === `${installationId}/${capabilityId}`
          ) {
            return {
              capability_version:
                typeof version === "string" ? version : "1.0.0",
            };
          }
        }

        if (key.startsWith(`global/`)) {
          return "miss";
        }

        return "miss";
      },
    };

    const principal = {
      installationId,
      organizationId: orgId,
      branchId,
      actorId,
      role,
      scopes,
      jti: "ops-discover",
      iat: 0,
      exp: Math.floor(Date.now() / 1000) + 3600,
      ver: "1",
    };

    const cache = new ConfigCache();
    const result = await capability.discover(principal, cache, reader);
    return jsonResult(200, result, started);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return gapResult(`discover unavailable: ${message}`, undefined, started);
  }
}

async function handleCompose(
  _input: Record<string, unknown>,
  repoRoot: string,
  started: number,
): Promise<OpsRunResult> {
  try {
    await importPlatform(repoRoot, "prompt/composer.ts");
    return gapResult(
      "compose module loaded but prompt artifact registry requires import.meta.glob (Vite/Worker build)",
      "library-only until bindings / Worker mount",
      started,
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return gapResult(`compose unavailable: ${message}`, undefined, started);
  }
}

async function handleContextValidate(
  input: Record<string, unknown>,
  repoRoot: string,
  started: number,
): Promise<OpsRunResult> {
  const capabilityId = asString(input.capability_id, "capability_id");
  const capabilityVersion = asString(
    input.capability_version,
    "capability_version",
  );
  const context = asRecord(input.context, "context");
  const key =
    typeof input.key === "string" && input.key.trim()
      ? input.key.trim()
      : undefined;

  try {
    const manifestJson = await loadPublishedManifest(
      repoRoot,
      capabilityId,
      capabilityVersion,
    );
    if (manifestJson === null) {
      return jsonResult(
        404,
        {
          error: `Published manifest not found: ${capabilityId}@${capabilityVersion}`,
        },
        started,
      );
    }

    const manifestMod = await importPlatform<{
      load: (json: Record<string, unknown>) => unknown;
    }>(repoRoot, "manifest/index.ts");
    const validatorMod = await importPlatform<{
      validateContext: (
        manifest: unknown,
        suppliedContext: Record<string, unknown>,
        principal: unknown,
      ) => unknown;
    }>(repoRoot, "context/validator.ts");

    const manifest = manifestMod.load(manifestJson);
    const org =
      typeof context.org === "string" ? context.org : "ops-org-placeholder";
    const branch =
      typeof context.branch === "string"
        ? context.branch
        : "ops-branch-placeholder";

    const principal = {
      installationId: "ops-validate",
      organizationId: org,
      branchId: branch,
      actorId: "ops-validate",
      role: "clinician",
      scopes: [],
      jti: "ops-validate",
      iat: 0,
      exp: Math.floor(Date.now() / 1000) + 3600,
      ver: "1",
    };

    const response: Record<string, unknown> = {
      validateContext: validatorMod.validateContext(manifest, context, principal),
    };

    if (key !== undefined) {
      const contextIndex = await importPlatform<{
        validateKey: (key: string) => unknown;
      }>(repoRoot, "context/index.ts");
      response.validateKey = contextIndex.validateKey(key);
    }

    return jsonResult(200, response, started);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return gapResult(
      `context-validate unavailable: ${message}`,
      undefined,
      started,
    );
  }
}

async function handleRouteDryRun(
  input: Record<string, unknown>,
  repoRoot: string,
  started: number,
): Promise<OpsRunResult> {
  const policyDocument = asRecord(input.policy_document, "policy_document");
  const capabilityId = asString(input.capability_id, "capability_id");
  const installationId = asString(input.installation_id, "installation_id");
  const costClass = (
    typeof input.cost_class === "string" && input.cost_class.trim()
      ? input.cost_class.trim()
      : "standard"
  ) as "economy" | "standard" | "premium";
  const tier = (
    typeof input.tier === "string" && input.tier.trim()
      ? input.tier.trim()
      : "standard"
  ) as "standard" | "degraded";
  const language =
    typeof input.language === "string" && input.language.trim()
      ? input.language.trim()
      : "en";
  const latencyClass =
    typeof input.latency_class === "string" && input.latency_class.trim()
      ? input.latency_class.trim()
      : "standard";

  try {
    const routerMod = await importPlatform<{
      selectCandidateChain: (args: unknown) => unknown;
      RoutingPolicyError: new (code: string, message: string) => Error;
    }>(repoRoot, "router/index.ts");
    const { ConfigCache } = await importPlatform<{
      ConfigCache: new () => {
        remember: (
          kind: string,
          key: string,
          value: Record<string, unknown>,
        ) => void;
      };
    }>(repoRoot, "config-cache/index.ts");

    const policyId =
      typeof policyDocument.policy_id === "string"
        ? policyDocument.policy_id
        : "ops-policy";
    const policyVersion =
      typeof policyDocument.policy_version === "number"
        ? policyDocument.policy_version
        : 1;
    const policyCacheKey = `routing/${policyId}@v${policyVersion}`;

    const cache = new ConfigCache();
    cache.remember("active_routing_policy", policyCacheKey, {
      policy_id: policyId,
      policy_version: policyVersion,
      document: policyDocument,
    });

    const outcome = routerMod.selectCandidateChain({
      cache,
      policyCacheKey,
      context: {
        installationId,
        capabilityId,
        routingTier: tier,
        requirements: {
          structured_output_required: false,
          min_context_window: 0,
          languages: [language],
          latency_class: latencyClass,
        },
        manifestCostClass: costClass,
        entitlementMaxCostClass: "premium",
      },
    });

    return jsonResult(200, outcome, started);
  } catch (error) {
    if (
      error instanceof Error &&
      error.name === "RoutingPolicyError"
    ) {
      return jsonResult(
        422,
        { error: error.message, code: (error as { code?: string }).code },
        started,
      );
    }
    const message = error instanceof Error ? error.message : String(error);
    return gapResult(`route-dry-run unavailable: ${message}`, undefined, started);
  }
}

async function handleCanonicalLint(
  input: Record<string, unknown>,
  repoRoot: string,
  started: number,
): Promise<OpsRunResult> {
  const request = asRecord(input.request, "request");

  try {
    const canonical = await importPlatform<{
      assertNoProviderShapedFieldNames: (keys: readonly string[]) => void;
      encodeCanonicalRequest: (value: unknown) => string;
    }>(repoRoot, "contracts/canonical.ts");

    const keys = Object.keys(request);
    const violations: string[] = [];

    try {
      canonical.assertNoProviderShapedFieldNames(keys);
    } catch (error) {
      violations.push(error instanceof Error ? error.message : String(error));
    }

    let encoded: string | undefined;
    let encodeError: string | undefined;
    try {
      encoded = canonical.encodeCanonicalRequest(request);
    } catch (error) {
      encodeError = error instanceof Error ? error.message : String(error);
    }

    return jsonResult(
      200,
      {
        keys,
        providerFieldViolations: violations,
        encoded,
        encodeError,
      },
      started,
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return gapResult(`canonical-lint unavailable: ${message}`, undefined, started);
  }
}
