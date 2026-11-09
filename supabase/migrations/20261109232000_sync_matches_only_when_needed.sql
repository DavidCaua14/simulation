-- O cron chamava a Edge Function sync-matches a cada minuto, mesmo sem jogo real em andamento (cerca de cinco
-- requisições ao banco por minuto, 24 horas por dia). Agora a chamada só sai quando há trabalho:
-- jogo em andamento, jogo com horário já passado, ou palpite pendente de jogo encerrado/anulado.
-- A janela de 7 dias é a mesma LOOKBACK_MS da função. O agendamento continua de minuto em minuto.
select cron.alter_job(
  (select jobid from cron.job where jobname = 'sync-matches-live'),
  command := $job$
  select net.http_post(
    url := 'https://nkdbixmfsochlprcvkxl.supabase.co/functions/v1/sync-matches',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := '{"mode":"live"}'::jsonb,
    timeout_milliseconds := 25000
  )
  where exists (select 1 from public.matches m
                where m.kickoff_at >= now() - interval '7 days'
                  and (m.status = 'live' or (m.status = 'scheduled' and m.kickoff_at <= now())))
     or exists (select 1 from public.ticket_picks p join public.matches m on m.id = p.match_id
                where p.status = 'pending' and m.status in ('finished', 'void'));
$job$);
