-- Agenda o sync-odds a cada 2 horas. Rode DEPOIS de publicar a função.
-- Antes: Database -> Extensions -> ative "pg_cron" e "pg_net".
-- Troque SEU_PROJECT_REF (o código antes de .supabase.co na URL do projeto)
-- e SEU_CRON_SECRET (o MESMO valor que você colocou em: supabase secrets set CRON_SECRET=...).
-- A função só gasta crédito quando há jogo sem odd real nos próximos dias, e no máximo
-- 1 consulta a cada 12h por campeonato; então rodar de 2 em 2 horas é barato.

select vault.create_secret('cd777300f854bd3ce7b19d31f0cd777300f854bd3ce7b19d31f0bfa9dfe21257b072f22a0621f5ebaa87982b37', 'cron_secret');

select cron.schedule('sync-odds', '0 */2 * * *', $$
  select net.http_post(
    url := 'https://SEU_PROJECT_REF.supabase.co/functions/v1/sync-odds',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
$$);

-- Para parar: select cron.unschedule('sync-odds');
