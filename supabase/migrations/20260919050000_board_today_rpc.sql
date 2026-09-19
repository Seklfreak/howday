-- The board read cost O(every check-in made today, by anybody) instead of
-- O(your friends). `select … from checkins where day = today` reaches the
-- RLS policy, which calls are_mutual_contacts once per candidate row; at
-- 20k users that is ~20k function calls, 60k buffers and 140ms to return 81
-- rows. Measured, not guessed.
--
-- The planner cannot fix it on its own: are_mutual_contacts is SECURITY
-- DEFINER, so it is a black box that cannot be inlined into a join, and it
-- has to stay definer because contact_links is sealed from authenticated.
--
-- So invert the query. Drive it from the caller's own links — 80 of them —
-- and probe checkins through the (user_id, day) unique index once per
-- friend. Same rows, 2.4ms, 336 buffers: ~58x faster and ~180x fewer
-- buffers on the same data, and now it scales with your friend count rather
-- than with total signups.
--
-- The RLS policy stays exactly as it is. This function does not replace that
-- boundary, it avoids paying for it row by row; a client that keeps querying
-- the table directly is still correctly filtered.
create function public.board_today(for_day date)
returns table (id uuid, user_id uuid, day date, emoji text)
language sql
stable
security definer
set search_path = public
as $$
  -- Your own row: one index probe, and the reason the board can show your
  -- check-in before anyone else has synced.
  select c.id, c.user_id, c.day, c.emoji
  from checkins c
  where c.user_id = auth.uid() and c.day = for_day

  union all

  -- Mutual contacts only, same condition as the RLS policy — expressed as a
  -- join so it is driven from contact_links rather than evaluated per
  -- check-in. `union all` cannot duplicate your own row: contact_links
  -- forbids owner_id = user_id.
  select c.id, c.user_id, c.day, c.emoji
  from contact_links mine
  join contact_links back
    on back.owner_id = mine.user_id and back.user_id = mine.owner_id
  join checkins c
    on c.user_id = mine.user_id and c.day = for_day
  where mine.owner_id = auth.uid();
$$;

-- Returns only the four columns the board renders. `note` is deliberately
-- not among them: nothing reads it, and a definer function should hand back
-- the minimum rather than whatever the table happens to hold.
revoke execute on function public.board_today(date) from public, anon;
grant execute on function public.board_today(date) to authenticated;
