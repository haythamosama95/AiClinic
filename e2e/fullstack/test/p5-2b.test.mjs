import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test, { before } from "node:test";
import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
import { subscriptionRef } from "vendor-contracts";

// H-FS unit harness (P5.2b): node --import tsx --test test/p5-2b.test.mjs

const REPO_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../..",
);

const SUPABASE_URL = process.env.SUPABASE_URL ?? "http://127.0.0.1:54321";
const SUPABASE_ANON_KEY =
  process.env.SUPABASE_ANON_KEY ??
  process.env.ANON_KEY ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";
const DB_URL =
  process.env.DB_URL ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

const STAFF_ROLES = [
  "administrator",
  "doctor",
  "receptionist",
  "lab_staff",
];

const FORBIDDEN_STAFF_STATUS_KEYS = [
  "subscription_ref",
  "term_ref",
  "abo_base_url",
  "plan",
  "plan_display_name",
  "allowance",
  "used",
  "queued_count",
  "held_count",
  "remaining",
  "price",
  "payment",
];

let clinic = null;

function psqlQuery(sql) {
  const result = spawnSync(
    "psql",
    [DB_URL, "-v", "ON_ERROR_STOP=1", "-t", "-A", "-c", sql],
    { encoding: "utf8" },
  );
  if (result.status !== 0) {
    throw new Error(`psql failed: ${result.stderr || result.stdout}`);
  }
  return result.stdout.trim();
}

function readDbNow() {
  return psqlQuery("SELECT now()::timestamptz");
}

async function rpc(client, fn, args = {}) {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new Error(`${fn} failed: ${error.message}`);
  }
  return data;
}

async function signIn(email, password) {
  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.signInWithPassword({
    email,
    password,
  });
  if (error) {
    throw new Error(`sign in ${email} failed: ${error.message}`);
  }
  return client;
}

function seedStaffMembership(orgId, username, role) {
  psqlQuery(`
    INSERT INTO ai_internal.membership (user_id, organization_id, role)
    SELECT u.id, '${orgId}', '${role}'::public.staff_role
    FROM auth.users u
    WHERE u.email = '${username}'
    ON CONFLICT (user_id, organization_id) DO NOTHING
  `);
}

async function createClinicFixture() {
  psqlQuery(`
    DELETE FROM ai_internal.user_active_organization uao
    USING auth.users u
    WHERE uao.user_id = u.id
      AND u.email LIKE 'p5-2b-%';
    DELETE FROM ai_internal.membership m
    USING auth.users u
    WHERE m.user_id = u.id
      AND u.email LIKE 'p5-2b-%';
    DELETE FROM public.staff_branch_assignments sba
    USING public.staff_members sm
    WHERE sba.staff_member_id = sm.id
      AND sm.auth_user_id IN (SELECT id FROM auth.users WHERE email LIKE 'p5-2b-%');
    DELETE FROM public.staff_members sm
    WHERE sm.auth_user_id IN (SELECT id FROM auth.users WHERE email LIKE 'p5-2b-%');
    DELETE FROM auth.users WHERE email LIKE 'p5-2b-%';
  `);

  const bootstrap = await signIn("admin", "admin");

  let orgResult = await rpc(bootstrap, "bootstrap_create_organization", {
    p_name: "H-FS P5.2b Org",
    p_settings_json: {},
    p_currency_code: "EGP",
    p_timezone: "UTC",
  });
  if (!orgResult?.success) {
    const existingOrg = psqlQuery(
      "SELECT id FROM public.organizations WHERE is_deleted = false ORDER BY created_at LIMIT 1",
    );
    orgResult = {
      success: true,
      data: { organization_id: existingOrg },
    };
  }
  const orgId = orgResult.data.organization_id;
  await bootstrap.auth.refreshSession();

  let branchId = psqlQuery(
    `SELECT id FROM public.branches WHERE organization_id = '${orgId}' AND code = 'P52B' AND is_deleted = false LIMIT 1`,
  );
  if (!branchId) {
    let branchResult = await rpc(bootstrap, "bootstrap_create_branch", {
      p_organization_id: orgId,
      p_name: "H-FS P5.2b Main",
      p_code: "P52B",
    });
    if (!branchResult?.success) {
      branchId = psqlQuery(
        `SELECT id FROM public.branches WHERE organization_id = '${orgId}' AND is_deleted = false LIMIT 1`,
      );
    } else {
      branchId = branchResult.data.branch_id;
    }
  }
  await bootstrap.auth.refreshSession();

  const createStaff = async (username, password, fullName, role) => {
    const result = await rpc(bootstrap, "create_staff_account", {
      p_username: username,
      p_password: password,
      p_full_name: fullName,
      p_role: role,
      p_branch_ids: [branchId],
      p_primary_branch_id: branchId,
      p_phone: null,
    });
    if (!result?.success) {
      throw new Error(
        `create_staff_account(${username}) failed: ${result?.error_code ?? "unknown"}`,
      );
    }
    seedStaffMembership(orgId, username, role);
    return signIn(username, password);
  };

  const clients = {};
  for (const role of STAFF_ROLES) {
    const username = `p5-2b-${role.replace("_", "-")}`;
    clients[role] = await createStaff(
      username,
      "P52bPass!",
      `P5.2b ${role}`,
      role,
    );
  }

  return {
    orgId,
    branchId,
    installationId: crypto.randomUUID(),
    clients,
    administrator: clients.administrator,
  };
}

function clearClinicAiCoverage(orgId) {
  psqlQuery(`
    DELETE FROM ai_internal.clinic_ai_coverage
    WHERE organization_id = '${orgId}'
  `);
}

function seedClinicAiCoverage({
  orgId,
  installationId,
  bindingEpoch = 1,
  clinicSeq = 1,
  state = "active",
  reason = "none",
  termRef = "TERM-P52B",
  planDisplayName = "P5.2b Test Plan",
  startsAtSql = "now() - interval '30 days'",
  endsAtSql = "now() + interval '30 days'",
  graceEndsAtSql = "now() + interval '37 days'",
  allowance = 10000,
  used = 0,
  band = "ok",
  queuedCount = 0,
  heldCount = 0,
  suspended = false,
  eventAtSql = "timestamp '2020-06-15 12:00:00+00'",
  appliedAtSql = "timestamp '2021-03-20 08:00:00+00'",
}) {
  clearClinicAiCoverage(orgId);
  psqlQuery(`
    INSERT INTO ai_internal.clinic_ai_coverage (
      organization_id,
      installation_id,
      binding_epoch,
      clinic_seq,
      state,
      reason,
      term_ref,
      plan_display_name,
      starts_at,
      ends_at,
      grace_ends_at,
      allowance,
      used,
      band,
      queued_count,
      held_count,
      suspended,
      event_at,
      applied_at
    ) VALUES (
      '${orgId}',
      '${installationId}',
      ${bindingEpoch},
      ${clinicSeq},
      '${state}',
      '${reason}',
      '${termRef}',
      '${planDisplayName}',
      ${startsAtSql},
      ${endsAtSql},
      ${graceEndsAtSql},
      ${allowance},
      ${used},
      '${band}',
      ${queuedCount},
      ${heldCount},
      ${suspended},
      ${eventAtSql},
      ${appliedAtSql}
    )
  `);
}

function setFeedStateLastSuccessAgo(seconds) {
  psqlQuery(`
    UPDATE ai_internal.feed_state
    SET last_success_at = now() - interval '${seconds} seconds'
    WHERE singleton
  `);
}

function setFeedStateFresh() {
  psqlQuery(`
    UPDATE ai_internal.feed_state
    SET last_success_at = now()
    WHERE singleton
  `);
}

function readCoverageReason(orgId) {
  return psqlQuery(`
    SELECT reason
    FROM ai_internal.clinic_ai_coverage
    WHERE organization_id = '${orgId}'
    LIMIT 1
  `);
}

function readFeedStateLastSuccessAt() {
  return psqlQuery(`
    SELECT last_success_at::timestamptz
    FROM ai_internal.feed_state
    WHERE singleton
    LIMIT 1
  `);
}

function findNotice(notices, code) {
  return (notices ?? []).find((notice) => notice.code === code);
}

function assertHasNoticeCodes(notices, codes) {
  for (const code of codes) {
    assert.ok(findNotice(notices, code), `expected notice code ${code}`);
  }
}

function assertAsOfBetween(asOf, before, after) {
  const asOfMs = Date.parse(asOf);
  const beforeMs = Date.parse(before);
  const afterMs = Date.parse(after);
  assert.ok(
    asOfMs >= beforeMs - 1000,
    `as_of ${asOf} should not be before ${before}`,
  );
  assert.ok(
    asOfMs <= afterMs + 1000,
    `as_of ${asOf} should not be after ${after}`,
  );
}

async function callGetAiStatusWithAsOf(client, args = { p_contract_version: 1 }) {
  const before = readDbNow();
  const status = await rpc(client, "get_ai_status", args);
  const after = readDbNow();
  return { status, before, after };
}

before(async () => {
  clinic = await createClinicFixture();
});

test(
  "E2E-P5.2-03 Stored dates pass to grace then lapsed while workers are stopped, then stale and status_stale",
  async () => {
    const { orgId, installationId, administrator } = clinic;
    setFeedStateFresh();

    seedClinicAiCoverage({
      orgId,
      installationId,
      state: "active",
      queuedCount: 0,
      endsAtSql: "now() - interval '1 hour'",
      graceEndsAtSql: "now() + interval '3 days'",
      eventAtSql: "timestamp '2020-06-15 12:00:00+00'",
      appliedAtSql: "timestamp '2021-03-20 08:00:00+00'",
    });

    const graceCall = await callGetAiStatusWithAsOf(administrator);
    assert.equal(graceCall.status.contract_version, 1);
    assert.equal(graceCall.status.success, true);
    assert.equal(graceCall.status.data.state, "grace");
    assert.equal(graceCall.status.data.available, true);
    assert.equal(graceCall.status.data.reason, null);
    assertHasNoticeCodes(graceCall.status.data.notices, ["in_grace"]);
    const inGrace = findNotice(graceCall.status.data.notices, "in_grace");
    assert.equal(inGrace.audience, "member");
    assert.equal(inGrace.channel, "in_app");
    assert.ok(
      Number.isInteger(inGrace.grace_days_left) && inGrace.grace_days_left >= 0,
      "in_grace should carry grace_days_left",
    );
    assertAsOfBetween(
      graceCall.status.data.as_of,
      graceCall.before,
      graceCall.after,
    );
    const asOfMs = Date.parse(graceCall.status.data.as_of);
    assert.ok(
      asOfMs > Date.parse("2022-01-01T00:00:00Z"),
      "as_of should not be seeded event_at or applied_at",
    );

    seedClinicAiCoverage({
      orgId,
      installationId,
      state: "active",
      queuedCount: 0,
      endsAtSql: "now() - interval '2 days'",
      graceEndsAtSql: "now() - interval '1 hour'",
    });

    const lapsedCall = await callGetAiStatusWithAsOf(administrator);
    assert.equal(lapsedCall.status.success, true);
    assert.equal(lapsedCall.status.data.state, "lapsed");
    assert.equal(lapsedCall.status.data.available, false);
    assert.equal(lapsedCall.status.data.reason, "expired");
    assertHasNoticeCodes(lapsedCall.status.data.notices, ["lapsed"]);

    setFeedStateLastSuccessAgo(121);
    const lastSuccessAt = readFeedStateLastSuccessAt();
    const staleCall = await callGetAiStatusWithAsOf(administrator);
    assert.equal(staleCall.status.success, true);
    assert.equal(staleCall.status.data.stale, true);
    assertHasNoticeCodes(staleCall.status.data.notices, ["status_stale"]);
    assert.notEqual(
      staleCall.status.data.as_of,
      lastSuccessAt,
      "as_of should not be last_success_at",
    );

    clearClinicAiCoverage(orgId);
    const absentCall = await callGetAiStatusWithAsOf(administrator);
    assert.equal(absentCall.status.success, true);
    assert.equal(absentCall.status.data.state, "none");
    assert.equal(absentCall.status.data.available, false);
    assert.equal(absentCall.status.data.reason, "none");
    assert.equal(absentCall.status.data.days_left, null);
    assertAsOfBetween(
      absentCall.status.data.as_of,
      absentCall.before,
      absentCall.after,
    );
  },
);

test(
  "E2E-P5.2-04 ends_soon at 7, 3, and 1 days when queued_count is 0, staff status has no prices, and staff billing is FORBIDDEN_ROLE",
  async () => {
    const { orgId, installationId, clients, administrator } = clinic;
    setFeedStateFresh();

    const endsSoonDays = [7, 3, 1, 0];
    for (const days of endsSoonDays) {
      const endsAtSql =
        days === 0
          ? "now() + interval '12 hours'"
          : `date_trunc('day', now()) + interval '${days + 1} days'`;
      seedClinicAiCoverage({
        orgId,
        installationId,
        state: "active",
        queuedCount: 0,
        endsAtSql,
        graceEndsAtSql: `now() + interval '${days + 7} days'`,
      });

      const status = await rpc(administrator, "get_ai_status", {
        p_contract_version: 1,
      });
      assert.equal(status.success, true);
      assertHasNoticeCodes(status.data.notices, ["ends_soon"]);
    }

    seedClinicAiCoverage({
      orgId,
      installationId,
      state: "active",
      queuedCount: 0,
      endsAtSql: "now() - interval '1 day'",
      graceEndsAtSql: "now() + interval '6 days'",
    });
    const nullDaysLeft = await rpc(administrator, "get_ai_status", {
      p_contract_version: 1,
    });
    assert.equal(nullDaysLeft.success, true);
    assert.equal(nullDaysLeft.data.days_left, null);
    assert.equal(findNotice(nullDaysLeft.data.notices, "ends_soon"), undefined);

    const staffStatus = await rpc(clients.doctor, "get_ai_status", {
      p_contract_version: 1,
    });
    assert.equal(staffStatus.success, true);
    for (const key of FORBIDDEN_STAFF_STATUS_KEYS) {
      assert.equal(
        Object.hasOwn(staffStatus.data, key),
        false,
        `staff get_ai_status should not expose ${key}`,
      );
    }

    const forbiddenBilling = await rpc(clients.doctor, "get_ai_billing_status", {
      p_contract_version: 1,
    });
    assert.equal(forbiddenBilling.success, false);
    assert.equal(forbiddenBilling.error_code, "FORBIDDEN_ROLE");
    assert.equal(forbiddenBilling.data, null);

    seedClinicAiCoverage({
      orgId,
      installationId,
      state: "active",
      reason: "none",
      queuedCount: 0,
    });
    const reasonBefore = readCoverageReason(orgId);

    const missingStatusVersion = await rpc(administrator, "get_ai_status", {});
    assert.equal(missingStatusVersion.success, false);
    assert.equal(
      missingStatusVersion.error_code,
      "CONTRACT_VERSION_UNSUPPORTED",
    );

    const unsupportedStatusVersion = await rpc(administrator, "get_ai_status", {
      p_contract_version: 2,
    });
    assert.equal(unsupportedStatusVersion.success, false);
    assert.equal(
      unsupportedStatusVersion.error_code,
      "CONTRACT_VERSION_UNSUPPORTED",
    );

    const missingBillingVersion = await rpc(
      administrator,
      "get_ai_billing_status",
      {},
    );
    assert.equal(missingBillingVersion.success, false);
    assert.equal(
      missingBillingVersion.error_code,
      "CONTRACT_VERSION_UNSUPPORTED",
    );

    const unsupportedBillingVersion = await rpc(
      administrator,
      "get_ai_billing_status",
      { p_contract_version: 2 },
    );
    assert.equal(unsupportedBillingVersion.success, false);
    assert.equal(
      unsupportedBillingVersion.error_code,
      "CONTRACT_VERSION_UNSUPPORTED",
    );

    const reasonAfter = readCoverageReason(orgId);
    assert.equal(reasonAfter, reasonBefore);
  },
);

test(
  "E2E-P5.2-09 SQL subscription ref equals the package vector and the ABO and platform values",
  async () => {
    const { orgId, installationId, administrator } = clinic;
    setFeedStateFresh();

    seedClinicAiCoverage({
      orgId,
      installationId,
      state: "active",
      queuedCount: 0,
      planDisplayName: "P5.2b Billing Plan",
      startsAtSql: "now() - interval '10 days'",
      endsAtSql: "now() + interval '20 days'",
      graceEndsAtSql: "now() + interval '27 days'",
      allowance: 5000,
      used: 1200,
      heldCount: 2,
    });

    const expectedRef = await subscriptionRef(orgId);
    const billing = await rpc(administrator, "get_ai_billing_status", {
      p_contract_version: 1,
    });
    assert.equal(billing.contract_version, 1);
    assert.equal(billing.success, true);
    assert.equal(billing.data.subscription_ref, expectedRef);
    assert.equal(billing.data.plan_display_name, "P5.2b Billing Plan");
    assert.ok(billing.data.starts_at);
    assert.ok(billing.data.ends_at);
    assert.ok(billing.data.grace_ends_at);
    assert.equal(billing.data.allowance, 5000);
    assert.equal(billing.data.used, 1200);
    assert.equal(billing.data.queued_count, 0);
    assert.equal(billing.data.held_count, 2);
    assert.ok(billing.data.abo_base_url);
    assert.equal(Object.hasOwn(billing.data, "remaining"), false);
  },
);

test(
  "E2E-P5.2-11 Band 90 raises allowance_low for every role",
  async () => {
    const { orgId, installationId, clients } = clinic;
    setFeedStateFresh();

    seedClinicAiCoverage({
      orgId,
      installationId,
      state: "active",
      band: "90",
      queuedCount: 0,
    });

    for (const role of STAFF_ROLES) {
      const status = await rpc(clients[role], "get_ai_status", {
        p_contract_version: 1,
      });
      assert.equal(status.success, true);
      const allowanceLow = findNotice(status.data.notices, "allowance_low");
      assert.ok(allowanceLow, `${role} should receive allowance_low`);
      assert.equal(allowanceLow.code, "allowance_low");
      assert.equal(allowanceLow.audience, "member");
      assert.equal(allowanceLow.channel, "in_app");
      assert.equal(
        Object.hasOwn(allowanceLow, "grace_days_left"),
        false,
        "allowance_low should not carry grace_days_left",
      );
    }
  },
);
