-- Notify on mood *edits*, not just the first check-in of the day. Re-picking
-- today's emoji is an upsert UPDATE, so the INSERT-only trigger stayed quiet
-- and friends never learned the mood had changed.
--
-- Edits are cheap to make (one tap) and would otherwise be a spam vector, so
-- pushes are rate limited per author: an edit only notifies if the author's
-- last push was more than the cooldown ago. Inserts always push — there is
-- at most one per user per day (unique (user_id, day)), and the daily
-- "friend checked in" alert must not be swallowed by an edit made minutes
-- earlier on the other side of midnight.

-- ---------------------------------------------------------------------------
-- Rate-limit state
-- ---------------------------------------------------------------------------

-- Sealed like device_tokens/contact_links: RLS on, no policies, no grants.
-- Nothing outside the trigger reads or writes it, and a client that could
-- would be able to reset its own cooldown.
create table public.checkin_push_log (
  user_id uuid primary key references public.profiles on delete cascade,
  last_push_at timestamptz not null default now()
);
alter table public.checkin_push_log enable row level security;
revoke all on public.checkin_push_log from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Trigger: check-in inserted, or today's mood changed -> push-checkin
-- ---------------------------------------------------------------------------

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

  select decrypted_secret into base_url
    from vault.decrypted_secrets where name = 'project_url';
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

drop trigger on_checkin_insert_push on public.checkins;
create trigger on_checkin_push
  after insert or update of emoji on public.checkins
  for each row execute function public.notify_checkin_push();
