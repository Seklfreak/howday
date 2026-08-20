-- sync-contacts used to delete + insert contact_links as two separate
-- statements. Concurrent invocations for the same user (board load,
-- foreground re-sync, and a contacts change can all fire at once) interleave
-- those statements and the loser's insert dies on the primary key
-- (MOODRING-IOS-1). Do the replace in one transaction, serialized per owner
-- with an advisory xact lock so concurrent syncs queue instead of colliding.
create function public.replace_contact_links(owner uuid, ids uuid[])
returns integer
language plpgsql
set search_path = public
as $$
declare
  linked integer;
begin
  -- Released at commit/rollback; different owners don't contend.
  perform pg_advisory_xact_lock(
    hashtextextended('contact_links:' || owner::text, 0)
  );
  delete from contact_links where owner_id = owner;
  insert into contact_links (owner_id, user_id)
  select distinct owner, u
  from unnest(ids) as u
  where u <> owner;
  get diagnostics linked = row_count;
  return linked;
end;
$$;

-- Service-role only, like everything else that touches contact_links.
revoke execute on function public.replace_contact_links(uuid, uuid[])
  from public, anon, authenticated;
grant execute on function public.replace_contact_links(uuid, uuid[])
  to service_role;
