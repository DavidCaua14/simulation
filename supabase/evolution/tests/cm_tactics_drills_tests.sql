-- Evolução 64: táticas do CM17, funções e exercícios pré-jogo. Banco descartável; tudo é revertido.
do $$ begin if current_database() not like 'simulation_validation_%' then raise exception 'Disposable local database required';end if;end $$;
begin;
select setseed(0.64);
insert into auth.users(id,email) values('64640000-0000-0000-0000-000000000001','cm64@example.test');
insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins,level,xp)
 values('64640000-0000-0000-0000-000000000011','64640000-0000-0000-0000-000000000001','CM64','sport','1',30,1000,3,250);
select set_config('request.jwt.claim.sub','64640000-0000-0000-0000-000000000001',true);
select public.career_runtime_initialize() is not null;
create temp table cm_sample(case_name text,long_goals int,sp_goals int,goals int,headers int);
do $test$
declare cid uuid:='64640000-0000-0000-0000-000000000011';t jsonb;r jsonb;req uuid:=gen_random_uuid();coins0 int;fx bigint;st jsonb;
 cap text;minute int;rec record;
begin
 update public.cw_world set needs_sync=false where career_id=cid;
 perform public.mgr_lock();

 -- 1) Táticas: as escolhas do CM17 mandam e derivam as chaves do motor; táticas antigas viram o equivalente.
 t:=public.mgr_tactics_clean('{"style":"attacking","attack":"central","passing":"long","tackling":"heavy","tempo":"fast","marking":"high","long_shots":"often","set_pieces":"shoot","crossing":"rarely"}');
 if (t->>'mentality')::int<>1 or t->>'build'<>'direct' or t->>'width'<>'center' or t->>'tackles'<>'aggressive' or t->>'pressing'<>'high' or t->>'line'<>'high' then
  raise exception 'Chaves internas não derivadas do CM17: %',t;
 end if;
 t:=public.mgr_tactics_clean('{"mentality":-2,"build":"short","width":"wide","tackles":"cautious","pressing":"low"}');
 if t->>'style'<>'defensive' or (t->>'mentality')::int<>-2 or t->>'passing'<>'short' or t->>'attack'<>'both' or t->>'tackling'<>'light' or t->>'marking'<>'low' then
  raise exception 'Tática antiga não convertida: %',t;
 end if;
 -- mudança no meio do jogo (só chaves do CM17) prevalece sobre as internas antigas
 t:=public.mgr_tactics_clean(public.mgr_tactics_clean('{"mentality":1}')||'{"style":"defensive","passing":"short"}');
 if (t->>'mentality')::int<>-1 or t->>'build'<>'short' then raise exception 'Mudança do CM17 ignorada: %',t;end if;
 if exists(select 1 from public.mgr_lineups where not (tactics ? 'style')) then raise exception 'Escalação salva sem tática convertida';end if;
 raise notice 'PASS táticas CM17';

 -- 2) Exercícios: cobram moedas uma vez (pedido repetido não cobra de novo) e duram 3 jogos.
 select coins into coins0 from public.careers where id=cid;
 r:=public.career_drill_buy('shooting',req);
 r:=public.career_drill_buy('shooting',req);
 if (select coins from public.careers where id=cid)<>coins0-40 then raise exception 'Exercício cobrado errado';end if;
 if (select games_left from public.cw_match_boosts where career_id=cid and kind='shooting')<>3 then raise exception 'Exercício sem 3 jogos';end if;
 r:=public.career_drill_buy('all',gen_random_uuid());
 if (select coins from public.careers where id=cid)<>coins0-40-public.cw_drill_all_price() then raise exception 'Pacote cobrado errado';end if;
 begin
  update public.careers set coins=0 where id=cid;
  r:=public.career_drill_buy('passing',gen_random_uuid());
  raise exception 'Comprou sem moedas';
 exception when sqlstate 'P0402' then null;end;
 raise notice 'PASS exercícios: cobrança e duração';

 -- 3) Funções: capitão e batedores entram na partida; exercícios valem para o time do treinador e gastam um jogo.
 select mp.player_id into cap from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
  where mp.career_id=cid and mp.club_id='sport' and sp.position<>'GOL' order by mp.player_id limit 1;
 r:=public.career_set_pieces_set(null,cap,cap,cap);
 if (public.career_club_dev_read()->'set_pieces'->>'captain') is distinct from cap then raise exception 'Capitão não lido';end if;
 select f.id into fx from public.season_fixtures f join public.career_seasons s on s.id=f.season_id
  where s.career_id=cid and f.status<>'played' and 'sport' in(f.home_club,f.away_club) and not exists(select 1 from public.mgr_matches m where m.fixture_id=f.id) order by f.id limit 1;
 begin
  perform public.mgr_match_create(fx,cid,case when (select home_club from public.season_fixtures where id=fx)='sport' then 'h' else 'a' end,
   (select jsonb_build_object('formation',l.formation,'slots',l.slots,'bench',to_jsonb(l.bench),'tactics',l.tactics) from public.mgr_lineups l where l.career_id=cid and l.club_id='sport'));
  select state into st from public.mgr_matches where fixture_id=fx;
  if not coalesce((st->>'cm64')::boolean,false) or st->'drills'->>'shooting' is null then raise exception 'Partida sem preparação 64: %',st;end if;
  if (select games_left from public.cw_match_boosts where career_id=cid and kind='shooting')<>5 then raise exception 'Exercício não gastou um jogo';end if;
  if st->'fk_taker'->>(case when (select home_club from public.season_fixtures where id=fx)='sport' then 'h' else 'a' end) is null then raise exception 'Sem batedor de falta: % %',st->'fk_taker',(select json_agg(json_build_object('s',side,'st',status)) from public.mgr_match_players where fixture_id=fx);end if;
  raise exception using errcode='P6401',message='rollback';
 exception when sqlstate 'P6401' then null;end;
 raise notice 'PASS funções e exercícios na partida';

 -- 4) Motor: chutes longos frequentes geram gols de fora da área; bola parada produz gols; "raro" quase zera.
 select f.id into fx from public.season_fixtures f join public.career_seasons s on s.id=f.season_id
  where s.career_id=cid and f.status<>'played' and f.competition_id='brasileirao' and not exists(select 1 from public.mgr_matches m where m.fixture_id=f.id) order by f.id limit 1;
 for i in 1..80 loop
  delete from public.mgr_match_events where fixture_id=fx;
  delete from public.mgr_match_players where fixture_id=fx;
  delete from public.mgr_matches where fixture_id=fx;
  perform public.mgr_match_create(fx,cid,null,null);
  t:=case when i<=40 then '{"long_shots":"often","crossing":"byline","set_pieces":"shoot"}'::jsonb else '{"long_shots":"rarely","crossing":"rarely","set_pieces":"short"}'::jsonb end;
  update public.mgr_matches set state=jsonb_set(jsonb_set(state,'{tactics,h}',public.mgr_tactics_clean((state->'tactics'->'h')||t)),
   '{tactics,a}',public.mgr_tactics_clean((state->'tactics'->'a')||t)) where fixture_id=fx;
  loop
   perform public.mgr_engine_run(fx,90,'h');
   select m.minute into minute from public.mgr_matches m where fixture_id=fx;
   exit when minute>=90;
  end loop;
  insert into cm_sample select case when i<=40 then 'often' else 'rarely' end,
   count(*) filter(where kind='goal' and detail='de fora da área'),count(*) filter(where kind='goal' and detail like '%bola parada%' or detail='cobrança de falta'),
   count(*) filter(where kind in('goal','pen_goal')),count(*) filter(where kind='goal' and detail like '%cabeça%')
  from public.mgr_match_events where fixture_id=fx;
 end loop;
 for rec in select case_name,sum(long_goals) lg,sum(sp_goals) sg,round(avg(goals),2) g,sum(headers) h from cm_sample group by 1 order by 1 loop
  raise notice 'CM64 %: gols de fora %, bola parada %, cabeça %, média de gols %',rec.case_name,rec.lg,rec.sg,rec.h,rec.g;
 end loop;
 if (select sum(long_goals) from cm_sample where case_name='often')<=(select sum(long_goals) from cm_sample where case_name='rarely') then raise exception 'Chutes longos sem efeito';end if;
 if (select sum(headers) from cm_sample where case_name='often')<=(select sum(headers) from cm_sample where case_name='rarely') then raise exception 'Cruzamento sem efeito';end if;
 if (select sum(sp_goals) from cm_sample)=0 then raise exception 'Bola parada nunca vira gol';end if;
 if (select avg(goals) from cm_sample) not between 1.5 and 4.5 then raise exception 'Gols fora da faixa';end if;
 raise notice 'PASS motor CM17: chutes longos, cruzamento e bola parada';
end $test$;
rollback;
