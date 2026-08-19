-- Push notifications when a friend checks in. An AFTER INSERT trigger on
-- checkins calls the push-checkin Edge Function through pg_net; the function
-- fans out APNs alerts to the author's mutual contacts' devices. INSERT only:
-- re-picking today's emoji is an upsert UPDATE, so edits never re-notify.
--
-- The trigger reads the function URL and shared secret from Vault (this repo
-- is public, so the project ref stays out of migrations). Configure once per
-- project — see README "Push notifications". Without the Vault secrets the
-- trigger is a silent no-op, so check-ins keep working on projects (and local
-- dev) where push isn't set up.

create extension if not exists pg_net;

-- ---------------------------------------------------------------------------
-- Device tokens
-- ---------------------------------------------------------------------------

create table public.device_tokens (
  -- APNs device token, lowercase hex. Primary key: a physical device keeps
  -- one row, and re-registration by a different account takes the row over.
  token text primary key check (token ~ '^[0-9a-f]{16,200}$'),
  user_id uuid not null references public.profiles on delete cascade,
  -- Debug builds run against APNs sandbox, Release against production; a
  -- token is only valid on the environment it was issued for.
  sandbox boolean not null default false,
  updated_at timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);

-- Sealed like contact_links: RLS with no policies + revoked grants. Clients
-- go through the register/unregister functions below.
alter table public.device_tokens enable row level security;
revoke all on public.device_tokens from anon, authenticated;

create function public.register_device_token(device_token text, is_sandbox boolean)
returns void
language sql
security definer
set search_path = public
as $$
  insert into device_tokens (token, user_id, sandbox)
  values (lower(device_token), auth.uid(), is_sandbox)
  on conflict (token) do update
    set user_id = excluded.user_id,
        sandbox = excluded.sandbox,
        updated_at = now();
$$;
revoke execute on function public.register_device_token(text, boolean) from public, anon;
grant execute on function public.register_device_token(text, boolean) to authenticated;

create function public.unregister_device_token(device_token text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from device_tokens
  where token = lower(device_token) and user_id = auth.uid();
$$;
revoke execute on function public.unregister_device_token(text) from public, anon;
grant execute on function public.unregister_device_token(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Recipient fan-out (service role only — used by the push-checkin function)
-- ---------------------------------------------------------------------------

-- Devices of everyone mutual with the author: same join shape as
-- my_mutuals(), keyed to the author instead of auth.uid().
create function public.checkin_push_recipients(author uuid)
returns table (token text, sandbox boolean)
language sql
stable
security definer
set search_path = public
as $$
  select dt.token, dt.sandbox
  from contact_links mine
  join contact_links back
    on back.owner_id = mine.user_id and back.user_id = mine.owner_id
  join device_tokens dt on dt.user_id = mine.user_id
  where mine.owner_id = author;
$$;
revoke execute on function public.checkin_push_recipients(uuid) from public, anon, authenticated;
grant execute on function public.checkin_push_recipients(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Trigger: first check-in of the day -> push-checkin Edge Function
-- ---------------------------------------------------------------------------

create function public.notify_checkin_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  base_url text;
  fn_secret text;
begin
  select decrypted_secret into base_url
    from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into fn_secret
    from vault.decrypted_secrets where name = 'push_fn_secret';
  if base_url is null or fn_secret is null then
    return new;
  end if;
  perform net.http_post(
    url := base_url || '/functions/v1/push-checkin',
    body := jsonb_build_object('user_id', new.user_id),
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

create trigger on_checkin_insert_push
  after insert on public.checkins
  for each row execute function public.notify_checkin_push();
