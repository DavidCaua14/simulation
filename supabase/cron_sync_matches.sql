-- =====================================================================
-- AGENDAMENTOS (pg_cron + pg_net) — rode no Supabase -> SQL Editor
-- Antes: Database -> Extensions -> ative "pg_cron" e "pg_net".
-- Troque SEU_CRON_SECRET pelo MESMO valor do secret CRON_SECRET da função.
-- ATENÇÃO: cole o valor UMA vez, sem repetir pedaços (no arquivo antigo
-- schedule_sync_odds.sql o segredo estava duplicado/errado -> 401 em toda chamada).
-- =====================================================================
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- guarda (ou atualiza) o segredo no Vault
do $$
begin
  if exists (select 1 from vault.secrets where name = 'cron_secret') then
    perform vault.update_secret((select id from vault.secrets where name = 'cron_secret'), 'cd777300f854bd3ce7b19d31f0bfa9dfe21257b072f22a0621f5ebaa87982b37');
  else
    perform vault.create_secret('cd777300f854bd3ce7b19d31f0bfa9dfe21257b072f22a0621f5ebaa87982b37', 'cron_secret');
  end if;
end $$;

-- remove agendamentos antigos (inclusive o de odds, que não é mais usado)
do $$
declare j record;
begin
  for j in select jobid from cron.job
           where jobname in ('sync-odds','sync-matches-live','sync-matches-schedule','start-due-matches')
              or command ilike '%sync-matches%' or command ilike '%sync-odds%' or command ilike '%start_due_matches%'
  loop
    perform cron.unschedule(j.jobid);
  end loop;
end $$;

-- A cada minuto: começou -> "em andamento" (banco) e terminou -> consulta a API / liquida
select cron.schedule('start-due-matches', '* * * * *', $$select public.start_due_matches()$$);

select cron.schedule('sync-matches-live', '* * * * *', $$
  select net.http_post(
    url := 'https://nkdbixmfsochlprcvkxl.supabase.co/functions/v1/sync-matches',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := '{"mode":"live"}'::jsonb,
    timeout_milliseconds := 25000
  );
$$);

-- 1x por dia (05:00 em Brasília = 08:00 UTC): traz a agenda dos próximos 7 dias
select cron.schedule('sync-matches-schedule', '0 8 * * *', $$
  select net.http_post(
    url := 'https://nkdbixmfsochlprcvkxl.supabase.co/functions/v1/sync-matches',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := '{"mode":"schedule"}'::jsonb,
    timeout_milliseconds := 25000
  );
$$);

select jobid, jobname, schedule, active from cron.job order by jobid;
