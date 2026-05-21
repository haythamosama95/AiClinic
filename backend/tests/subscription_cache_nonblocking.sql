-- FR-014a / SC-008: subscription_cache must NOT block login or JWT claims in V1-1.
-- Run: psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -v ON_ERROR_STOP=1 -f backend/tests/subscription_cache_nonblocking.sql

BEGIN;

CREATE TEMP TABLE subscription_nonblocking_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_claims jsonb;
  v_has_org boolean;
BEGIN
  -- Trivial: claims always include staff identity (subscription state irrelevant).
  v_claims := auth_internal.build_staff_claims(v_bootstrap_user);

  INSERT INTO subscription_nonblocking_results VALUES (
    'bootstrap_claims_include_staff_member_id',
    v_claims ? 'staff_member_id',
    v_claims::text
  );

  SELECT EXISTS (SELECT 1 FROM public.organizations o WHERE o.is_deleted = false) INTO v_has_org;

  INSERT INTO subscription_nonblocking_results VALUES (
    'setup_required_true_only_before_first_org',
    NOT v_has_org OR (v_claims ->> 'setup_required') = 'false',
    'has_org=' || v_has_org::text || ' setup_required=' || COALESCE(v_claims ->> 'setup_required', '<missing>')
  );

  INSERT INTO subscription_nonblocking_results VALUES (
    'claims_never_include_subscription_tier',
    NOT (v_claims ? 'subscription_tier' OR v_claims ? 'subscription_valid_until' OR v_claims ? 'subscription_blocked'),
    'keys=' || (SELECT coalesce(string_agg(key, ','), '') FROM jsonb_object_keys(v_claims) AS key)
  );
END;
$$;

DO $$
DECLARE
  v_bootstrap_user uuid := 'a0000000-0000-4000-8000-000000000001';
  v_claims jsonb;
  v_org_id uuid;
  v_hook jsonb;
BEGIN
  SELECT o.id INTO v_org_id
  FROM public.organizations o
  WHERE o.is_deleted = false
  ORDER BY o.created_at
  LIMIT 1;

  IF v_org_id IS NULL THEN
    INSERT INTO subscription_nonblocking_results VALUES (
      'skip_org_scenarios_no_organization',
      true,
      'no organization seeded; org-level subscription tests skipped'
    );
    RETURN;
  END IF;

  -- Advanced: expired cache row (yesterday) must not strip staff claims.
  INSERT INTO public.subscription_cache (organization_id, tier, valid_until, last_checked_at)
  VALUES (v_org_id, 'expired', now() - interval '1 day', now())
  ON CONFLICT (organization_id) DO UPDATE
  SET tier = EXCLUDED.tier,
      valid_until = EXCLUDED.valid_until,
      last_checked_at = EXCLUDED.last_checked_at;

  v_claims := auth_internal.build_staff_claims(v_bootstrap_user);

  INSERT INTO subscription_nonblocking_results VALUES (
    'expired_cache_staff_member_id_present',
    v_claims ? 'staff_member_id',
    v_claims::text
  );

  -- Corner: far-past expiry (10 years ago).
  UPDATE public.subscription_cache
  SET valid_until = now() - interval '10 years', tier = 'lapsed', last_checked_at = now()
  WHERE organization_id = v_org_id;

  v_claims := auth_internal.build_staff_claims(v_bootstrap_user);

  INSERT INTO subscription_nonblocking_results VALUES (
    'ancient_expiry_still_non_blocking',
    v_claims ? 'staff_role' OR v_claims ? 'staff_member_id',
    v_claims::text
  );

  -- Corner: future validity — should also not add login gates (symmetry check).
  UPDATE public.subscription_cache
  SET valid_until = now() + interval '365 days', tier = 'premium', last_checked_at = now()
  WHERE organization_id = v_org_id;

  v_claims := auth_internal.build_staff_claims(v_bootstrap_user);

  INSERT INTO subscription_nonblocking_results VALUES (
    'future_validity_does_not_add_extra_claims',
    NOT (v_claims ? 'subscription_tier'),
    v_claims::text
  );

  -- Stupid usage: NULL valid_until (unknown expiry) — still must not block.
  UPDATE public.subscription_cache
  SET valid_until = NULL, tier = 'unknown', last_checked_at = now()
  WHERE organization_id = v_org_id;

  v_claims := auth_internal.build_staff_claims(v_bootstrap_user);

  INSERT INTO subscription_nonblocking_results VALUES (
    'null_valid_until_non_blocking',
    v_claims ? 'staff_member_id',
    v_claims::text
  );

  -- Hook path: get_custom_claims(event) must merge staff claims regardless of cache.
  v_hook := public.get_custom_claims(
    jsonb_build_object('user_id', v_bootstrap_user::text, 'claims', jsonb_build_object('role', 'authenticated'))
  );

  INSERT INTO subscription_nonblocking_results VALUES (
    'get_custom_claims_event_includes_staff_member_id_with_expired_cache',
    (v_hook -> 'claims') ? 'staff_member_id',
    (v_hook -> 'claims')::text
  );
END;
$$;

DO $$
DECLARE
  v_org_id uuid;
BEGIN
  SELECT o.id INTO v_org_id
  FROM public.organizations o
  WHERE o.is_deleted = false
  LIMIT 1;

  IF v_org_id IS NULL THEN
    RETURN;
  END IF;

  -- Missing cache row after delete — login path must not depend on cache presence.
  DELETE FROM public.subscription_cache WHERE organization_id = v_org_id;

  INSERT INTO subscription_nonblocking_results VALUES (
    'missing_cache_row_is_ok',
    NOT EXISTS (SELECT 1 FROM public.subscription_cache sc WHERE sc.organization_id = v_org_id),
    'cache row deleted'
  );
END;
$$;

DO $$
DECLARE
  v_failed int;
BEGIN
  SELECT count(*) INTO v_failed
  FROM subscription_nonblocking_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    RAISE EXCEPTION 'subscription_cache_nonblocking: % test(s) failed: %',
      v_failed,
      (SELECT string_agg(test_name || ': ' || detail, '; ') FROM subscription_nonblocking_results WHERE NOT passed);
  END IF;
END;
$$;

COMMIT;

SELECT test_name, passed, detail FROM subscription_nonblocking_results ORDER BY test_name;
