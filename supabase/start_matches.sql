-- OPCIONAL (recomendado): faz o BANCO marcar o jogo como 'live' no horário do apito,
-- sem depender da sincronização com a API. O app já mostra AO VIVO por conta própria;
-- isto só deixa o banco igual ao que o jogador vê (e dispara o realtime).
-- Rode no Supabase -> SQL Editor.

create or replace function public.start_due_matches()
returns int
language sql security definer set search_path = public as $$
  with u as (
    update matches set status = 'live', updated_at = now()
    where status = 'scheduled' and kickoff_at <= now()
    returning 1
  )
  select count(*)::int from u;
$$;
revoke all on function public.start_due_matches() from public, anon, authenticated;

-- Agenda a cada minuto (requer a extensão pg_cron: Database -> Extensions -> pg_cron).
create extension if not exists pg_cron;
select cron.schedule('start-due-matches', '* * * * *', $$select public.start_due_matches()$$);
