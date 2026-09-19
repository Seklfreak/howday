-- Postgres grants EXECUTE on a new function to PUBLIC by default, so every
-- trigger function in this schema is nominally callable by anon and
-- authenticated. Nothing is exploitable through it — Postgres refuses a
-- direct call to a function returning `trigger` ("trigger functions can only
-- be called as triggers"), and none of these take an argument worth probing.
-- But every other function here states its grants explicitly, and a reader
-- checking the attack surface should not have to know that rule to clear
-- them. Make the intent visible instead.

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.notify_checkin_push() from public, anon, authenticated;
revoke execute on function public.link_new_profile() from public, anon, authenticated;
revoke execute on function public.announce_new_join() from public, anon, authenticated;
