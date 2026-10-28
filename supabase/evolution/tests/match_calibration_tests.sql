-- Amostra de regressão do motor. Só no banco descartável; todos os dados são fictícios.
begin;
select setseed(0.271828);
insert into auth.users(id) values('16161616-0000-0000-0000-000000000001');
insert into public.careers(id,user_id,nickname,club_id,country,age,bonus_energy)
 values('16161616-0000-0000-0000-0000000000ca','16161616-0000-0000-0000-000000000001','calibration','palmeiras','BR',30,1000);
select set_config('request.jwt.claim.sub','16161616-0000-0000-0000-000000000001',true);
select public.mgr_hub() is not null;
create temp table sample(case_name text,home_goals int,away_goals int,reds int,yellows int,fouls int,shots int,home_strength numeric,away_strength numeric);
do $$
declare fx bigint;v_season uuid;r record;minute int;v_state jsonb;goals int[];t text;v_strength numeric[];fx_home bigint;fx_away bigint;strong text;weak text;
begin
 select id into v_season from public.career_seasons where career_id='16161616-0000-0000-0000-0000000000ca' and status='active';
 select f.id into fx from public.season_fixtures f join public.sim_clubs h on h.id=f.home_club join public.sim_clubs a on a.id=f.away_club
  where f.season_id=v_season and f.competition_id='brasileirao' order by abs(h.strength-a.strength) limit 1;
 for i in 1..180 loop
  delete from public.mgr_match_events where fixture_id=fx;
  delete from public.mgr_match_players where fixture_id=fx;
  delete from public.mgr_matches where fixture_id=fx;
  perform public.mgr_match_create(fx,'16161616-0000-0000-0000-0000000000ca',null,null);
  t:=case when i<=60 then 'cautious' when i<=120 then 'normal' else 'aggressive' end;
  update public.mgr_matches set state=jsonb_set(jsonb_set(state,'{tactics,h,tackles}',to_jsonb(t)),'{tactics,a,tackles}',to_jsonb(t)) where fixture_id=fx;
  loop
   perform public.mgr_engine_run(fx,90,null);
   select m.minute,m.state into minute,v_state from public.mgr_matches m where fixture_id=fx;
   exit when minute>=90;
  end loop;
  insert into sample select t,(v_state->'score'->>0)::int,(v_state->'score'->>1)::int,
    sum(red),sum(yellow),sum(fouls),sum(shots),(v_state->'strength'->>0)::numeric,(v_state->'strength'->>1)::numeric
   from public.mgr_match_players where fixture_id=fx;
 end loop;
 for r in select case_name,count(*) as games,round(avg(home_goals+away_goals),2) as goals,round(avg(reds),3) as reds,round(avg(yellows),2) as yellows,round(avg(fouls),2) as fouls,round(avg(shots),2) as shots from sample group by 1 order by 1 loop
  raise notice 'CALIBRAÇÃO %: jogos %, gols %, vermelhos %, amarelos %, faltas %, chutes %',r.case_name,r.games,r.goals,r.reds,r.yellows,r.fouls,r.shots;
 end loop;
 assert (select avg(reds) from sample)<0.30,'Expulsões excessivas na amostra';
 assert (select avg(home_goals+away_goals) from sample) between 1.5 and 4.5,'Gols fora da faixa de regressão';
 assert (select avg(fouls) from sample where case_name='aggressive')>(select avg(fouls) from sample where case_name='cautious'),'Entradas não influenciam faltas';
 assert (select avg(yellows) from sample where case_name='aggressive')>(select avg(yellows) from sample where case_name='cautious'),'Entradas não influenciam cartões';
 assert (select count(*) from sample where home_goals=away_goals)>0,'Sem empates na amostra';
 assert (select count(*) from sample where home_goals>away_goals)>0 and (select count(*) from sample where away_goals>home_goals)>0,'Resultados previsíveis';
 -- Arbitragem e comportamento individual precisam mudar probabilidades, sem sorteio no teste.
 assert (public.mgr_card_chances(85,35,50,45,4,false,'aggressive',1.2,1.2)->>'red')::numeric
  >(public.mgr_card_chances(30,85,85,100,0,false,'cautious',0.8,1)->>'red')::numeric,'Disciplina contextual inoperante';
 -- Mesmo confronto de qualidade diferente, alternando mando para não confundir
 -- vantagem de casa com força dos atletas. O resultado continua probabilístico.
 select f.id,f.home_club,f.away_club into fx_home,strong,weak from public.season_fixtures f
  join public.sim_clubs h on h.id=f.home_club join public.sim_clubs a on a.id=f.away_club
  where f.season_id=v_season and f.competition_id='brasileirao' and h.strength-a.strength between 10 and 18
  order by h.strength-a.strength desc,f.id limit 1;
 assert fx_home is not null,'Sem confronto de qualidade para a amostra';
 select id into fx_away from public.season_fixtures where season_id=v_season and competition_id='brasileirao' and home_club=weak and away_club=strong;
 for i in 1..120 loop
  fx:=case when i<=60 then fx_home else fx_away end;
  delete from public.mgr_match_events where fixture_id=fx;
  delete from public.mgr_match_players where fixture_id=fx;
  delete from public.mgr_matches where fixture_id=fx;
  perform public.mgr_match_create(fx,'16161616-0000-0000-0000-0000000000ca',null,null);
  loop
   perform public.mgr_engine_run(fx,90,null);
   select m.minute,m.state into minute,v_state from public.mgr_matches m where fixture_id=fx;
   exit when minute>=90;
  end loop;
  insert into sample select case when i<=60 then 'quality_home' else 'quality_away' end,
    (v_state->'score'->>0)::int,(v_state->'score'->>1)::int,sum(red),sum(yellow),sum(fouls),sum(shots),
    (v_state->'strength'->>0)::numeric,(v_state->'strength'->>1)::numeric from public.mgr_match_players where fixture_id=fx;
 end loop;
 select count(*) filter(where sg>wg) as wins,count(*) filter(where sg<wg) as upsets,round(avg(sg),2) as strong_goals,round(avg(wg),2) as weak_goals into r
 from(select case when case_name='quality_home' then home_goals else away_goals end sg,
             case when case_name='quality_home' then away_goals else home_goals end wg from sample where case_name like 'quality_%') q;
 raise notice 'QUALIDADE: % x %, favorito % vitórias, % derrotas; média de gols % x % em 120 jogos',strong,weak,r.wins,r.upsets,r.strong_goals,r.weak_goals;
 select round(avg(case when case_name='quality_home' then home_strength else away_strength end),1) as strong_eff,round(avg(case when case_name='quality_home' then away_strength else home_strength end),1) as weak_eff into r from sample where case_name like 'quality_%';
 raise notice 'FORÇA efetiva: % x %',r.strong_eff,r.weak_eff;
 select count(*) filter(where sg>wg) as wins,count(*) filter(where sg<wg) as upsets,round(avg(sg),2) as strong_goals,round(avg(wg),2) as weak_goals into r from(select case when case_name='quality_home' then home_goals else away_goals end sg,case when case_name='quality_home' then away_goals else home_goals end wg from sample where case_name like 'quality_%') q;
 assert r.weak_goals>=0.4,'Azarão sem capacidade real de criar gols';
 assert r.strong_goals>r.weak_goals and r.wins>r.upsets,'Força dos atletas sem influência';
 assert r.upsets>=3 and r.wins<108,'Favorito artificialmente invencível';
 raise notice 'PASS calibração: resultados variados e disciplina contextual';
end $$;
rollback;
