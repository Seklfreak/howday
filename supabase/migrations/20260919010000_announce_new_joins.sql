-- "Someone in your contacts just joined Howday": a push to the people a new
-- user becomes MUTUAL with, once each.
--
-- Mutual, not merely linked. A one-way link must keep granting nothing, and
-- that includes the fact that somebody signed up: the newcomer has not put
-- the recipient in their address book yet, so telling the recipient would
-- announce the newcomer's membership to someone they never reciprocated.
-- Mutuality is therefore the trigger condition, which in practice means the
-- newcomer's first sync — the signup backfill has already created the
-- incoming half by then (see backfill_links_on_signup).
--
-- The alert text carries no name. The server stores none, and the board is
-- where the newcomer gets a first name and a photo, resolved from the
-- viewer's own address book.

-- One announcement per (recipient, newcomer) pair, ever. Not merely tidiness:
-- replace_contact_hashes deletes and re-inserts an owner's whole link set on
-- every sync, so the trigger below sees every existing friendship again on
-- each upload. This table is what makes that idempotent.
create table public.join_announcements (
  recipient_id uuid not null references public.profiles on delete cascade,
  new_user_id uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (recipient_id, new_user_id)
);

alter table public.join_announcements enable row level security;
revoke all on public.join_announcements from anon, authenticated;

-- How recently a profile must have been created to count as "just joined".
-- Adding a long-standing user to your contacts makes you mutual, but it is
-- not news that they joined, and saying so would be a lie about when.
create function public.join_announcement_window()
returns interval
language sql
immutable
as $$ select interval '7 days' $$;

-- The recipient's devices, but only while the pair really is mutual — the
-- Edge Function re-checks through this rather than trusting its caller.
create function public.join_push_recipients(recipient uuid, newcomer uuid)
returns table (token text, sandbox boolean)
language sql
stable
security definer
set search_path = public
as $$
  select dt.token, dt.sandbox
  from device_tokens dt
  where dt.user_id = recipient
    and public.are_mutual_contacts(recipient, newcomer);
$$;
revoke execute on function public.join_push_recipients(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.join_push_recipients(uuid, uuid)
  to service_role;

-- Fires on every contact_links insert; cheap because the common case is an
-- existing friendship being re-inserted by a routine sync, which fails the
-- mutuality check or the once-ever claim below and stops there.
create function public.announce_new_join()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  pair record;
  base_url text;
  fn_secret text;
begin
  -- Not mutual yet: nothing has happened worth telling anyone about.
  if not exists (
    select 1 from contact_links
    where owner_id = new.user_id and user_id = new.owner_id
  ) then
    return new;
  end if;

  select decrypted_secret into base_url
    from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into fn_secret
    from vault.decrypted_secrets where name = 'push_fn_secret';

  -- Both directions: usually only one side is new, but two friends who sign
  -- up in the same week should each hear about the other.
  for pair in
    select new.owner_id as recipient, new.user_id as newcomer
    union all
    select new.user_id, new.owner_id
  loop
    -- Claim the announcement and test the window in one statement, so
    -- concurrent syncs cannot both decide they are the one to send.
    insert into join_announcements (recipient_id, new_user_id)
    select pair.recipient, pair.newcomer
    from profiles p
    where p.id = pair.newcomer
      and p.created_at > now() - public.join_announcement_window()
    on conflict do nothing;

    if found and base_url is not null and fn_secret is not null then
      perform net.http_post(
        url := base_url || '/functions/v1/push-joined',
        body := jsonb_build_object(
          'recipient_id', pair.recipient,
          'new_user_id', pair.newcomer
        ),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-push-secret', fn_secret
        )
      );
    end if;
  end loop;

  return new;
exception when others then
  -- Push plumbing must never block a sync or a signup.
  return new;
end;
$$;

create trigger on_contact_link_announce_join
  after insert on public.contact_links
  for each row execute function public.announce_new_join();
