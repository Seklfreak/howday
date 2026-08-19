-- Contacts-based social graph. The friendship request/accept flow, invite
-- codes, and display names are gone: each user's hashed address book is
-- synced into contact_links by the sync-contacts Edge Function (service role
-- only), and check-in visibility requires the link in BOTH directions.
-- Names and photos are rendered client-side from the viewer's own address
-- book, so the server stores no names at all.

create table public.contact_links (
  owner_id uuid not null references public.profiles on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, user_id),
  check (owner_id <> user_id)
);
create index contact_links_user_idx on public.contact_links (user_id);

-- Only the sync-contacts Edge Function (service role) touches this table:
-- RLS enabled with no policies + revoked grants = invisible to clients.
alter table public.contact_links enable row level security;
revoke all on public.contact_links from anon, authenticated;

create function public.are_mutual_contacts(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from contact_links where owner_id = a and user_id = b)
     and exists (select 1 from contact_links where owner_id = b and user_id = a);
$$;

-- The caller's mutual contacts. phone_hash is included so the client can map
-- each friend onto the local address book for their name and photo — by
-- definition of mutuality the caller already has that number saved, so
-- nothing new is revealed.
create function public.my_mutuals()
returns table (id uuid, phone_hash text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.phone_hash
  from contact_links mine
  join contact_links back
    on back.owner_id = mine.user_id and back.user_id = mine.owner_id
  join profiles p on p.id = mine.user_id
  where mine.owner_id = auth.uid();
$$;
revoke execute on function public.my_mutuals() from public, anon;
grant execute on function public.my_mutuals() to authenticated;

-- Rewire check-in visibility before dropping the old machinery it replaces.
drop policy checkins_select on public.checkins;
create policy checkins_select on public.checkins
  for select using (user_id = auth.uid() or are_mutual_contacts(auth.uid(), user_id));

-- No client code reads or writes profiles anymore (names come from the
-- address book, reminders are device-local) — lock the table down entirely.
drop policy profiles_select on public.profiles;
drop policy profiles_update on public.profiles;
revoke all on public.profiles from anon, authenticated;

drop function public.redeem_invite(text);
drop function public.are_friends(uuid, uuid);
drop function public.has_relationship(uuid, uuid);
drop table public.friendships;

alter table public.profiles
  drop column display_name,
  drop column invite_code,
  drop column reminder_time;

-- match_phone_hashes returned display_name; recreate it without (Postgres
-- doesn't track column references inside sql function bodies, so the drop
-- above would otherwise leave it broken at call time).
drop function public.match_phone_hashes(text[]);
create function public.match_phone_hashes(hashes text[])
returns table (id uuid, phone_hash text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.phone_hash
  from profiles p
  where p.phone_hash = any(hashes)
$$;
revoke execute on function public.match_phone_hashes(text[]) from public, anon, authenticated;
grant execute on function public.match_phone_hashes(text[]) to service_role;
