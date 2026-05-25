-- Fix 34: Set search_path on normalize_username and assert_valid_username.
-- Addresses Supabase security advisor rule 0011 (mutable search_path).

ALTER FUNCTION auth_internal.normalize_username(text) SET search_path = '';
ALTER FUNCTION auth_internal.assert_valid_username(text) SET search_path = '';
