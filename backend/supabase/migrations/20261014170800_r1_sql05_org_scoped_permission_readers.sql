-- =============================================================================
-- R1-SQL-05 (P1): Inherited permission helpers borrow another tenant's grants.
--
-- The five shared helpers (assert_appointment_access,
-- staff_has_invoices_view_access, staff_has_payments_read_access,
-- staff_has_services_read_access, staff_has_shifts_manage) and the nine inline
-- readers (get_billing_settings, list_insurance_providers,
-- check_patient_duplicates, get_patient_safety_context, get_visit,
-- get_service, resolve_effective_service_price_rpc, search_eligible_services,
-- list_services) omitted the org predicate and/or matched the global staff
-- role, so a grant for the same role in organization B could satisfy an
-- explicit denial in organization A.
--
-- Forward overrides: every permission lookup requires
-- rp.organization_id = public.current_org_id() and
-- rp.role = public.current_membership_role() with active/non-deleted caller
-- staff (enforced by current_org_id()'s live-staff predicate, R1-SQL-03);
-- NULL context/role denies. is_granted = true, is_deleted = false and each
-- existing permission-key OR set retained. Tenant/branch guards, restrictive
-- RLS, invoker wrappers, signatures, ACLs and response shapes unchanged.
-- get_visit keeps its clinical-child gating through the scoped helpers.
-- Private auth_internal.resolve_effective_service_price is not touched; no
-- pricing algorithm change.
-- Reuses auth_internal.staff_has_membership_permissions(text[]) from
-- 20261014170700_r1_sql04_membership_role_authority.sql (R1-SQL-04 step 3).
-- Forward-only migration; never edit an applied migration file.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. assert_appointment_access (20260601180000, 23–62): create OR cancel OR
--    read, now org- and membership-role scoped.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.assert_appointment_access()
RETURNS public.staff_members
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.staff_members%ROWTYPE;
BEGIN
  SELECT *
  INTO v_staff
  FROM public.staff_members sm
  WHERE sm.auth_user_id = auth.uid()
    AND sm.is_deleted = false
    AND sm.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  IF v_staff.is_bootstrap_admin AND NOT auth_internal.organization_exists() THEN
    RETURN v_staff;
  END IF;

  IF NOT auth_internal.staff_has_membership_permissions(
    ARRAY['appointments.create', 'appointments.cancel', 'appointments.read']
  ) THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN v_staff;
END;
$$;

-- -----------------------------------------------------------------------------
-- 2. staff_has_invoices_view_access (20260605180300, 3–18).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.staff_has_invoices_view_access()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth_internal.staff_has_membership_permissions(ARRAY['invoices.view']);
$$;

-- -----------------------------------------------------------------------------
-- 3. staff_has_payments_read_access (20260605180300, 20–35).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.staff_has_payments_read_access()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth_internal.staff_has_membership_permissions(
    ARRAY['invoices.view', 'payments.record']
  );
$$;

-- -----------------------------------------------------------------------------
-- 4. staff_has_services_read_access (20260712090000, 122–138).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.staff_has_services_read_access()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth_internal.staff_has_membership_permissions(
    ARRAY['services.view', 'services.manage', 'invoices.create']
  );
$$;

-- -----------------------------------------------------------------------------
-- 5. staff_has_shifts_manage (20260606180000, 164–180). The get_shift_detail
--    is_read_only consumer (578) follows this helper, so the shift read-only
--    indication now agrees with the caller's current-org membership role.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.staff_has_shifts_manage()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth_internal.staff_has_membership_permissions(ARRAY['shifts.manage']);
$$;

-- -----------------------------------------------------------------------------
-- 6. get_billing_settings (20260605181000, 368–410): invoices.view helper OR
--    payments.record fallback, both org- and membership-role scoped.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.get_billing_settings()
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_allow_partial boolean;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF NOT (
    auth_internal.staff_has_invoices_view_access()
    OR auth_internal.staff_has_membership_permissions(ARRAY['payments.record'])
  ) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view billing settings.');
  END IF;

  SELECT obs.allow_partial_payments
  INTO v_allow_partial
  FROM public.organization_billing_settings obs
  WHERE obs.organization_id = v_org_id;

  IF NOT FOUND THEN
    v_allow_partial := false;
  END IF;

  RETURN public.rpc_success(
    jsonb_build_object('allow_partial_payments', coalesce(v_allow_partial, false))
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 7. list_insurance_providers (20260605230000, 309–359): invoices.view helper
--    OR (invoices.create OR insurance.manage), all org- and membership-role
--    scoped; provider rows stay org-filtered.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.list_insurance_providers(p_only_active boolean DEFAULT true)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_providers jsonb;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF NOT (
    auth_internal.staff_has_invoices_view_access()
    OR auth_internal.staff_has_membership_permissions(
      ARRAY['invoices.create', 'insurance.manage']
    )
  ) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to list insurance providers.');
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', ip.id,
        'name', ip.name,
        'contact_info', ip.contact_info,
        'is_active', ip.is_active
      )
      ORDER BY ip.name
    ),
    '[]'::jsonb
  )
  INTO v_providers
  FROM public.insurance_providers ip
  WHERE ip.organization_id = v_org_id
    AND ip.is_deleted = false
    AND (NOT COALESCE(p_only_active, true) OR ip.is_active = true);

  RETURN public.rpc_success(jsonb_build_object('providers', v_providers));
END;
$$;

-- -----------------------------------------------------------------------------
-- 8. check_patient_duplicates (20260523150000, 237–294):
--    patients.create OR patients.edit, org- and membership-role scoped.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.check_patient_duplicates(
  p_full_name text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_exclude_patient_id uuid DEFAULT NULL
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_candidates jsonb;
BEGIN
  IF NOT auth_internal.staff_has_membership_permissions(
    ARRAY['patients.create', 'patients.edit']
  ) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to check patient duplicates.');
  END IF;

  v_org_id := public.jwt_organization_id();
  IF v_org_id IS NULL THEN
    RETURN public.rpc_error('FORBIDDEN', 'Organization context is required.');
  END IF;

  IF p_exclude_patient_id IS NOT NULL THEN
    PERFORM auth_internal.assert_org_patient(p_exclude_patient_id, false);
  END IF;

  v_candidates := auth_internal.find_patient_duplicate_candidates(
    v_org_id,
    p_full_name,
    p_phone,
    p_date_of_birth,
    p_exclude_patient_id
  );

  RETURN public.rpc_success(jsonb_build_object('candidates', v_candidates));
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM = 'NOT_FOUND' THEN
      RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
    END IF;
    IF SQLERRM = 'PATIENT_ARCHIVED' THEN
      RETURN public.rpc_error('PATIENT_ARCHIVED', 'This patient is archived.');
    END IF;
    RAISE;
END;
$$;

-- -----------------------------------------------------------------------------
-- 9. get_patient_safety_context (20260704120000, 4–134): clinical helper OR
--    patients.view fallback, org- and membership-role scoped.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.get_patient_safety_context(p_patient_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowed boolean;
  v_allergies jsonb;
  v_medications jsonb;
  v_conditions jsonb;
  v_last_visit_id uuid;
  v_last_visit_date date;
  v_last_vitals jsonb;
BEGIN
  v_allowed := auth_internal.staff_has_visit_clinical_access()
    OR auth_internal.staff_has_membership_permissions(ARRAY['patients.view']);

  IF NOT v_allowed THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view patient safety context.');
  END IF;

  BEGIN
    PERFORM auth_internal.assert_patient_branch_scope(p_patient_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Patient was not found.');
      END IF;
      RAISE;
  END;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object('id', pa.id, 'substance', pa.substance, 'reaction', pa.reaction)
      ORDER BY pa.created_at ASC
    ),
    '[]'::jsonb
  )
  INTO v_allergies
  FROM public.patient_allergies pa
  WHERE pa.patient_id = p_patient_id AND pa.is_deleted = false;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', pm.id,
        'name', pm.name,
        'medication_id', pm.medication_id,
        'note', pm.note
      )
      ORDER BY pm.created_at ASC
    ),
    '[]'::jsonb
  )
  INTO v_medications
  FROM public.patient_medications pm
  WHERE pm.patient_id = p_patient_id AND pm.is_deleted = false;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', pcc.id,
        'name', pcc.name,
        'note', pcc.note
      )
      ORDER BY pcc.created_at ASC
    ),
    '[]'::jsonb
  )
  INTO v_conditions
  FROM public.patient_chronic_conditions pcc
  WHERE pcc.patient_id = p_patient_id AND pcc.is_deleted = false;

  SELECT v.id, v.visit_date
  INTO v_last_visit_id, v_last_visit_date
  FROM public.visits v
  WHERE v.patient_id = p_patient_id
    AND v.is_deleted = false
    AND auth_internal.staff_can_access_branch(v.branch_id)
    AND EXISTS (
      SELECT 1 FROM public.visit_vital_signs vvs
      WHERE vvs.visit_id = v.id AND vvs.is_deleted = false
    )
  ORDER BY v.visit_date DESC, v.created_at DESC
  LIMIT 1;

  IF FOUND THEN
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'name', vvs.name,
          'value', vvs.value,
          'unit', vvs.unit
        )
        ORDER BY vvs.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_last_vitals
    FROM public.visit_vital_signs vvs
    WHERE vvs.visit_id = v_last_visit_id AND vvs.is_deleted = false;

    v_last_vitals := jsonb_build_object(
      'visit_id', v_last_visit_id,
      'visit_date', v_last_visit_date,
      'items', COALESCE(v_last_vitals, '[]'::jsonb)
    );
  ELSE
    v_last_vitals := jsonb_build_object(
      'visit_id', NULL,
      'visit_date', NULL,
      'items', '[]'::jsonb
    );
  END IF;

  RETURN public.rpc_success(jsonb_build_object(
    'allergies', COALESCE(v_allergies, '[]'::jsonb),
    'current_medications', COALESCE(v_medications, '[]'::jsonb),
    'chronic_conditions', COALESCE(v_conditions, '[]'::jsonb),
    'last_vitals', v_last_vitals
  ));
END;
$$;

-- -----------------------------------------------------------------------------
-- 10. get_visit (20260707120000, 104–EOF): patients.view fallback reader is
--     org- and membership-role scoped; clinical-child gating still flows
--     through the scoped helpers.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.get_visit(p_visit_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_visit public.visits%ROWTYPE;
  v_note public.visit_clinical_notes%ROWTYPE;
  v_doctor_name text;
  v_has_clinical boolean;
  v_has_patients_view boolean;
  v_payload jsonb;
  v_documentation jsonb;
  v_vital_signs jsonb;
  v_investigations jsonb;
  v_treatment_plans jsonb;
  v_attachments jsonb;
  v_pending_investigations jsonb;
BEGIN
  BEGIN
    v_visit := auth_internal.assert_visit_branch_scope(p_visit_id);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'NOT_FOUND' THEN
        RETURN public.rpc_error('NOT_FOUND', 'Visit was not found.');
      END IF;
      RAISE;
  END;

  v_has_clinical := auth_internal.staff_has_visit_clinical_access();
  v_has_patients_view := auth_internal.staff_has_membership_permissions(
    ARRAY['patients.view']
  );

  IF NOT v_has_clinical AND NOT v_has_patients_view THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view this visit.');
  END IF;

  SELECT sm.full_name INTO v_doctor_name
  FROM public.staff_members sm
  WHERE sm.id = v_visit.doctor_id AND sm.is_deleted = false;

  v_payload := jsonb_build_object(
    'id', v_visit.id,
    'branch_id', v_visit.branch_id,
    'appointment_id', v_visit.appointment_id,
    'patient_id', v_visit.patient_id,
    'doctor_id', v_visit.doctor_id,
    'doctor_name', v_doctor_name,
    'visit_date', v_visit.visit_date,
    'status', v_visit.status::text,
    'updated_at', v_visit.updated_at
  );

  IF v_has_clinical THEN
    SELECT * INTO v_note
    FROM public.visit_clinical_notes vcn
    WHERE vcn.visit_id = p_visit_id AND vcn.is_deleted = false;

    IF FOUND THEN
      v_documentation := jsonb_build_object(
        'complaint', v_note.complaint,
        'history', v_note.history,
        'examination', v_note.examination,
        'diagnosis', v_note.diagnosis,
        'plan', v_note.plan,
        'updated_at', v_note.updated_at
      );
    ELSE
      v_documentation := jsonb_build_object(
        'complaint', '',
        'history', '',
        'examination', '',
        'diagnosis', '',
        'plan', '',
        'updated_at', v_visit.updated_at
      );
    END IF;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', vvs.id,
          'name', vvs.name,
          'value', vvs.value,
          'unit', vvs.unit,
          'predefined_vital_sign_id', vvs.predefined_vital_sign_id
        )
        ORDER BY vvs.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_vital_signs
    FROM public.visit_vital_signs vvs
    WHERE vvs.visit_id = p_visit_id AND vvs.is_deleted = false;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', vi.id,
          'name', vi.name,
          'note', vi.note,
          'investigation_id', vi.investigation_id,
          'result', vi.result,
          'result_recorded_at', vi.result_recorded_at
        )
        ORDER BY vi.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_investigations
    FROM public.visit_investigations vi
    WHERE vi.visit_id = p_visit_id AND vi.is_deleted = false;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', vi.id,
          'name', vi.name,
          'note', vi.note,
          'investigation_id', vi.investigation_id,
          'ordered_visit_id', v_prior.id,
          'ordered_visit_date', v_prior.visit_date,
          'result', vi.result,
          'result_recorded_at', vi.result_recorded_at
        )
        ORDER BY v_prior.visit_date DESC, vi.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_pending_investigations
    FROM public.visit_investigations vi
    JOIN public.visits v_prior ON v_prior.id = vi.visit_id
    WHERE v_prior.patient_id = v_visit.patient_id
      AND v_prior.id <> p_visit_id
      AND v_prior.is_deleted = false
      AND vi.is_deleted = false
      AND vi.result IS NULL
      AND auth_internal.staff_can_access_branch(v_prior.branch_id);

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', tp.id,
          'medication_name', tp.medication_name,
          'medication_id', tp.medication_id,
          'dosage', tp.dosage,
          'frequency', tp.frequency,
          'duration', tp.duration,
          'notes', tp.notes
        )
        ORDER BY tp.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_treatment_plans
    FROM public.treatment_plans tp
    WHERE tp.visit_id = p_visit_id AND tp.is_deleted = false;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', va.id,
          'file_type', va.file_type::text,
          'label', va.label,
          'uploaded_by', va.uploaded_by,
          'uploaded_by_name', uploader.full_name,
          'size_bytes', va.size_bytes,
          'created_at', va.created_at,
          'can_download',
            auth_internal.staff_has_visit_clinical_access()
            OR (
              auth_internal.staff_has_visit_upload_access()
              AND va.uploaded_by = public.jwt_staff_member_id()
            ),
          'can_delete',
            auth_internal.staff_has_visit_clinical_access()
            OR (
              auth_internal.staff_has_visit_upload_access()
              AND va.uploaded_by = public.jwt_staff_member_id()
            )
        )
        ORDER BY va.created_at ASC
      ),
      '[]'::jsonb
    )
    INTO v_attachments
    FROM public.visit_attachments va
    LEFT JOIN public.staff_members uploader ON uploader.id = va.uploaded_by
    WHERE va.visit_id = p_visit_id AND va.is_deleted = false;

    v_payload := v_payload || jsonb_build_object(
      'documentation', v_documentation,
      'vital_signs', COALESCE(v_vital_signs, '[]'::jsonb),
      'investigations', COALESCE(v_investigations, '[]'::jsonb),
      'treatment_plans', COALESCE(v_treatment_plans, '[]'::jsonb),
      'attachments', COALESCE(v_attachments, '[]'::jsonb),
      'pending_investigations', COALESCE(v_pending_investigations, '[]'::jsonb)
    );
  END IF;

  RETURN public.rpc_success(v_payload);
END;
$$;

-- -----------------------------------------------------------------------------
-- 11. get_service (20260712091000, 9–85): services.view OR services.manage.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.get_service(p_service_id uuid)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_service public.services%ROWTYPE;
  v_branches jsonb;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF NOT auth_internal.staff_has_membership_permissions(
    ARRAY['services.view', 'services.manage']
  ) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view the service catalog.');
  END IF;

  IF p_service_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service ID is required.');
  END IF;

  SELECT *
  INTO v_service
  FROM public.services s
  WHERE s.id = p_service_id
    AND s.organization_id = v_org_id
    AND s.is_deleted = false;

  IF NOT FOUND THEN
    RETURN public.rpc_error('NOT_FOUND', 'The requested service was not found.');
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'service_branch_id', sb.id,
        'branch_id', sb.branch_id,
        'status', sb.status::text,
        'price_override', sb.price_override,
        'promotion_price', sb.promotion_price,
        'promotion_start_date', sb.promotion_start_date,
        'promotion_end_date', sb.promotion_end_date,
        'updated_at', sb.updated_at
      )
      ORDER BY sb.branch_id
    ),
    '[]'::jsonb
  )
  INTO v_branches
  FROM public.service_branches sb
  WHERE sb.service_id = p_service_id
    AND sb.is_deleted = false
    AND sb.branch_id = ANY (public.jwt_branch_ids());

  RETURN public.rpc_success(
    jsonb_build_object(
      'service', jsonb_build_object(
        'id', v_service.id,
        'name', v_service.name,
        'default_price', v_service.default_price,
        'global_status', v_service.global_status::text,
        'created_at', v_service.created_at,
        'updated_at', v_service.updated_at
      ),
      'branches', v_branches
    )
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 12. resolve_effective_service_price_rpc (20260712091000, 198–264):
--     services.view OR services.manage OR invoices.create.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.resolve_effective_service_price_rpc(
  p_service_id uuid,
  p_branch_id uuid,
  p_on_date date DEFAULT current_date
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_resolution jsonb;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF NOT auth_internal.staff_has_membership_permissions(
    ARRAY['services.view', 'services.manage', 'invoices.create']
  ) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view service pricing.');
  END IF;

  IF p_service_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Service ID is required.');
  END IF;

  IF p_branch_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Branch ID is required.');
  END IF;

  IF NOT (p_branch_id = ANY (public.jwt_branch_ids())) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have access to this branch.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.branches b
    WHERE b.id = p_branch_id
      AND b.organization_id = v_org_id
      AND b.is_deleted = false
  ) THEN
    RETURN public.rpc_error('BRANCH_NOT_IN_ORG', 'The branch is not in your organization.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.services s
    WHERE s.id = p_service_id
      AND s.organization_id = v_org_id
      AND s.is_deleted = false
  ) THEN
    RETURN public.rpc_error('NOT_FOUND', 'The requested service was not found.');
  END IF;

  v_resolution := auth_internal.resolve_effective_service_price(p_service_id, p_branch_id, p_on_date);

  RETURN public.rpc_success(v_resolution);
END;
$$;

-- -----------------------------------------------------------------------------
-- 13. search_eligible_services (20260712091000, 285–375):
--     services.view OR services.manage OR invoices.create.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.search_eligible_services(
  p_branch_id uuid,
  p_query text DEFAULT '',
  p_on_date date DEFAULT current_date,
  p_limit int DEFAULT 20
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_limit int;
  v_query text := coalesce(p_query, '');
  v_items jsonb;
BEGIN
  v_org_id := public.jwt_organization_id();

  IF NOT auth_internal.staff_has_membership_permissions(
    ARRAY['services.view', 'services.manage', 'invoices.create']
  ) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to search services.');
  END IF;

  IF p_branch_id IS NULL THEN
    RETURN public.rpc_error('INVALID_INPUT', 'Branch ID is required.');
  END IF;

  IF NOT (p_branch_id = ANY (public.jwt_branch_ids())) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have access to this branch.');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.branches b
    WHERE b.id = p_branch_id
      AND b.organization_id = v_org_id
      AND b.is_deleted = false
  ) THEN
    RETURN public.rpc_error('BRANCH_NOT_IN_ORG', 'The branch is not in your organization.');
  END IF;

  v_limit := greatest(1, least(coalesce(p_limit, 20), 50));

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'service_id', ranked.service_id,
        'name', ranked.name,
        'unit_price', ranked.unit_price,
        'applied_rule', ranked.applied_rule,
        'on_promotion', ranked.on_promotion
      )
      ORDER BY ranked.name
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM (
    SELECT
      s.id AS service_id,
      s.name,
      res.resolution ->> 'unit_price' AS unit_price,
      res.resolution ->> 'applied_rule' AS applied_rule,
      (res.resolution ->> 'applied_rule') = 'promo' AS on_promotion
    FROM public.services s
    JOIN public.service_branches sb
      ON sb.service_id = s.id
      AND sb.branch_id = p_branch_id
      AND sb.is_deleted = false
    CROSS JOIN LATERAL (
      SELECT auth_internal.resolve_effective_service_price(s.id, p_branch_id, p_on_date) AS resolution
    ) res
    WHERE s.organization_id = v_org_id
      AND s.is_deleted = false
      AND (res.resolution ->> 'eligible')::boolean = true
      AND s.name ILIKE '%' || v_query || '%'
    ORDER BY s.name
    LIMIT v_limit
  ) AS ranked;

  RETURN public.rpc_success(jsonb_build_object('items', v_items));
END;
$$;

-- -----------------------------------------------------------------------------
-- 14. list_services (20260712091000, 399–553): services.view OR
--     services.manage; rows stay org-filtered so no B records return.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth_internal.list_services(
  p_query text DEFAULT NULL,
  p_global_status text DEFAULT NULL,
  p_branch_id uuid DEFAULT NULL,
  p_limit int DEFAULT 25,
  p_offset int DEFAULT 0
)
RETURNS public.rpc_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_limit int;
  v_offset int;
  v_status public.service_global_status;
  v_total int;
  v_items jsonb;
  v_query text := NULLIF(btrim(p_query), '');
BEGIN
  v_org_id := public.jwt_organization_id();

  IF NOT auth_internal.staff_has_membership_permissions(
    ARRAY['services.view', 'services.manage']
  ) THEN
    RETURN public.rpc_error('FORBIDDEN', 'You do not have permission to view the service catalog.');
  END IF;

  IF p_global_status IS NOT NULL AND btrim(p_global_status) <> '' THEN
    BEGIN
      v_status := p_global_status::public.service_global_status;
    EXCEPTION
      WHEN invalid_text_representation THEN
        RETURN public.rpc_error('INVALID_INPUT', 'Global status must be active or inactive.');
    END;
  END IF;

  IF p_branch_id IS NOT NULL THEN
    IF NOT (p_branch_id = ANY (public.jwt_branch_ids())) THEN
      RETURN public.rpc_error('FORBIDDEN', 'You do not have access to this branch.');
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.branches b
      WHERE b.id = p_branch_id
        AND b.organization_id = v_org_id
        AND b.is_deleted = false
    ) THEN
      RETURN public.rpc_error('BRANCH_NOT_IN_ORG', 'The branch is not in your organization.');
    END IF;
  END IF;

  v_limit := greatest(1, least(coalesce(p_limit, 25), 100));
  v_offset := greatest(coalesce(p_offset, 0), 0);

  SELECT count(*)::int
  INTO v_total
  FROM public.services s
  WHERE s.organization_id = v_org_id
    AND s.is_deleted = false
    AND (v_query IS NULL OR s.name ILIKE '%' || v_query || '%')
    AND (p_global_status IS NULL OR btrim(p_global_status) = '' OR s.global_status = v_status)
    AND (
      p_branch_id IS NULL
      OR EXISTS (
        SELECT 1
        FROM public.service_branches sb
        WHERE sb.service_id = s.id
          AND sb.branch_id = p_branch_id
          AND sb.is_deleted = false
      )
    );

  SELECT COALESCE(
    jsonb_agg(
      jsonb_strip_nulls(
        jsonb_build_object(
          'service_id', page.service_id,
          'name', page.name,
          'default_price', to_char(page.default_price, 'FM9999999990.00'),
          'global_status', page.global_status::text,
          'assigned_branch_count', page.assigned_branch_count,
          'updated_at', page.updated_at,
          'branch_summary', page.branch_summary
        )
      )
      ORDER BY page.name
    ),
    '[]'::jsonb
  )
  INTO v_items
  FROM (
    SELECT
      s.id AS service_id,
      s.name,
      s.default_price,
      s.global_status,
      s.updated_at,
      (
        SELECT count(*)::int
        FROM public.service_branches sb
        WHERE sb.service_id = s.id
          AND sb.is_deleted = false
      ) AS assigned_branch_count,
      CASE
        WHEN p_branch_id IS NULL THEN NULL
        ELSE (
          SELECT jsonb_build_object(
            'status', sb.status::text,
            'effective_price', res.resolution ->> 'unit_price',
            'on_promotion', (res.resolution ->> 'applied_rule') = 'promo'
          )
          FROM public.service_branches sb
          CROSS JOIN LATERAL (
            SELECT auth_internal.resolve_effective_service_price(s.id, p_branch_id, current_date) AS resolution
          ) res
          WHERE sb.service_id = s.id
            AND sb.branch_id = p_branch_id
            AND sb.is_deleted = false
        )
      END AS branch_summary
    FROM public.services s
    WHERE s.organization_id = v_org_id
      AND s.is_deleted = false
      AND (v_query IS NULL OR s.name ILIKE '%' || v_query || '%')
      AND (p_global_status IS NULL OR btrim(p_global_status) = '' OR s.global_status = v_status)
      AND (
        p_branch_id IS NULL
        OR EXISTS (
          SELECT 1
          FROM public.service_branches sb
          WHERE sb.service_id = s.id
            AND sb.branch_id = p_branch_id
            AND sb.is_deleted = false
        )
      )
    ORDER BY s.name
    LIMIT v_limit
    OFFSET v_offset
  ) AS page;

  RETURN public.rpc_success(jsonb_build_object('total', v_total, 'items', v_items));
END;
$$;
