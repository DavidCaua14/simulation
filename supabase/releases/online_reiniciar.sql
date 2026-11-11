-- Reinicia o modo online: apaga a temporada atual (clubes, elencos, jogos, leilões, extratos e histórico) e cria
-- uma temporada nova com os técnicos de teste (on_config.testers), que voltam para a escolha dos três craques.
-- Só mexe nas tabelas on_*. O modo Temporadas e as moedas das contas não mudam.
-- A temporada começa amanhã (horário de São Paulo), com jogos às 09:00, 10:00, 11:00, 14:00, 15:30 e 17:00.
-- Para testar partidas em sequência, troque a última linha por:
--   ..., (now() at time zone 'America/Sao_Paulo')::date, 'sandbox', interval '15 minutes');
begin;
delete from public.on_players;
delete from public.on_history;
delete from public.on_seasons;
select public.on_season_bootstrap(
 array(select u.id from auth.users u where lower(u.email)=any(select unnest(c.testers) from public.on_config c)),
 (now() at time zone 'America/Sao_Paulo')::date+1,'main');
commit;
