-- checkins is the only table clients touch directly, and its grants were
-- never written down: this project was created while Supabase still
-- auto-exposed new tables in `public`, so `authenticated` got them
-- implicitly. Applying these migrations to an empty database therefore
-- produces an app that cannot read its own check-ins —
-- "permission denied for table checkins" — which is what a disaster
-- recovery, a preview branch, or a staging project would hit. CI never
-- noticed because it applies migrations and lints, but never reads a row as
-- a client. That auto-expose behaviour is removed on 2026-10-30 (see the
-- comment on `auto_expose_new_tables` in config.toml), so this is also a
-- deadline, not only tidiness.
--
-- The implicit grant was also broader than intended:
--   SELECT, INSERT, REFERENCES, TRIGGER, TRUNCATE, MAINTAIN, UPDATE
-- TRUNCATE is the one that matters, because it bypasses RLS entirely — the
-- whole security model of this table. PostgREST only ever issues SELECT /
-- INSERT / UPDATE / DELETE, so it was not reachable through the API, but a
-- privilege that exists only by accident and appears in no migration is not
-- one anybody is deciding to keep.
--
-- State what the client actually does, and nothing else: read the board and
-- the history, insert today's check-in, update it until midnight. No DELETE,
-- matching "No client deletes on checkins" in the init migration.

revoke all on public.checkins from anon, authenticated;
grant select, insert, update on public.checkins to authenticated;
