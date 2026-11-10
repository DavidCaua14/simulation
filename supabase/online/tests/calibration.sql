-- Calibração do motor online (Fase 2): N partidas inteiras entre clubes da temporada de teste.
-- Rodar só no banco descartável: node scripts/test-online-db.mjs --calibrate
-- Referência (motor v2 do modo Temporadas em produção, 10/11/2026): 2,9 gols, 4,0 amarelos, 0,1 vermelho e
-- 27 finalizações por partida; mandante vence 42%.
create temp table cal(goals int,hw int,yel int,red int,shots int,inj int,ms int);
create temp table calt(seg5_ms int,bloco45_ms int);
do $$
declare f public.on_fixtures;i int;t0 timestamptz;t1 timestamptz;seg5 numeric:=0;blk45 numeric:=0;
begin
 for i in 1..500 loop
  select x.* into f from public.on_fixtures x join public.on_seasons s on s.id=x.season_id and s.status='live' order by x.id offset (i%132) limit 1;
  delete from public.on_matches where fixture_id=f.id;
  update public.on_fixtures set status='sched' where id=f.id;
  update public.on_players p set cond=100,inj_until=null,susp_round=null where p.club_id in(f.home,f.away);
  perform public.on_match_open(f);
  t0:=clock_timestamp();
  perform public.on_advance(f.id,f.kickoff+interval '35 seconds',case when i%2=0 then 'h' else '' end);
  t1:=clock_timestamp();seg5:=greatest(seg5,extract(epoch from t1-t0));
  perform public.on_advance(f.id,f.kickoff+interval '315 seconds',case when i%2=0 then 'h' else '' end);
  t0:=clock_timestamp();
  perform public.on_advance(f.id,f.kickoff+interval '1 day',null);
  blk45:=greatest(blk45,extract(epoch from clock_timestamp()-t0));
  insert into cal select (m.state->'score'->>0)::int+(m.state->'score'->>1)::int,((m.state->'score'->>0)::int>(m.state->'score'->>1)::int)::int,
   (select sum(yellow) from public.on_match_players where fixture_id=f.id),(select sum(red) from public.on_match_players where fixture_id=f.id),
   (select sum(shots) from public.on_match_players where fixture_id=f.id),(select count(*) from public.on_match_players where fixture_id=f.id and injured),0
  from public.on_matches m where m.fixture_id=f.id;
 end loop;
 insert into calt values(round(seg5*1000),round(blk45*1000));
end $$;
select count(*) n,round(avg(goals),2) gols,round(stddev(goals),2) dp,round(avg(hw),3) mandante,round(avg(yel),2) amarelos,round(avg(red),3) vermelhos,
 round(avg(shots),1) finalizacoes,round(avg(inj),2) lesoes,(select seg5_ms from calt) pior_5min_ms,(select bloco45_ms from calt) pior_45min_ms from cal;
do $$ begin
 if (select avg(goals) not between 2.0 and 3.6 or avg(yel) not between 3.0 and 6.0 or avg(red)>0.3 or avg(shots) not between 20 and 34 from cal) then
  raise exception 'motor online fora da faixa do motor do modo Temporadas';
 end if;
 if (select seg5_ms>150 or bloco45_ms>1500 from calt) then raise exception 'motor online lento demais';end if;
end $$;
