-- V1-4 appointment RPC grant regression (PostgREST / authenticated path).
-- Catches missing GRANT EXECUTE on auth_internal wrappers (see 20260527150000_*).
--
-- Note: appointment_management_crud.sql runs as the psql superuser (postgres). That bypasses
-- EXECUTE checks on auth_internal that PostgREST enforces for role authenticated.
-- Grant regressions are also covered by Flutter boundary tests (test/boundary/appointments/).

BEGIN;

CREATE TEMP TABLE appointment_grant_results (
  test_name text PRIMARY KEY,
  passed boolean NOT NULL,
  detail text
);

DO $$
DECLARE
  r record;
  v_missing text[] := ARRAY[]::text[];
  v_sig regprocedure;
  v_required regprocedure[] := ARRAY[
    'auth_internal.get_appointment_settings(uuid)'::regprocedure,
    'auth_internal.set_appointment_default_duration(uuid,integer)'::regprocedure,
    'auth_internal.create_appointment(uuid,uuid,uuid,text,timestamp with time zone,integer,timestamp with time zone,text)'::regprocedure,
    'auth_internal.reschedule_appointment(uuid,timestamp with time zone,integer,timestamp with time zone)'::regprocedure,
    'auth_internal.cancel_appointment(uuid,text)'::regprocedure,
    'auth_internal.update_appointment_status(uuid,text)'::regprocedure,
    'auth_internal.list_appointments(uuid,timestamp with time zone,timestamp with time zone,uuid,text[],uuid)'::regprocedure
  ];
BEGIN
  FOREACH v_sig IN ARRAY v_required LOOP
    IF NOT has_function_privilege('authenticated', v_sig, 'EXECUTE') THEN
      v_missing := array_append(v_missing, v_sig::text);
    END IF;
  END LOOP;

  INSERT INTO appointment_grant_results VALUES (
    'authenticated_execute_on_auth_internal_appointment_rpcs',
    cardinality(v_missing) = 0,
    CASE
      WHEN cardinality(v_missing) = 0 THEN 'ok'
      ELSE 'missing: ' || array_to_string(v_missing, '; ')
    END
  );

  INSERT INTO appointment_grant_results VALUES (
    'public_get_appointment_settings_granted',
    has_function_privilege('authenticated', 'public.get_appointment_settings(uuid)'::regprocedure, 'EXECUTE'),
    'public wrapper'
  );

  INSERT INTO appointment_grant_results VALUES (
    'public_create_appointment_granted',
    has_function_privilege(
      'authenticated',
      'public.create_appointment(uuid,uuid,uuid,text,timestamp with time zone,integer,timestamp with time zone,text)'::regprocedure,
      'EXECUTE'
    ),
    'public wrapper'
  );

  INSERT INTO appointment_grant_results VALUES (
    'public_set_appointment_default_duration_granted',
    has_function_privilege(
      'authenticated',
      'public.set_appointment_default_duration(integer,uuid)'::regprocedure,
      'EXECUTE'
    ),
    'public wrapper'
  );

  INSERT INTO appointment_grant_results VALUES (
    'public_list_appointments_granted',
    has_function_privilege(
      'authenticated',
      'public.list_appointments(uuid,timestamp with time zone,timestamp with time zone,uuid,text[],uuid)'::regprocedure,
      'EXECUTE'
    ),
    'public wrapper'
  );

  INSERT INTO appointment_grant_results VALUES (
    'public_reschedule_appointment_granted',
    has_function_privilege(
      'authenticated',
      'public.reschedule_appointment(uuid,timestamp with time zone,integer,timestamp with time zone)'::regprocedure,
      'EXECUTE'
    ),
    'public wrapper'
  );

  INSERT INTO appointment_grant_results VALUES (
    'public_cancel_appointment_granted',
    has_function_privilege(
      'authenticated',
      'public.cancel_appointment(uuid,text)'::regprocedure,
      'EXECUTE'
    ),
    'public wrapper'
  );

  INSERT INTO appointment_grant_results VALUES (
    'public_update_appointment_status_granted',
    has_function_privilege(
      'authenticated',
      'public.update_appointment_status(uuid,text)'::regprocedure,
      'EXECUTE'
    ),
    'public wrapper'
  );
END;
$$;

DO $$
DECLARE
  r record;
  v_failed int;
BEGIN
  SELECT count(*)::int
  INTO v_failed
  FROM appointment_grant_results
  WHERE NOT passed;

  IF v_failed > 0 THEN
    FOR r IN SELECT test_name, detail FROM appointment_grant_results WHERE NOT passed LOOP
      RAISE NOTICE 'FAIL %: %', r.test_name, r.detail;
    END LOOP;
    RAISE EXCEPTION 'appointment_management_grants: % test(s) failed', v_failed;
  END IF;
END;
$$;

ROLLBACK;
