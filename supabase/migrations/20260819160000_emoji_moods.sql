-- Emoji-first check-ins: the emoji IS the mood. Backfill existing rows from
-- the old 1–5 scale, then require emoji and drop mood. char_length counts
-- code points, and a long ZWJ sequence (family emoji) is ~7 — 16 leaves room
-- while still rejecting arbitrary text; "one emoji" is enforced client-side.

update public.checkins
set emoji = (array['😢','😕','😐','🙂','😄'])[mood]
where emoji is null;

alter table public.checkins
  alter column emoji set not null,
  add constraint checkins_emoji_length check (char_length(emoji) between 1 and 16),
  drop column mood;
