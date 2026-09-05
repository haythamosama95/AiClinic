import {
  newId,
  nowIso,
  ok,
  parseJsonBody,
  reject,
  requireOperator,
} from "./http";
import type {
  CohortPayload,
  ControlBindings,
  OperatorAuth,
  PublishPayload,
  RoutingPolicyRoute,
} from "./types";
import visitSummaryPublished from "../../manifests/published/clinic.visit_summary@1.0.0.json";

type RoutingPolicyRow = {
  policy_id: string;
  version: string;
  status: string;
  canary_installation_ids: string | null;
  active_from: string;
};

type PublishedCapabilityManifest = {
  Routing?: {
    routingPolicyRef?: unknown;
    latencyClass?: unknown;
  };
};

const PUBLISHED_CAPABILITY_MANIFESTS: readonly PublishedCapabilityManifest[] = [
  visitSummaryPublished,
];

function parseRoutingPolicyRef(ref: unknown): { policyId: string } | null {
  if (typeof ref !== "string") {
    return null;
  }
  const match = /^routing\/([^/]+)(?:@v\d+)?$/.exec(ref);
  if (!match) {
    return null;
  }
  return { policyId: match[1] };
}

function collectTargetLatencyClasses(
  document: Record<string, unknown>,
): Set<string> {
  const classes = new Set<string>();
  if (!Array.isArray(document.rules)) {
    return classes;
  }
  for (const rule of document.rules) {
    if (rule === null || typeof rule !== "object" || Array.isArray(rule)) {
      continue;
    }
    const targets = (rule as { targets?: unknown }).targets;
    if (!Array.isArray(targets)) {
      continue;
    }
    for (const target of targets) {
      if (target === null || typeof target !== "object" || Array.isArray(target)) {
        continue;
      }
      const features = (target as { features?: unknown }).features;
      if (
        features === null ||
        typeof features !== "object" ||
        Array.isArray(features)
      ) {
        continue;
      }
      const latencyClass = (features as { latency_class?: unknown }).latency_class;
      if (typeof latencyClass === "string") {
        classes.add(latencyClass);
      }
    }
  }
  return classes;
}

function isUniqueConstraint(err: unknown): boolean {
  const message = err instanceof Error ? err.message : String(err);
  return /UNIQUE constraint failed|SQLITE_CONSTRAINT/i.test(message);
}

function latencyMismatchWarnings(
  document: Record<string, unknown>,
  policyId: string,
): string[] {
  const referenced = PUBLISHED_CAPABILITY_MANIFESTS.filter((manifest) => {
    const parsed = parseRoutingPolicyRef(manifest.Routing?.routingPolicyRef);
    return parsed !== null && parsed.policyId === policyId;
  });
  if (referenced.length === 0) {
    return ["unreferenced_policy"];
  }

  const targetClasses = collectTargetLatencyClasses(document);
  for (const manifest of referenced) {
    const latencyClass = manifest.Routing?.latencyClass;
    if (typeof latencyClass !== "string" || latencyClass.length === 0) {
      continue;
    }
    if (!targetClasses.has(latencyClass)) {
      return ["latency_class_mismatch"];
    }
  }
  return [];
}

async function assertInstallationsExist(
  db: D1Database,
  ids: string[],
): Promise<Response | null> {
  for (const id of ids) {
    const row = await db
      .prepare(
        `SELECT installation_id FROM installation WHERE installation_id = ?`,
      )
      .bind(id)
      .first<{ installation_id: string }>();
    if (!row) {
      return reject(404, "installation_not_found");
    }
  }
  return null;
}

export function parseRoutingPolicyRoute(
  request: Request,
): RoutingPolicyRoute | null {
  const pathname = new URL(request.url).pathname;
  if (pathname === "/control/routing-policies/publish") {
    return { action: "publish" };
  }
  const match = pathname.match(
    /^\/control\/routing-policies\/([^/]+)\/versions\/([^/]+)\/(canary|promote|rollback)$/,
  );
  if (!match) {
    return null;
  }
  return {
    policyId: match[1],
    version: match[2],
    action: match[3] as "canary" | "promote" | "rollback",
  };
}

export async function handleRoutingPolicyPublish(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseRoutingPolicyRoute(request);
  if (!route || route.action !== "publish") {
    return reject(400, "invalid_route");
  }

  if (!bindings.R2) {
    return reject(500, "missing_r2_binding");
  }

  const body = await parseJsonBody<PublishPayload>(request);
  if (body instanceof Response) {
    return body;
  }

  if (!body.document || typeof body.document !== "object") {
    return reject(400, "missing_document");
  }

  const document = body.document as Record<string, unknown>;
  const policyId = document.policy_id;
  const policyVersion = document.policy_version;
  if (
    typeof policyId !== "string" ||
    policyId.length === 0 ||
    typeof policyVersion !== "number" ||
    !Number.isInteger(policyVersion) ||
    policyVersion < 1
  ) {
    return reject(400, "invalid_policy_identity");
  }
  const version = String(policyVersion);

  const { DB, R2 } = bindings;
  const recordedAt = nowIso();
  const contentPointer = `control/routing-policy/${policyId}/${version}.json`;
  const target = `${policyId}@${version}`;

  const alreadyPublished = await DB.prepare(
    `SELECT policy_id FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(policyId, version)
    .first();
  if (alreadyPublished) {
    return reject(409, "already_published");
  }

  await R2.put(contentPointer, JSON.stringify(document), {
    httpMetadata: { contentType: "application/json" },
  });

  try {
    await DB.batch([
      DB.prepare(
        `INSERT INTO routing_policy (
           policy_id, version, content_pointer, active_from, activated_by,
           canary_installation_ids, status
         ) VALUES (?, ?, ?, ?, ?, NULL, 'published')`,
      ).bind(
        policyId,
        version,
        contentPointer,
        recordedAt,
        auth.operatorId,
      ),
      DB.prepare(
        `INSERT INTO control_audit
           (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
         VALUES (?, ?, 'routing_policy_publish', ?, NULL, ?, ?)`,
      ).bind(newId(), auth.operatorId, target, contentPointer, recordedAt),
    ]);
  } catch (err) {
    if (isUniqueConstraint(err)) {
      return reject(409, "already_published");
    }
    return reject(500, "storage_error");
  }

  const warnings = latencyMismatchWarnings(document, policyId);
  return warnings.length > 0 ? ok({ warnings }) : ok();
}

export async function handleRoutingPolicyCanary(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseRoutingPolicyRoute(request);
  if (!route || route.action !== "canary") {
    return reject(400, "invalid_route");
  }

  const body = await parseJsonBody<CohortPayload>(request);
  if (body instanceof Response) {
    return body;
  }

  if (!Array.isArray(body.installation_ids) || body.installation_ids.length === 0) {
    return reject(400, "missing_installation_ids");
  }

  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = `${route.policyId}@${route.version}`;

  const existing = await DB.prepare(
    `SELECT policy_id, version, status, canary_installation_ids, active_from
     FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(route.policyId, route.version)
    .first<RoutingPolicyRow>();

  if (!existing) {
    return reject(404, "policy_version_not_found");
  }

  if (existing.status !== "published" && existing.status !== "canary") {
    return reject(409, "illegal_policy_transition");
  }

  const missingInstallations = await assertInstallationsExist(
    DB,
    body.installation_ids,
  );
  if (missingInstallations) {
    return missingInstallations;
  }

  const priorCanary = await DB.prepare(
    `SELECT canary_installation_ids FROM routing_policy
     WHERE policy_id = ? AND status = 'canary'
     ORDER BY active_from DESC, rowid DESC LIMIT 1`,
  )
    .bind(route.policyId)
    .first<{ canary_installation_ids: string | null }>();

  const beforePointer = priorCanary?.canary_installation_ids ?? null;
  const afterPointer = JSON.stringify(body.installation_ids);

  await DB.batch([
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'canary', canary_installation_ids = ?
       WHERE policy_id = ? AND version = ?`,
    ).bind(afterPointer, route.policyId, route.version),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'routing_policy_canary', ?, ?, ?, ?)`,
    ).bind(
      newId(),
      auth.operatorId,
      target,
      beforePointer,
      afterPointer,
      recordedAt,
    ),
  ]);

  return ok();
}

export async function handleRoutingPolicyPromote(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseRoutingPolicyRoute(request);
  if (!route || route.action !== "promote") {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = `${route.policyId}@${route.version}`;

  const existing = await DB.prepare(
    `SELECT policy_id, version, status, canary_installation_ids, active_from
     FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(route.policyId, route.version)
    .first<RoutingPolicyRow>();

  if (!existing) {
    return reject(404, "policy_version_not_found");
  }

  const priorActive = await DB.prepare(
    `SELECT version FROM routing_policy
     WHERE policy_id = ? AND status = 'active'
     ORDER BY active_from DESC, rowid DESC LIMIT 1`,
  )
    .bind(route.policyId)
    .first<{ version: string }>();

  const beforePointer = priorActive
    ? `${route.policyId}@${priorActive.version}`
    : null;
  const afterPointer = target;

  await DB.batch([
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'superseded', canary_installation_ids = NULL
       WHERE policy_id = ? AND status = 'active' AND version != ?`,
    ).bind(route.policyId, route.version),
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'superseded', canary_installation_ids = NULL
       WHERE policy_id = ? AND status = 'canary' AND version != ?`,
    ).bind(route.policyId, route.version),
    DB.prepare(
      `UPDATE routing_policy
       SET status = 'active', canary_installation_ids = NULL
       WHERE policy_id = ? AND version = ?`,
    ).bind(route.policyId, route.version),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'routing_policy_promote', ?, ?, ?, ?)`,
    ).bind(
      newId(),
      auth.operatorId,
      target,
      beforePointer,
      afterPointer,
      recordedAt,
    ),
  ]);

  return ok();
}

export async function handleRoutingPolicyRollback(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const route = parseRoutingPolicyRoute(request);
  if (!route || route.action !== "rollback") {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const recordedAt = nowIso();
  const target = `${route.policyId}@${route.version}`;

  const existing = await DB.prepare(
    `SELECT policy_id, version, status, canary_installation_ids, active_from
     FROM routing_policy WHERE policy_id = ? AND version = ?`,
  )
    .bind(route.policyId, route.version)
    .first<RoutingPolicyRow>();

  if (!existing) {
    return reject(404, "policy_version_not_found");
  }

  const statements: D1PreparedStatement[] = [];
  let beforePointer: string | null = `${route.policyId}@${route.version}`;
  let afterPointer: string | null = null;

  if (existing.status === "canary") {
    const active = await DB.prepare(
      `SELECT version FROM routing_policy
       WHERE policy_id = ? AND status = 'active'
       ORDER BY active_from DESC, rowid DESC LIMIT 1`,
    )
      .bind(route.policyId)
      .first<{ version: string }>();

    statements.push(
      DB.prepare(
        `UPDATE routing_policy
         SET status = 'published', canary_installation_ids = NULL
         WHERE policy_id = ? AND version = ?`,
      ).bind(route.policyId, route.version),
    );
    afterPointer = active
      ? `${route.policyId}@${active.version}`
      : null;
  } else if (existing.status === "active") {
    const prior = await DB.prepare(
      `SELECT version FROM routing_policy
       WHERE policy_id = ? AND status = 'superseded'
       ORDER BY active_from DESC, rowid DESC LIMIT 1`,
    )
      .bind(route.policyId)
      .first<{ version: string }>();

    if (!prior) {
      return reject(409, "illegal_policy_transition");
    }

    statements.push(
      DB.prepare(
        `UPDATE routing_policy
         SET status = 'superseded', canary_installation_ids = NULL
         WHERE policy_id = ? AND version = ?`,
      ).bind(route.policyId, route.version),
    );
    statements.push(
      DB.prepare(
        `UPDATE routing_policy
         SET status = 'active', canary_installation_ids = NULL
         WHERE policy_id = ? AND version = ?`,
      ).bind(route.policyId, prior.version),
    );
    afterPointer = `${route.policyId}@${prior.version}`;
  } else {
    // published (or other): succeed, clear any canary split on this policy
    beforePointer = existing.canary_installation_ids
      ? `${route.policyId}@${route.version}`
      : null;
    const active = await DB.prepare(
      `SELECT version FROM routing_policy
       WHERE policy_id = ? AND status = 'active'
       ORDER BY active_from DESC, rowid DESC LIMIT 1`,
    )
      .bind(route.policyId)
      .first<{ version: string }>();
    afterPointer = active
      ? `${route.policyId}@${active.version}`
      : null;
  }

  // Always clear canary split on this policy_id.
  statements.push(
    DB.prepare(
      `UPDATE routing_policy
       SET status = CASE WHEN status = 'canary' THEN 'published' ELSE status END,
           canary_installation_ids = NULL
       WHERE policy_id = ? AND (status = 'canary' OR canary_installation_ids IS NOT NULL)`,
    ).bind(route.policyId),
  );

  statements.push(
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'routing_policy_rollback', ?, ?, ?, ?)`,
    ).bind(
      newId(),
      auth.operatorId,
      target,
      beforePointer,
      afterPointer,
      recordedAt,
    ),
  );

  await DB.batch(statements);
  return ok();
}
