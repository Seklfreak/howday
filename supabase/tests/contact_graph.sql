-- Contact-graph regression tests, run against the scratch database CI builds
-- by applying every migration from zero. Plain SQL assertions rather than a
-- test framework, in the spirit of scripts/rls-proof.sh.
--
-- The case that matters is the signup race (steps 1-4): a sync that lands
-- BEFORE the contact signs up used to discard the hash, leaving both boards
-- empty until the client's 24h staleness timer expired. It shipped silently
-- because every test created its users first and synced afterwards, which is
-- the one ordering the bug does not have.
--
--   docker exec -i supabase_db_howday psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/contact_graph.sql

\set ON_ERROR_STOP on
begin;

do $$
declare
  a uuid := '11111111-1111-1111-1111-111111111111';
  b uuid := '22222222-2222-2222-2222-222222222222';
  a_phone text := '15005550001';
  b_phone text := '15005550002';
  a_hash text := encode(digest('15005550001', 'sha256'), 'hex');
  b_hash text := encode(digest('15005550002', 'sha256'), 'hex');
  instance uuid := '00000000-0000-0000-0000-000000000000';
  linked integer;
begin
  insert into auth.users (id, instance_id, aud, role, phone)
  values (a, instance, 'authenticated', 'authenticated', a_phone);

  -- 1. A's address book already holds B's number, but B has not signed up.
  linked := public.replace_contact_hashes(a, array[b_hash]);
  if linked <> 0 then
    raise exception 'sync before signup should link nobody, linked %', linked;
  end if;

  -- 2. The hash is kept anyway — that is what makes the backfill possible.
  if not exists (
    select 1 from public.contact_hashes where owner_id = a and phone_hash = b_hash
  ) then
    raise exception 'sync did not store the unmatched hash';
  end if;

  -- 3. B signs up. The trigger owes A the incoming link, without A re-syncing.
  insert into auth.users (id, instance_id, aud, role, phone)
  values (b, instance, 'authenticated', 'authenticated', b_phone);
  if not exists (
    select 1 from public.contact_links where owner_id = a and user_id = b
  ) then
    raise exception 'signup did not backfill the link from an earlier sync';
  end if;

  -- 4. One-way still grants nothing: the model's core property.
  if public.are_mutual_contacts(a, b) then
    raise exception 'a one-way link must not be mutual';
  end if;

  -- 5. B's own sign-in sync closes the loop.
  linked := public.replace_contact_hashes(b, array[a_hash]);
  if linked <> 1 then
    raise exception 'B should link A, linked %', linked;
  end if;
  if not public.are_mutual_contacts(a, b) then
    raise exception 'links in both directions must be mutual';
  end if;

  -- 6. Nobody is their own contact, from either direction.
  perform public.replace_contact_hashes(a, array[a_hash, b_hash]);
  if exists (select 1 from public.contact_links where owner_id = user_id) then
    raise exception 'a self-link was created';
  end if;

  -- 7. Deleting a contact must drop the stored hash too, or they would
  -- re-link on a future signup after being deliberately removed.
  perform public.replace_contact_hashes(a, array[]::text[]);
  if exists (select 1 from public.contact_hashes where owner_id = a) then
    raise exception 'unsync left hashes behind';
  end if;
  if public.are_mutual_contacts(a, b) then
    raise exception 'unsync did not end mutuality';
  end if;

  raise notice 'contact_graph: all assertions passed';
end;
$$;

rollback;
