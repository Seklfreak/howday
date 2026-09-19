-- A contact who signs up AFTER your last sync stays invisible to you, and
-- you to them: sync-contacts resolves your uploaded hashes against profiles
-- as they exist at upload time and discards the rest, so the link you would
-- have got is simply never created. Worse, the race is the *normal* flow —
-- adding their number to your address book is what triggers your sync, so
-- your sync runs before they sign up, and afterwards your fingerprint is
-- current so the client skips every further upload until its 24h staleness
-- timer expires. Observed in production: one user's sync landed 5 minutes
-- before their friend's signup, and both boards stayed empty for a day.
--
-- Fix: keep the uploaded hashes, so a new profile can look backwards and
-- create its own incoming links. That is a real privacy trade-off, made
-- deliberately: the server now retains hashes of numbers belonging to people
-- who are NOT users, where before they were matched and discarded. What
-- makes it acceptable — they are SHA-256 hashes, never numbers; the table is
-- sealed exactly like contact_links (RLS on with no policies, all grants
-- revoked, reachable only from service-role functions); and a sync replaces
-- the owner's whole set, so deleting a contact still deletes what we hold.

create table public.contact_hashes (
  owner_id uuid not null references public.profiles on delete cascade,
  phone_hash text not null,
  primary key (owner_id, phone_hash)
);
-- The signup backfill asks "who already uploaded this one hash?", which is
-- the opposite direction from the primary key.
create index contact_hashes_hash_idx on public.contact_hashes (phone_hash);

alter table public.contact_hashes enable row level security;
revoke all on public.contact_hashes from anon, authenticated;

-- Supersedes replace_contact_links + match_phone_hashes: storing the hashes
-- makes the links derivable, so one call does both and they cannot drift.
-- Same advisory lock key as the function it replaces — concurrent syncs for
-- one owner still queue instead of colliding on the primary key.
create function public.replace_contact_hashes(owner uuid, hashes text[])
returns integer
language plpgsql
set search_path = public
as $$
declare
  linked integer;
begin
  perform pg_advisory_xact_lock(
    hashtextextended('contact_links:' || owner::text, 0)
  );

  delete from contact_hashes where owner_id = owner;
  insert into contact_hashes (owner_id, phone_hash)
  select distinct owner, h from unnest(hashes) as h;

  delete from contact_links where owner_id = owner;
  insert into contact_links (owner_id, user_id)
  select owner, p.id
  from profiles p
  where p.phone_hash = any(hashes)
    and p.id <> owner;
  get diagnostics linked = row_count;

  return linked;
end;
$$;

revoke execute on function public.replace_contact_hashes(uuid, text[])
  from public, anon, authenticated;
grant execute on function public.replace_contact_hashes(uuid, text[])
  to service_role;

-- The other half of the race: a profile created now links back to everyone
-- who already holds its hash. Paired with the client syncing at sign-in
-- rather than at first check-in, both directions exist within seconds of
-- signup instead of within a day.
--
-- Runs inside handle_new_user's transaction, so it must not be able to fail
-- a signup: the only write is guarded by on conflict, and an owner whose
-- link already exists is a no-op.
create function public.link_new_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into contact_links (owner_id, user_id)
  select ch.owner_id, new.id
  from contact_hashes ch
  where ch.phone_hash = new.phone_hash
    and ch.owner_id <> new.id
  on conflict do nothing;
  return new;
end;
$$;

create trigger link_new_profile_after_insert
  after insert on public.profiles
  for each row execute function public.link_new_profile();

-- Both are unreachable now that sync-contacts calls replace_contact_hashes.
-- No backfill is possible for either: nobody's hashes were ever stored, so
-- existing users start contributing to the backfill from their next sync.
drop function public.replace_contact_links(uuid, uuid[]);
drop function public.match_phone_hashes(text[]);
