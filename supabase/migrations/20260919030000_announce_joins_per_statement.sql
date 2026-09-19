-- announce_new_join ran once per inserted contact_links row, and
-- replace_contact_hashes re-inserts an owner's whole link set on every sync.
-- So a routine upload from somebody with N mutual friends did N trigger
-- invocations, each re-reading Vault and probing join_announcements, to
-- discover N times that there was nothing to announce. Irrelevant at today's
-- size and quadratic-feeling at any other, since it scales with mutuals ×
-- syncs.
--
-- A statement-level trigger with a transition table does the same work in
-- one pass: one Vault read, one set-based claim, and a push per row that the
-- claim actually won. Semantics are unchanged — the contact_graph tests
-- assert the behaviour, not the shape.

create function public.announce_new_joins()
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
  select decrypted_secret into base_url
    from vault.decrypted_secrets where name = 'project_url';
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

drop trigger on_contact_link_announce_join on public.contact_links;
drop function public.announce_new_join();

create trigger on_contact_links_announce_joins
  after insert on public.contact_links
  referencing new table as inserted
  for each statement execute function public.announce_new_joins();
