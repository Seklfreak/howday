-- Moodring initial schema: profiles, friendships, checkins, RLS.
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null default '',
  -- sha256 hex of auth.users.phone as stored by Supabase (E.164 WITHOUT the
  -- leading +). Contact matching joins against this; clients must hash the
  -- same form. Never readable by clients (see column grants below).
  phone_hash text unique not null,
  invite_code text unique not null default encode(gen_random_bytes(4), 'hex'),
  reminder_time time,
  created_at timestamptz not null default now()
);

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester uuid not null references public.profiles on delete cascade,
  addressee uuid not null references public.profiles on delete cascade,
  status text not null check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  check (requester <> addressee)
);

-- One row per pair regardless of direction.
create unique index friendships_pair_idx
  on public.friendships (least(requester, addressee), greatest(requester, addressee));

create table public.checkins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles on delete cascade,
  -- The user's LOCAL date, computed client-side; unique below enforces one
  -- check-in per (their) day. Edit-until-midnight is enforced client-side.
  day date not null,
  mood smallint not null check (mood between 1 and 5),
  emoji text,
  note text check (char_length(note) <= 140),
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique (user_id, day)
);

-- ---------------------------------------------------------------------------
-- Signup trigger: create the profile row when a phone user registers
-- ---------------------------------------------------------------------------

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.phone is not null then
    insert into public.profiles (id, phone_hash)
    values (new.id, encode(digest(new.phone, 'sha256'), 'hex'));
  end if;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Helper functions (security definer so policies don't recurse)
-- ---------------------------------------------------------------------------

create function public.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from friendships
    where status = 'accepted'
      and ((requester = a and addressee = b) or (requester = b and addressee = a))
  );
$$;

-- Any relationship (pending or accepted) — used for profile visibility so
-- you can see the name of someone who sent you a request.
create function public.has_relationship(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from friendships
    where (requester = a and addressee = b) or (requester = b and addressee = a)
  );
$$;

-- Invite-link redemption: creates a pending request to the code's owner.
-- Security definer because the caller can't read the target profile yet.
create function public.redeem_invite(code text)
returns table (friend_id uuid, friend_name text)
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.profiles;
begin
  select * into target from profiles where invite_code = lower(trim(code));
  if target.id is null then
    raise exception 'invalid invite code';
  end if;
  if target.id = auth.uid() then
    raise exception 'cannot friend yourself';
  end if;
  insert into friendships (requester, addressee, status)
  values (auth.uid(), target.id, 'pending')
  on conflict do nothing;
  return query select target.id, target.display_name;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.checkins enable row level security;

create policy profiles_select on public.profiles
  for select using (id = auth.uid() or has_relationship(auth.uid(), id));

create policy profiles_update on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

create policy friendships_select on public.friendships
  for select using (auth.uid() in (requester, addressee));

create policy friendships_insert on public.friendships
  for insert with check (requester = auth.uid() and status = 'pending');

-- Only the addressee may accept, and only from pending.
create policy friendships_update on public.friendships
  for update using (addressee = auth.uid() and status = 'pending')
  with check (addressee = auth.uid() and status = 'accepted');

-- Either side can unfriend / withdraw / decline.
create policy friendships_delete on public.friendships
  for delete using (auth.uid() in (requester, addressee));

create policy checkins_select on public.checkins
  for select using (user_id = auth.uid() or are_friends(auth.uid(), user_id));

create policy checkins_insert on public.checkins
  for insert with check (user_id = auth.uid());

create policy checkins_update on public.checkins
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Column-level grants. phone_hash is brute-forceable (phone numbers are a
-- small space), so clients never get the column — only the service-role
-- matching Edge Function may read it. No client deletes on checkins.
-- ---------------------------------------------------------------------------

revoke all on public.profiles from anon, authenticated;
revoke all on public.friendships from anon;
revoke all on public.checkins from anon;

grant select (id, display_name, invite_code, reminder_time, created_at)
  on public.profiles to authenticated;
grant update (display_name, reminder_time)
  on public.profiles to authenticated;
grant select, insert, update, delete on public.friendships to authenticated;
revoke delete on public.checkins from authenticated;
