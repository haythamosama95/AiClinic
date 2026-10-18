#!/usr/bin/env python3
"""Backend SQL/shell test campaigns."""

from __future__ import annotations

import sys
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TESTS_DIR.parents[1]
sys.path.insert(0, str(REPO_ROOT / "test"))

from harness.common import (  # noqa: E402
    TestHarness,
    TestStep,
    catalog_sql_steps,
    live_progress_child_enabled,
    load_backend_local_env,
    new_run_id,
    resolve_governor_run_id,
    run_campaign_script,
    sql_steps,
)

AREA = "backend"

_PATIENT_SQL = (
    "patient_mrn_generation.sql",
    "patient_mrn_reassign.sql",
    "invoices_patient_mrn_payload_test.sql",
    "patient_management_crud.sql",
    "patient_transfer_restore.sql",
    "patient_management_rls.sql",
    "patient_management_extended.sql",
    "patient_management_roles.sql",
    "patient_management_search_advanced.sql",
    "patient_management_search_filters.sql",
    "patient_management_concurrent.sql",
)

_APPOINTMENT_SQL = (
    "appointment_management_grants.sql",
    "appointment_management_crud.sql",
    "appointment_get_update.sql",
    "appointment_simplified_booking_slots.sql",
    "appointment_management_patient_filter.sql",
    "appointment_management_rls.sql",
    "appointment_calendar_backend_integrity.sql",
    "appointments_patient_mrn_payload_test.sql",
    "appointment_queue_qa.sql",
)

_VISIT_SQL = (
    "visit_medical_records_crud.sql",
    "visit_medical_records_rls.sql",
    "visit_attachment_storage_rls.sql",
    "visit_attachment_delete_storage.sql",
    "patient_visit_attachments_list.sql",
    "visit_encounter_workspace_crud.sql",
    "visit_encounter_workspace_rls.sql",
    "visit_predefined_vital_signs_backfill.sql",
    "visit_documentation_complete_validation.sql",
)

_BILLING_SQL = ("billing_rls.sql", "billing_crud.sql", "billing_concurrency.sql")

_SERVICE_CATALOG_SQL = (
    "service_catalog_crud.sql",
    "service_catalog_list.sql",
    "service_catalog_rls.sql",
    "service_catalog_pricing.sql",
    "service_catalog_concurrency.sql",
)

_SHIFT_SQL = (
    "shift_management_rls.sql",
    "shift_management_crud.sql",
    "shift_management_concurrency.sql",
)

_AI_TRUST_SQL = (
    "ai_keystore_rls.sql",
    "ai_token_issuer.sql",
    "ai_token_contract_rotation.sql",
    "context_provider_rpc.sql",
    "ai_acceptance_recording.sql",
)


def _auth_rbac_steps() -> list[TestStep]:
    return [
        TestStep("Auth flow smoke", "shell", "auth_flow_smoke.sh"),
        TestStep("JWT claims contract", "sql", "jwt_claims_contract.sql"),
        TestStep("Auth security extensions", "sql", "auth_security_extensions.sql"),
        TestStep("Bootstrap RPC", "sql", "bootstrap_rpc.sql"),
        TestStep("Create staff RPC", "sql", "create_staff_rpc.sql"),
        TestStep("Admin reset staff password", "sql", "admin_reset_staff_password.sql"),
        TestStep(
            "Subscription cache nonblocking", "sql", "subscription_cache_nonblocking.sql"
        ),
        TestStep("RPC contract alignment", "sql", "rpc_contract_alignment.sql"),
        TestStep("RLS isolation", "sql", "rls_isolation.sql"),
        TestStep("Auth RBAC extended", "sql", "auth_rbac_extended.sql"),
        TestStep("Owner role migration", "sql", "owner_role_migration.sql"),
        TestStep("Dev reset clinic installation", "sql", "dev_reset_clinic_installation.sql"),
        TestStep("AI keystore RLS", "sql", "ai_keystore_rls.sql"),
        TestStep("AI token issuer", "sql", "ai_token_issuer.sql"),
        TestStep("Staff sign-in after create", "shell", "staff_sign_in_after_create.sh"),
    ]


def _org_branch_steps() -> list[TestStep]:
    return [
        TestStep("Org branch management CRUD", "sql", "org_branch_management_crud.sql"),
        TestStep("Org branch management RLS", "sql", "org_branch_management_rls.sql"),
        TestStep(
            "Org branch management extended", "sql", "org_branch_management_extended.sql"
        ),
        TestStep("Role permissions matrix", "sql", "role_permissions_matrix.sql"),
        TestStep("Admin update staff username", "sql", "admin_update_staff_username.sql"),
        TestStep("Delete staff member", "sql", "delete_staff_member.sql"),
    ]


def _ai_trust_steps() -> list[TestStep]:
    steps: list[TestStep] = []
    for name in _AI_TRUST_SQL:
        steps.append(
            TestStep(
                "Reset ai_token_issuance",
                "psql",
                "DELETE FROM ai_internal.ai_token_issuance;",
            )
        )
        steps.append(TestStep(f"AI platform trust: {name}", "sql", name))
    return steps


def _all_steps() -> list[TestStep]:
    steps = _auth_rbac_steps()
    steps.extend(_org_branch_steps())
    steps.append(
        TestStep("Settings code review fixes", "sql", "settings_code_review_fixes.sql")
    )
    steps.extend(sql_steps("Patient management", _PATIENT_SQL))
    steps.extend(sql_steps("Appointment management", _APPOINTMENT_SQL))
    steps.extend(sql_steps("Visit medical records", _VISIT_SQL))
    steps.extend(sql_steps("Billing", _BILLING_SQL, skip_if_missing=True))
    steps.extend(sql_steps("Service catalog", _SERVICE_CATALOG_SQL, skip_if_missing=True))
    steps.extend(sql_steps("Shift management", _SHIFT_SQL, skip_if_missing=True))
    steps.extend(_ai_trust_steps())
    steps.extend(
        [
            TestStep("Dev reset safety", "sql", "dev_reset_safety.sql"),
            TestStep("Membership active org", "sql", "membership_active_org.sql"),
            TestStep("Cross-tenant suite", "sql", "cross_tenant_suite.sql"),
            TestStep("Issuer RPC", "sql", "issuer_rpc.sql"),
            TestStep("Contract versions", "node", "contract_versions.mjs"),
            TestStep("Staff authority RM01", "sql", "r1_rm01_staff_authority.sql"),
            TestStep("Permission readers RM02", "sql", "r1_rm02_permission_readers.sql"),
        ]
    )
    return steps


def _run_steps(subcampaign: str, steps: list[TestStep]) -> int:
    load_backend_local_env(REPO_ROOT)
    run_id = resolve_governor_run_id()
    live_label = (
        f"[backend/{subcampaign}]"
        if sys.stderr.isatty() and not live_progress_child_enabled()
        else None
    )
    harness = TestHarness(
        REPO_ROOT,
        TESTS_DIR,
        subcampaign,
        run_id,
        area=AREA,
        live_label=live_label,
    )
    return harness.run_steps(steps)


def run_all(_: str) -> int:
    return _run_steps("all", _all_steps())


def run_auth_rbac(_: str) -> int:
    return _run_steps("auth-rbac", _auth_rbac_steps())


def run_org_branch(_: str) -> int:
    return _run_steps("org-branch", _org_branch_steps())


def run_patients(_: str) -> int:
    return _run_steps("patients", sql_steps("Patient management", _PATIENT_SQL))


def run_appointments(_: str) -> int:
    return _run_steps(
        "appointments", sql_steps("Appointment management", _APPOINTMENT_SQL)
    )


def run_visit_medical(_: str) -> int:
    return _run_steps("visit-medical", sql_steps("Visit medical records", _VISIT_SQL))


def run_billing(_: str) -> int:
    return _run_steps(
        "billing", sql_steps("Billing", _BILLING_SQL, skip_if_missing=True)
    )


def run_service_catalog(_: str) -> int:
    return _run_steps(
        "service-catalog",
        sql_steps("Service catalog", _SERVICE_CATALOG_SQL, skip_if_missing=True),
    )


def run_shift(_: str) -> int:
    return _run_steps(
        "shift", sql_steps("Shift management", _SHIFT_SQL, skip_if_missing=True)
    )


def run_ai_platform_trust(_: str) -> int:
    return _run_steps("ai-platform-trust", _ai_trust_steps())


def run_safety(_: str) -> int:
    return _run_steps("safety", [TestStep("Dev reset safety", "sql", "dev_reset_safety.sql")])


def run_membership(_: str) -> int:
    return _run_steps(
        "membership",
        [TestStep("Membership active org", "sql", "membership_active_org.sql")],
    )


def run_cross_tenant(_: str) -> int:
    return _run_steps(
        "cross-tenant",
        [TestStep("Cross-tenant suite", "sql", "cross_tenant_suite.sql")],
    )


def run_p51_issuer(_: str) -> int:
    return _run_steps(
        "p51-issuer",
        [
            TestStep("Issuer RPC", "sql", "issuer_rpc.sql"),
            TestStep("Contract versions", "node", "contract_versions.mjs"),
        ],
    )


def run_catalog(_: str) -> int:
    catalog_dir = TESTS_DIR / "catalog"
    steps = catalog_sql_steps(catalog_dir)
    if not steps:
        print("catalog SQL harness: no files to run.", file=sys.stderr)
        return 1
    return _run_steps("catalog", steps)


_STEP_BUILDERS: dict[str, object] = {
    "all": _all_steps,
    "auth-rbac": _auth_rbac_steps,
    "org-branch": _org_branch_steps,
    "patients": lambda: sql_steps("Patient management", _PATIENT_SQL),
    "appointments": lambda: sql_steps("Appointment management", _APPOINTMENT_SQL),
    "visit-medical": lambda: sql_steps("Visit medical records", _VISIT_SQL),
    "billing": lambda: sql_steps("Billing", _BILLING_SQL, skip_if_missing=True),
    "service-catalog": lambda: sql_steps(
        "Service catalog", _SERVICE_CATALOG_SQL, skip_if_missing=True
    ),
    "shift": lambda: sql_steps("Shift management", _SHIFT_SQL, skip_if_missing=True),
    "ai-platform-trust": _ai_trust_steps,
    "safety": lambda: [TestStep("Dev reset safety", "sql", "dev_reset_safety.sql")],
    "membership": lambda: [
        TestStep("Membership active org", "sql", "membership_active_org.sql")
    ],
    "cross-tenant": lambda: [
        TestStep("Cross-tenant suite", "sql", "cross_tenant_suite.sql")
    ],
    "p51-issuer": lambda: [
        TestStep("Issuer RPC", "sql", "issuer_rpc.sql"),
        TestStep("Contract versions", "node", "contract_versions.mjs"),
    ],
    "catalog": lambda: catalog_sql_steps(TESTS_DIR / "catalog"),
}


def subcampaign_test_counts() -> dict[str, int]:
    """Harness steps per subcampaign (one step ≈ one runnable suite file or smoke)."""
    counts: dict[str, int] = {}
    for key, builder in _STEP_BUILDERS.items():
        steps = builder()  # type: ignore[operator]
        counts[key] = len({step.name for step in steps})
    return counts


SUBCAMPAIGNS = {
    "all": run_all,
    "auth-rbac": run_auth_rbac,
    "org-branch": run_org_branch,
    "patients": run_patients,
    "appointments": run_appointments,
    "visit-medical": run_visit_medical,
    "billing": run_billing,
    "service-catalog": run_service_catalog,
    "shift": run_shift,
    "ai-platform-trust": run_ai_platform_trust,
    "safety": run_safety,
    "membership": run_membership,
    "cross-tenant": run_cross_tenant,
    "p51-issuer": run_p51_issuer,
    "catalog": run_catalog,
}


def main() -> int:
    return run_campaign_script(AREA, SUBCAMPAIGNS)


if __name__ == "__main__":
    raise SystemExit(main())
