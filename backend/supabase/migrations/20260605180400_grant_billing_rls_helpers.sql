-- Grant authenticated role EXECUTE on billing RLS helper functions.
GRANT EXECUTE ON FUNCTION auth_internal.staff_has_invoices_view_access () TO authenticated;

GRANT EXECUTE ON FUNCTION auth_internal.staff_has_payments_read_access () TO authenticated;