-- Broadcast checkins changes over Realtime (postgres_changes). RLS still
-- applies per-subscriber: each client only receives rows it could select,
-- so friends see each other's check-ins pop in and nobody else's.
alter publication supabase_realtime add table public.checkins;
