-- The widgets size each friend's emoji by how recently they checked in and
-- lay the large one out along the day, so the board read needs to say when
-- each check-in happened. Same query as before plus one column; a
-- Decodable client that names its columns keeps working, and the app's
-- Checkin does.
--
-- checked_in_at is the last time the row was touched: updated_at is written
-- by every save the client makes (insert included), created_at is the
-- fallback for rows older than that behaviour.
drop function public.board_today(date);

create function public.board_today(for_day date)
returns table (id uuid, user_id uuid, day date, emoji text, checked_in_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select c.id, c.user_id, c.day, c.emoji, coalesce(c.updated_at, c.created_at)
  from checkins c
  where c.user_id = auth.uid() and c.day = for_day

  union all

  select c.id, c.user_id, c.day, c.emoji, coalesce(c.updated_at, c.created_at)
  from contact_links mine
  join contact_links back
    on back.owner_id = mine.user_id and back.user_id = mine.owner_id
  join checkins c
    on c.user_id = mine.user_id and c.day = for_day
  where mine.owner_id = auth.uid();
$$;

revoke execute on function public.board_today(date) from public, anon;
grant execute on function public.board_today(date) to authenticated;
