-- project_url lived in Vault beside push_fn_secret, but it is not a secret:
-- it is the project's public API origin, the same string every shipped
-- binary contains. Encrypting it misrepresents what is actually sensitive
-- here, and decrypting it on every check-in cost 8.1µs against 2.1µs for a
-- plain read (measured, 20k iterations). The whole push trigger is ~64µs a
-- row, so the speed is a rounding error — the reason to do it is that a
-- reader should be able to tell which of these two values matters.
--
-- The URL still stays out of this migration: the repo is public and the
-- value carries the project ref, so it is inserted per project, once (see
-- README "Push notifications").
--
-- ALTER DATABASE … SET would have been cheaper still, since a GUC read is
-- free — but Postgres refuses to set a custom parameter that way without
-- superuser, which Supabase's `postgres` role is not. Verified, not assumed.
--
-- No Vault fallback on purpose. An unconfigured project reads NULL here and
-- the triggers already treat that as "push isn't set up" and no-op silently,
-- which is exactly what an empty Vault did. A coalesce() to Vault would have
-- worked (it does short-circuit) but cost 2.8µs of the 6µs saved, to cover a
-- window of seconds between this migration and the insert that follows it.

create table public.push_config (
  -- Exactly one row, forever: `id` can only ever be true.
  id boolean primary key default true check (id),
  project_url text not null check (project_url ~ '^https://')
);

-- Sealed like every other table the triggers own: RLS on, no policies, no
-- grants. It holds no secret, but nothing outside these triggers reads it.
alter table public.push_config enable row level security;
revoke all on public.push_config from anon, authenticated;

-- Both trigger functions, unchanged except for where the URL comes from.

create or replace function public.notify_checkin_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  -- How long after a push the same author's edits stay silent.
  cooldown constant interval := interval '30 minutes';
  is_edit boolean := tg_op = 'UPDATE';
  base_url text;
  fn_secret text;
begin
  if is_edit then
    -- Only a real mood change is news; the client rewrites updated_at on
    -- every save.
    if new.emoji is not distinct from old.emoji then
      return new;
    end if;
    -- ...and only for a check-in that is plausibly today. `day` is the
    -- author's LOCAL date, so allow a day either side of the server's UTC
    -- one; anything older is a backfill, not a mood change.
    if new.day not between current_date - 1 and current_date + 1 then
      return new;
    end if;
  end if;

  select project_url into base_url from push_config;
  select decrypted_secret into fn_secret
    from vault.decrypted_secrets where name = 'push_fn_secret';
  if base_url is null or fn_secret is null then
    return new;
  end if;

  -- Claiming the slot and recording it are the same statement, so two
  -- concurrent edits can't both decide they're allowed to push. No row
  -- updated (the cooldown hasn't elapsed) means: stay quiet.
  insert into checkin_push_log as l (user_id, last_push_at)
  values (new.user_id, now())
  on conflict (user_id) do update set last_push_at = now()
    where not is_edit or l.last_push_at <= now() - cooldown;
  if not found then
    return new;
  end if;

  perform net.http_post(
    url := base_url || '/functions/v1/push-checkin',
    body := jsonb_build_object(
      'user_id', new.user_id,
      'kind', case when is_edit then 'update' else 'new' end
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', fn_secret
    )
  );
  return new;
exception when others then
  -- Push plumbing must never block a check-in.
  return new;
end;
$$;
revoke execute on function public.notify_checkin_push() from public, anon, authenticated;

create or replace function public.announce_new_joins()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  claim record;
  base_url text;
  fn_secret text;
begin
  select project_url into base_url from push_config;
  select decrypted_secret into fn_secret
    from vault.decrypted_secrets where name = 'push_fn_secret';

  for claim in
    with mutual as (
      -- Only pairs the inserted rows just completed in BOTH directions. A
      -- one-way link must not reveal that somebody joined.
      select i.owner_id as a, i.user_id as b
      from inserted i
      join contact_links back
        on back.owner_id = i.user_id and back.user_id = i.owner_id
    ),
    -- Usually only one side is new, but two friends who sign up in the same
    -- week should each hear about the other.
    directed as (
      select distinct a as recipient, b as newcomer from mutual
      union
      select distinct b, a from mutual
    ),
    claimed as (
      insert into join_announcements (recipient_id, new_user_id)
      select d.recipient, d.newcomer
      from directed d
      join profiles p on p.id = d.newcomer
      where p.created_at > now() - public.join_announcement_window()
      on conflict do nothing
      returning recipient_id, new_user_id
    )
    select recipient_id, new_user_id from claimed
  loop
    if base_url is not null and fn_secret is not null then
      perform net.http_post(
        url := base_url || '/functions/v1/push-joined',
        body := jsonb_build_object(
          'recipient_id', claim.recipient_id,
          'new_user_id', claim.new_user_id
        ),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-push-secret', fn_secret
        )
      );
    end if;
  end loop;

  return null;
exception when others then
  -- Push plumbing must never block a sync or a signup.
  return null;
end;
$$;
revoke execute on function public.announce_new_joins() from public, anon, authenticated;
