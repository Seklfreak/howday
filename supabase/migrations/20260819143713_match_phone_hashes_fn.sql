-- Contact matching at real-contact-list scale: passing thousands of hashes
-- through PostgREST's in() URL filter blows past URL length limits (500s
-- for lists over ~1000 contacts). This function takes the array in the
-- request body instead. Only the service role (the match-contacts Edge
-- Function) may execute it — for clients it would be a phone_hash oracle.
create function public.match_phone_hashes(hashes text[])
returns table (id uuid, display_name text, phone_hash text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.display_name, p.phone_hash
  from profiles p
  where p.phone_hash = any(hashes)
$$;

revoke execute on function public.match_phone_hashes(text[]) from public, anon, authenticated;
grant execute on function public.match_phone_hashes(text[]) to service_role;
