-- Supabase preinstalls pgcrypto in the `extensions` schema, so the signup
-- trigger's pinned search_path of `public` couldn't resolve digest() at
-- runtime ("Database error saving new user" on any phone signup).
alter function public.handle_new_user() set search_path = public, extensions;
