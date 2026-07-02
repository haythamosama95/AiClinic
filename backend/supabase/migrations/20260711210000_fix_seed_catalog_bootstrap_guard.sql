-- Fix catalog seed guard: allow org-insert trigger during bootstrap when JWT has no org yet.
-- Regression from 20260711120000: DISTINCT FROM jwt_organization_id() blocked seeding when
-- jwt_organization_id() was NULL (bootstrap_finish_setup / organizations INSERT trigger).

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

  -- Block cross-tenant invocation only when the session already has an org claim.
  IF auth.uid() IS NOT NULL
    AND public.jwt_organization_id() IS NOT NULL
    AND p_organization_id IS DISTINCT FROM public.jwt_organization_id() THEN
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
