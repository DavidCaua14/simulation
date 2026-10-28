-- SOMENTE LEITURA. Todos os contadores de inconsistência devem ser zero.
select 'pares duplicados' as verificacao,count(*) as inconsistencias from (
 select season_id,competition_id,stage,home_club,away_club from public.season_fixtures group by 1,2,3,4,5 having count(*)>1) q
union all
select 'clube em dois jogos na rodada',count(*) from(
 select season_id,competition_id,stage,round_no,club,count(*) from(
  select season_id,competition_id,stage,round_no,home_club as club from public.season_fixtures
  union all select season_id,competition_id,stage,round_no,away_club from public.season_fixtures) x group by 1,2,3,4,5 having count(*)>1) q
union all
select 'partida vinculada a outra carreira/temporada',count(*) from public.mgr_matches m
 join public.season_fixtures f on f.id=m.fixture_id join public.career_seasons s on s.id=f.season_id
 where m.season_id<>f.season_id or m.career_id<>s.career_id
union all
select 'placar encerrado inválido',count(*) from public.season_fixtures where status='played' and (home_goals is null or away_goals is null or least(home_goals,away_goals)<0)
union all
select 'mesmo clube nos dois lados',count(*) from public.season_fixtures where home_club=away_club;

select status,mode,count(*) as temporadas from public.career_seasons group by status,mode order by 1,2;
select status,count(*) as partidas from public.season_fixtures group by status;
-- Sem emails, sessões, saldos ou credenciais no resultado.
