-- The check-in push now carries the mood itself, so the recipient's
-- notification extension can write it straight into the sky the widgets
-- read from the App Group. Before this it could only mark that sky as
-- behind the truth, which sent every widget to the network — and a widget
-- refreshes on a locked phone with the radio asleep, where the round trip
-- is both the slow part and the part that fails. The lock screen is the
-- one surface looked at inside that window, so it was the one seen to lag.
--
-- The mood is readable by every recipient already: the trigger only pushes
-- to mutual contacts, who can select the same row through board_today. What
-- is new is that it passes through APNs, which is a deliberate trade — see
-- CLAUDE.md, "Push notifications".
--
-- Only the body of the http_post changes; everything else is the function
-- as 20260919060000 left it.

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
      'kind', case when is_edit then 'update' else 'new' end,
      'emoji', new.emoji
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
