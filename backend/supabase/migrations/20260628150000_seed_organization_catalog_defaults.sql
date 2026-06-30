-- Seed default org catalog rows (vital signs, medications, investigations) for new and existing orgs.
-- Fixes gap where 20260628140000 only seeded orgs that existed at migration apply time.

CREATE OR REPLACE FUNCTION auth_internal.seed_organization_catalog_defaults(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_organization_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.organizations o
    WHERE o.id = p_organization_id AND o.is_deleted = false
  ) THEN
    RETURN;
  END IF;

  INSERT INTO public.predefined_vital_signs (organization_id, name, default_unit)
  SELECT p_organization_id, seed.name, seed.default_unit
  FROM (
    VALUES
      ('Blood Pressure', 'mmHg'),
      ('Heart Rate', 'bpm'),
      ('Temperature', '°C'),
      ('Respiratory Rate', '/min'),
      ('Oxygen Saturation', '%'),
      ('Weight', 'kg'),
      ('Height', 'cm')
  ) AS seed(name, default_unit)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.predefined_vital_signs pvs
    WHERE pvs.organization_id = p_organization_id
      AND pvs.is_deleted = false
      AND lower(trim(pvs.name)) = lower(trim(seed.name))
  );

  INSERT INTO public.medications (organization_id, name)
  SELECT p_organization_id, seed.name
  FROM (
    VALUES
      ('Amoxicillin'), ('Ibuprofen'), ('Paracetamol'), ('Omeprazole'), ('Metformin'),
      ('Atorvastatin'), ('Amlodipine'), ('Salbutamol'), ('Cetirizine'), ('Azithromycin')
  ) AS seed(name)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.medications m
    WHERE m.organization_id = p_organization_id
      AND m.is_deleted = false
      AND lower(trim(m.name)) = lower(trim(seed.name))
  );

  INSERT INTO public.investigations (organization_id, name)
  SELECT p_organization_id, seed.name
  FROM (
    VALUES
      ('Complete Blood Count'), ('Lipid Panel'), ('Chest X-Ray'), ('Urinalysis'),
      ('Fasting Blood Glucose'), ('Liver Function Test'), ('Thyroid Panel'),
      ('ECG'), ('Abdominal Ultrasound'), ('HbA1c')
  ) AS seed(name)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.investigations i
    WHERE i.organization_id = p_organization_id
      AND i.is_deleted = false
      AND lower(trim(i.name)) = lower(trim(seed.name))
  );
END;
$$;

-- Backfill every active organization (including orgs created after the redesign migration).
SELECT auth_internal.seed_organization_catalog_defaults(o.id)
FROM public.organizations o
WHERE o.is_deleted = false;

-- Ensure future bootstrap org creation gets catalog defaults.
CREATE OR REPLACE FUNCTION auth_internal.bootstrap_create_organization(
  p_name text,
  p_settings_json jsonb DEFAULT '{}'::jsonb,
  p_logo_url text DEFAULT NULL,
  p_currency_code text DEFAULT NULL,
  p_timezone text DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
BEGIN
  PERFORM auth_internal.assert_bootstrap_admin();

  IF auth_internal.organization_exists() THEN
    RETURN public.rpc_error('ORG_ALREADY_EXISTS', 'An organization already exists for this installation.');
  END IF;

  IF NULLIF(trim(p_name), '') IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Organization name is required.');
  END IF;

  INSERT INTO public.organizations (
    name,
    logo_url,
    currency_code,
    timezone,
    settings_json,
    created_by,
    updated_by
  )
  VALUES (
    trim(p_name),
    NULLIF(trim(p_logo_url), ''),
    NULLIF(trim(p_currency_code), ''),
    NULLIF(trim(p_timezone), ''),
    COALESCE(p_settings_json, '{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  RETURNING id INTO v_org_id;

  PERFORM auth_internal.seed_organization_catalog_defaults(v_org_id);

  INSERT INTO public.audit_log (user_id, organization_id, action, table_name, record_id, new_data_json)
  VALUES (
    auth.uid(),
    v_org_id,
    'organization.bootstrap_create',
    'organizations',
    v_org_id,
    jsonb_build_object(
      'name', trim(p_name),
      'logo_url', NULLIF(trim(p_logo_url), ''),
      'currency_code', NULLIF(trim(p_currency_code), ''),
      'timezone', NULLIF(trim(p_timezone), '')
    )
  );

  RETURN public.rpc_success(jsonb_build_object('organization_id', v_org_id));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'NOT_BOOTSTRAP_ADMIN' THEN
      RETURN public.rpc_error('NOT_BOOTSTRAP_ADMIN', 'Only the bootstrap administrator may create the organization.');
    END IF;
    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION auth_internal.seed_organization_catalog_defaults(uuid) TO authenticated;
