-- Reinicia o modo online: apaga a temporada atual (clubes, elencos, jogos, leilões, extratos e histórico) e cria
-- uma temporada nova com os técnicos de teste (on_config.testers), que voltam para a escolha dos três craques.
-- Elencos, craques e leilões usam os jogadores reais do catálogo; os clubes sem técnico são bots.
-- Só mexe nas tabelas on_*. O modo Temporadas e as moedas das contas não mudam.
-- A temporada começa hoje (horário de São Paulo) se o primeiro jogo de todos os técnicos ainda estiver a mais
-- de 30 minutos; senão, começa amanhã. Jogos às 09:00, 10:00, 11:00, 14:00, 15:30 e 17:00.
-- Para testar partidas em sequência, troque a criação por:
--   select public.on_season_bootstrap(<técnicos>,(now() at time zone 'America/Sao_Paulo')::date,'sandbox',interval '15 minutes');
begin;
delete from public.on_players;
delete from public.on_history;
delete from public.on_seasons;
do $$
declare v_s smallint;v_first timestamptz;
begin
 v_s:=public.on_season_bootstrap(
  array(select u.id from auth.users u where lower(u.email)=any(select unnest(c.testers) from public.on_config c)),
  (now() at time zone 'America/Sao_Paulo')::date,'main');
 select min(f.kickoff) into v_first from public.on_fixtures f join public.on_clubs k on k.id in(f.home,f.away) and k.user_id is not null
  where f.season_id=v_s and f.round=1;
 if v_first is null or v_first<now()+interval '30 minutes' then
  update public.on_fixtures set kickoff=kickoff+interval '1 day' where season_id=v_s;
  update public.on_seasons set starts_on=starts_on+1 where id=v_s;
 end if;
end $$;
commit;
