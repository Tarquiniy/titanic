-- Shared balance for telegram users:
--   vernon_eger
--   erna_valter
--
-- What this does:
-- 1. Any change to v_balance or m_balance of one of these users
--    is copied to the other user automatically.
-- 2. Works only for this pair.
-- 3. Includes a one-time manual sync block at the end.

create or replace function public.sync_linked_voice_mind_balances()
returns trigger
language plpgsql
as $$
declare
  normalized_username text;
begin
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  normalized_username := lower(btrim(coalesce(new.telegram_username, '')));

  if normalized_username not in ('vernon_eger', 'erna_valter') then
    return new;
  end if;

  update public.user_credentials
  set
    v_balance = new.v_balance,
    m_balance = new.m_balance
  where lower(btrim(coalesce(telegram_username, ''))) in ('vernon_eger', 'erna_valter')
    and id <> new.id;

  return new;
end;
$$;

drop trigger if exists trg_sync_linked_voice_mind_balances on public.user_credentials;

create trigger trg_sync_linked_voice_mind_balances
after insert or update of telegram_username, v_balance, m_balance
on public.user_credentials
for each row
execute function public.sync_linked_voice_mind_balances();

-- One-time initial sync.
-- This takes vernon_eger as the source of truth and copies his balances to erna_valter.
update public.user_credentials target
set
  v_balance = source.v_balance,
  m_balance = source.m_balance
from public.user_credentials source
where lower(btrim(coalesce(source.telegram_username, ''))) = 'vernon_eger'
  and lower(btrim(coalesce(target.telegram_username, ''))) = 'erna_valter';
