-- The board's query is `where day = <viewer's local day>`, and the only index
-- on checkins was the unique (user_id, day) — useless when user_id isn't in
-- the predicate. So every board load of every user seq-scanned the whole
-- table and then evaluated the checkins_select policy's are_mutual_contacts()
-- (two EXISTS) on each surviving row. Invisible at today's row count and
-- steadily less so.
create index checkins_day_idx on public.checkins (day);
