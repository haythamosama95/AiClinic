-- Deny anonymous / PUBLIC execute on the chief-complaint RPC. GRANT to
-- authenticated alone does not revoke PostgreSQL's default EXECUTE TO PUBLIC.

REVOKE EXECUTE ON FUNCTION public.get_visit_chief_complaint(uuid) FROM PUBLIC, anon;
