export type OperatorPrincipal = {
  operatorId: string;
};

/** Port seam resolving an operator principal or rejecting (Clarification Q2). */
export type OperatorAuth = {
  resolve(request: Request): OperatorPrincipal | null;
};

/** Default bearer-token operator auth for the Worker route (real scheme is out of scope). */
export const defaultOperatorAuth: OperatorAuth = {
  resolve(request: Request) {
    const authorization = request.headers.get("authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return null;
    }
    const token = authorization.slice("Bearer ".length).trim();
    if (!token) {
      return null;
    }
    return { operatorId: token };
  },
};

type ControlBindings = {
  DB: D1Database;
};

type EnrollPayload = {
  org_id: string;
  display_name: string;
  region: string;
  plan: string;
  public_key: string;
  algorithm: string;
  kid: string;
};

type RotatePayload = {
  kid: string;
  public_key: string;
  algorithm: string;
};

const INSTALLATION_ACTIVE_STATUS = "active";
const INSTALLATION_SUSPENDED_STATUS = "suspended";
const INSTALLATION_DELETED_STATUS = "deleted";

function unauthorized(): Response {
  return new Response(JSON.stringify({ error: "unauthorized" }), {
    status: 401,
    headers: { "content-type": "application/json" },
  });
}

function reject(status: number, error: string): Response {
  return new Response(JSON.stringify({ error }), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function ok(body: Record<string, unknown> = {}): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

function nowIso(): string {
  return new Date().toISOString();
}

function newId(): string {
  return crypto.randomUUID();
}

function parseInstallationId(request: Request): string | null {
  const match = new URL(request.url).pathname.match(
    /^\/control\/installations\/([^/]+)\/(?:enroll|rotate|suspend|resume|delete)$/,
  );
  return match?.[1] ?? null;
}

function requireOperator(
  request: Request,
  operatorAuth: OperatorAuth,
): OperatorPrincipal | Response {
  const principal = operatorAuth.resolve(request);
  if (!principal) {
    return unauthorized();
  }
  return principal;
}

async function writeAudit(
  db: D1Database,
  operatorId: string,
  action: string,
  target: string,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, ?, ?, NULL, NULL, ?)`,
    )
    .bind(newId(), operatorId, action, target, nowIso())
    .run();
}

async function parseJsonBody<T>(request: Request): Promise<T | Response> {
  try {
    return (await request.json()) as T;
  } catch {
    return reject(400, "invalid_json");
  }
}

export async function handleEnroll(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const installationId = parseInstallationId(request);
  if (!installationId) {
    return reject(400, "invalid_route");
  }

  const body = await parseJsonBody<EnrollPayload>(request);
  if (body instanceof Response) {
    return body;
  }

  const { DB } = bindings;
  const existing = await DB.prepare(
    "SELECT installation_id FROM installation WHERE installation_id = ? OR org_id = ?",
  )
    .bind(installationId, body.org_id)
    .first<{ installation_id: string }>();

  if (existing) {
    return reject(409, "already_enrolled");
  }

  const enrolledAt = nowIso();
  const entitlementId = newId();
  const auditId = newId();
  const platformBaseUrl = new URL(request.url).origin;

  await DB.batch([
    DB.prepare(
      `INSERT INTO installation
         (installation_id, org_id, display_name, status, region, enrolled_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    ).bind(
      installationId,
      body.org_id,
      body.display_name,
      INSTALLATION_ACTIVE_STATUS,
      body.region,
      enrolledAt,
    ),
    DB.prepare(
      `INSERT INTO installation_key
         (key_id, installation_id, public_key, algorithm, valid_from, valid_until, revoked_at)
       VALUES (?, ?, ?, ?, ?, NULL, NULL)`,
    ).bind(
      body.kid,
      installationId,
      body.public_key,
      body.algorithm,
      enrolledAt,
    ),
    DB.prepare(
      `INSERT INTO entitlement
         (entitlement_id, installation_id, plan, period_start, period_end,
          request_quota, token_budget, cost_budget, allowed_capabilities,
          soft_threshold, status)
       VALUES (?, ?, ?, ?, ?, 0, 0, 0, '[]', 0, 'pending')`,
    ).bind(entitlementId, installationId, body.plan, enrolledAt, enrolledAt),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'enroll', ?, NULL, NULL, ?)`,
    ).bind(auditId, auth.operatorId, installationId, enrolledAt),
  ]);

  return ok({ platform_base_url: platformBaseUrl });
}

export async function handleRotate(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const installationId = parseInstallationId(request);
  if (!installationId) {
    return reject(400, "invalid_route");
  }

  const body = await parseJsonBody<RotatePayload>(request);
  if (body instanceof Response) {
    return body;
  }

  const { DB } = bindings;
  const installation = await DB.prepare(
    "SELECT installation_id FROM installation WHERE installation_id = ?",
  )
    .bind(installationId)
    .first<{ installation_id: string }>();

  if (!installation) {
    return reject(404, "installation_not_found");
  }

  const validFrom = nowIso();
  const auditId = newId();

  await DB.batch([
    DB.prepare(
      `INSERT INTO installation_key
         (key_id, installation_id, public_key, algorithm, valid_from, valid_until, revoked_at)
       VALUES (?, ?, ?, ?, ?, NULL, NULL)`,
    ).bind(
      body.kid,
      installationId,
      body.public_key,
      body.algorithm,
      validFrom,
    ),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'rotate', ?, NULL, NULL, ?)`,
    ).bind(auditId, auth.operatorId, installationId, validFrom),
  ]);

  return ok();
}

export async function handleSuspend(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const installationId = parseInstallationId(request);
  if (!installationId) {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const installation = await DB.prepare(
    "SELECT installation_id FROM installation WHERE installation_id = ?",
  )
    .bind(installationId)
    .first<{ installation_id: string }>();

  if (!installation) {
    return reject(404, "installation_not_found");
  }

  const recordedAt = nowIso();
  const auditId = newId();

  await DB.batch([
    DB.prepare(
      "UPDATE installation SET status = ? WHERE installation_id = ?",
    ).bind(INSTALLATION_SUSPENDED_STATUS, installationId),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'suspend', ?, NULL, NULL, ?)`,
    ).bind(auditId, auth.operatorId, installationId, recordedAt),
  ]);

  return ok();
}

export async function handleResume(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const installationId = parseInstallationId(request);
  if (!installationId) {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const installation = await DB.prepare(
    "SELECT installation_id, status FROM installation WHERE installation_id = ?",
  )
    .bind(installationId)
    .first<{ installation_id: string; status: string }>();

  if (!installation) {
    return reject(404, "installation_not_found");
  }

  const recordedAt = nowIso();
  const auditId = newId();
  const restoredStatus =
    installation.status === INSTALLATION_SUSPENDED_STATUS
      ? INSTALLATION_ACTIVE_STATUS
      : installation.status;

  await DB.batch([
    DB.prepare(
      "UPDATE installation SET status = ? WHERE installation_id = ?",
    ).bind(restoredStatus, installationId),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'resume', ?, NULL, NULL, ?)`,
    ).bind(auditId, auth.operatorId, installationId, recordedAt),
  ]);

  return ok();
}

export async function handleDelete(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth,
): Promise<Response> {
  const auth = requireOperator(request, operatorAuth);
  if (auth instanceof Response) {
    return auth;
  }

  const installationId = parseInstallationId(request);
  if (!installationId) {
    return reject(400, "invalid_route");
  }

  const { DB } = bindings;
  const installation = await DB.prepare(
    "SELECT installation_id FROM installation WHERE installation_id = ?",
  )
    .bind(installationId)
    .first<{ installation_id: string }>();

  if (!installation) {
    return reject(404, "installation_not_found");
  }

  const recordedAt = nowIso();
  const auditId = newId();

  await DB.batch([
    DB.prepare(
      "UPDATE installation SET status = ? WHERE installation_id = ?",
    ).bind(INSTALLATION_DELETED_STATUS, installationId),
    DB.prepare(
      `INSERT INTO control_audit
         (audit_id, operator_id, action, target, before_pointer, after_pointer, recorded_at)
       VALUES (?, ?, 'delete', ?, NULL, NULL, ?)`,
    ).bind(auditId, auth.operatorId, installationId, recordedAt),
  ]);

  return ok();
}

const CONTROL_ACTION_PATTERN =
  /^\/control\/installations\/[^/]+\/(enroll|rotate|suspend|resume|delete)$/;

export function isControlRoute(pathname: string): boolean {
  return CONTROL_ACTION_PATTERN.test(pathname);
}

export async function dispatchControlRequest(
  request: Request,
  bindings: ControlBindings,
  operatorAuth: OperatorAuth = defaultOperatorAuth,
): Promise<Response> {
  const action = new URL(request.url).pathname.split("/").pop();

  switch (action) {
    case "enroll":
      return handleEnroll(request, bindings, operatorAuth);
    case "rotate":
      return handleRotate(request, bindings, operatorAuth);
    case "suspend":
      return handleSuspend(request, bindings, operatorAuth);
    case "resume":
      return handleResume(request, bindings, operatorAuth);
    case "delete":
      return handleDelete(request, bindings, operatorAuth);
    default:
      return new Response("Not Found", { status: 404 });
  }
}
