-- Somente no banco descartável. Nenhum registro de usuário real é usado.
begin;
set local statement_timeout='180s';
select setseed(0.31415);

-- 1. Calendário Berger: 1 jogo por rodada, mandos iguais, nenhum rival duplicado,
-- e no máximo dois mandos iguais consecutivos (inclusive virada do turno).
do $$
declare n int;teams text[];v int;r record;
begin
 foreach n in array array[2,4,6,20,24] loop
  select array_agg('team-'||x order by x) into teams from generate_series(1,n) x;
  select count(*) into v from public.sim_round_robin(teams,true);assert v=n*(n-1),'Quantidade errada de jogos';
  for r in select x.club,count(*) as games,count(*) filter(where x.venue='h') as homes,count(distinct f.round_no) as rounds
    from public.sim_round_robin(teams,true) f cross join lateral(values(f.home,'h'),(f.away,'a')) x(club,venue) group by 1 loop
   assert r.games=2*(n-1) and r.homes=n-1 and r.rounds=2*(n-1),'Clube com mando ou rodada desequilibrada';
  end loop;
  with games as(select f.round_no,x.club,x.venue from public.sim_round_robin(teams,true) f cross join lateral(values(f.home,'h'),(f.away,'a')) x(club,venue)),
   islands as(select *,row_number() over(partition by club order by round_no)-row_number() over(partition by club,venue order by round_no) as g from games)
   select max(c) into v from(select count(*) c from islands group by club,venue,g) q;
  assert v<=2,'Mais de dois mandos consecutivos no gerador';
 end loop;
 raise notice 'PASS calendário novo: 2/4/6/20/24 clubes';
end $$;

insert into auth.users(id) values('15151515-0000-0000-0000-000000000001'),('15151515-0000-0000-0000-000000000002');
insert into public.careers(id,user_id,nickname,club_id,country,age,bonus_energy) values
 ('15151515-0000-0000-0000-0000000000a1','15151515-0000-0000-0000-000000000001','restructure_a','palmeiras','BR',30,1000),
 ('15151515-0000-0000-0000-0000000000b1','15151515-0000-0000-0000-000000000002','restructure_b','palmeiras','BR',30,1000);
create temp table test_seasons(k text primary key,v uuid);
select set_config('request.jwt.claim.sub','15151515-0000-0000-0000-000000000001',true);
select public.mgr_hub() is not null;
insert into test_seasons select 'a',id from public.career_seasons where career_id='15151515-0000-0000-0000-0000000000a1';
select set_config('request.jwt.claim.sub','15151515-0000-0000-0000-000000000002',true);
select public.mgr_hub() is not null;
insert into test_seasons select 'b',id from public.career_seasons where career_id='15151515-0000-0000-0000-0000000000b1';

-- Uma temporada do antigo modo jogador, arquivada sem terminar, não pode
-- bloquear a criação da primeira temporada de treinador nem fornecer classificação fictícia.
insert into auth.users(id) values('23232323-0000-0000-0000-000000000001');
insert into public.careers(id,user_id,nickname,club_id,country,age) values
 ('23232323-0000-0000-0000-0000000000ca','23232323-0000-0000-0000-000000000001','legacy_archive','palmeiras','BR',30);
do $$
declare legacy uuid;
begin
 legacy:=public.sim_create_season('23232323-0000-0000-0000-0000000000ca','BRA');
 update public.career_seasons set status='archived' where id=legacy;
 perform set_config('request.jwt.claim.sub','23232323-0000-0000-0000-000000000001',true);
 perform public.mgr_hub();
 assert exists(select 1 from public.career_seasons where career_id='23232323-0000-0000-0000-0000000000ca' and status='active' and mode='coach'),'Carreira legada não iniciou modo treinador';
 assert exists(select 1 from public.season_fixtures where season_id=legacy and status='pending'),'Histórico arquivado foi apagado';
 raise notice 'PASS histórico arquivado incompleto preservado sem bloquear modo treinador';
end $$;

-- Calendário legado defeituoso, para provar a reparação de um caso realista.
create or replace function pg_temp.legacy_round_robin(p_teams text[], p_double boolean default true)
returns table (round_no int, home text, away text)
language plpgsql as $$
declare
  n   int  := array_length(p_teams, 1);
  arr text[] := p_teams;
  r   int;
  i   int;
  h   text;
  a   text;
begin
  for r in 1 .. n - 1 loop
    for i in 1 .. n / 2 loop
      if (r + i) % 2 = 1 then
        h := arr[i];         a := arr[n - i + 1];
      else
        h := arr[n - i + 1]; a := arr[i];
      end if;
      round_no := r; home := h; away := a; return next;
      if p_double then
        round_no := r + n - 1; home := a; away := h; return next;
      end if;
    end loop;
    arr := array[arr[1], arr[n]] || arr[2 : n - 1];   -- gira todos, menos o primeiro
  end loop;
end;
$$;
with teams as(select array_agg(club_id order by club_id) a from public.season_participants where season_id=(select v from test_seasons where k='a') and competition_id='brasileirao'),
 old as(select f.* from teams cross join lateral pg_temp.legacy_round_robin(teams.a,true) f)
update public.season_fixtures f set round_no=old.round_no from old where f.season_id=(select v from test_seasons where k='a') and f.competition_id='brasileirao'
 and f.home_club=old.home and f.away_club=old.away;
update public.season_fixtures set status='played',home_goals=2,away_goals=1,played_at=now()
 where season_id=(select v from test_seasons where k='a') and competition_id='brasileirao' and round_no<=2;
create temp table preserved as select id,to_jsonb(f) as data from public.season_fixtures f
 where f.season_id=(select v from test_seasons where k='b') or f.status='played';
create temp table fixture_identity as select id,home_club,away_club from public.season_fixtures where season_id=(select v from test_seasons where k='a');

do $$
declare sa uuid:=(select v from test_seasons where k='a');sb uuid:=(select v from test_seasons where k='b');before bigint;after bigint;repaired jsonb;fx bigint;n int;rejected boolean;
begin
 before:=public.sim_calendar_cost(sa,'brasileirao','league');assert before>0,'Cenário legado precisa ter sequências excessivas';
 select id into fx from public.season_fixtures where season_id=sa and competition_id='brasileirao' and round_no=3 limit 1;
 perform public.mgr_match_create(fx,'15151515-0000-0000-0000-0000000000a1',null,null);
 repaired:=public.sim_rebalance_pending(sa,'brasileirao');after:=public.sim_calendar_cost(sa,'brasileirao','league');
 assert after<before,format('Reparação não melhorou: %',repaired);
 assert not exists(select 1 from preserved p join public.season_fixtures f using(id) where p.data<>to_jsonb(f)),'Resultado ou outra carreira foi modificado';
 assert not exists(select 1 from fixture_identity p full join public.season_fixtures f on f.id=p.id where f.season_id=sa and (p.id is null or p.home_club<>f.home_club or p.away_club<>f.away_club)),'IDs ou mandos alterados';
 assert (select round_no from public.season_fixtures where id=fx)=3,'Partida iniciada foi movida';
 raise notice 'PASS reparação preserva resultados e partida em andamento: custo % -> %',before,after;
 -- Retira apenas o estado fictício do teste, não o jogo nem seus resultados.
 delete from public.mgr_match_events where fixture_id=fx;
 delete from public.mgr_match_players where fixture_id=fx;
 delete from public.mgr_matches where fixture_id=fx;
 rejected:=false;
 begin
  update public.season_fixtures set home_goals=99 where id=(select id from preserved where data->>'status'='played' limit 1);
 exception when others then rejected:=true;end;
 assert rejected,'Resultado disputado deveria ser imutável';
 rejected:=false;
 begin
  insert into public.mgr_messages(career_id,season_id,day_no,kind,title,body)
   values('15151515-0000-0000-0000-0000000000a1',sb,0,'system','inválido','inválido');
 exception when foreign_key_violation then rejected:=true;end;
 assert rejected,'Vínculo de temporada de outro usuário aceito';
 rejected:=false;
 begin
  perform public.mgr_match_create((select id from public.season_fixtures where season_id=sb limit 1),'15151515-0000-0000-0000-0000000000a1',null,null);
 exception when others then rejected:=true;end;
 assert rejected,'Motor aceitou partida de outra carreira';
 raise notice 'PASS integridade: resultado imutável e vínculos entre usuários recusados';
end $$;
set constraints all immediate;

-- APIs e RLS recusam temporadas/partidas do outro usuário.
select set_config('request.jwt.claim.sub','15151515-0000-0000-0000-000000000001',true);
create temp table test_fixture_ids as select s.k,min(f.id) as fixture_id from test_seasons s join public.season_fixtures f on f.season_id=s.v where 'palmeiras' in(f.home_club,f.away_club) and f.status='pending' group by s.k;
grant select on test_seasons,test_fixture_ids to authenticated;
set local role authenticated;
do $$
declare fx bigint;report jsonb;rejected boolean:=false;
begin
 assert not exists(select 1 from public.career_seasons where id=(select v from test_seasons where k='b')),'RLS vazou outra carreira';
 begin
  perform public.season_standings((select v from test_seasons where k='b'),'brasileirao',null);
 exception when others then rejected:=true;end;
 assert rejected,'Classificação de outro usuário acessível';
 rejected:=false;
 begin
  perform public.mgr_opponent_report((select fixture_id from test_fixture_ids where k='b'));
 exception when others then rejected:=true;end;
 assert rejected,'Análise de rival vazou dados de outro usuário';
 report:=public.mgr_opponent_report((select fixture_id from test_fixture_ids where k='a'));
 assert report->>'formation' is not null and report->'tactics' ? 'build','Análise do rival sem informações táticas';
 assert not has_function_privilege('authenticated','public.sim_swiss_search(int[],int[],int[],int[],int,int)','execute'),'Solver interno exposto';
 assert not has_function_privilege('authenticated','public.mgr_engine_run_v2(bigint,int,char)','execute'),'Motor v2 exposto';
 raise notice 'PASS RLS e permissões das funções';
end $$;
reset role;

-- Encerramento e transição com placares controlados nas partidas ainda pendentes.
-- O clube vencedor escolhido abaixo NÃO era um dos classificados fixos de referência.
do $$
declare sa uuid:=(select v from test_seasons where k='a');sc uuid;wanted text;comp record;q text[];actual text[];v_summary jsonb;again jsonb;
begin
 select sp.club_id into wanted from public.season_participants sp where sp.season_id=sa and sp.competition_id='brasileirao'
 and not exists(select 1 from public.sim_competition_clubs cc where cc.competition_id='libertadores' and cc.club_id=sp.club_id) order by sp.club_id limit 1;
 update public.career_seasons set mode='player' where id=sa;
 update public.season_fixtures set status='played',home_goals=case when away_club=wanted then 0 else 3 end,
  away_goals=case when away_club=wanted then 3 else 0 end,played_at=now()
  where season_id=sa and competition_id='brasileirao' and status='pending';
 for comp in select competition_id from public.season_competitions where season_id=sa loop
  perform public.sim_complete_competition(sa,comp.competition_id);
 end loop;
 v_summary:=public.sim_season_transition(sa);again:=public.sim_season_transition(sa);assert v_summary=again,'Transição não idempotente';
 select array_agg(t->>'club_id' order by(t->>'pos')::int) into q from public.season_final_tables ft cross join lateral jsonb_array_elements(ft.standings) t
 where ft.season_id=sa and ft.competition_id='brasileirao' and (t->>'pos')::int<=6;
 assert wanted=any(q),'Vencedor esportivo não foi classificado';
 update public.career_seasons set status='finished',mode='coach',finished_at=now(),summary=jsonb_build_object('transition',v_summary) where id=sa;
 sc:=public.sim_create_season('15151515-0000-0000-0000-0000000000a1','BRA');
 select array_agg(sp.club_id order by sp.club_id) into actual from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id
 where sp.season_id=sc and sp.competition_id='libertadores' and cl.region='BRA';
 assert actual=array(select x from unnest(q) x order by x),'Vagas não vieram da tabela final individual';
 assert (select count(*) from public.season_participants where season_id=sc and competition_id='copa_brasil')=16,'Copa nacional sem 16 classificados';
 assert not exists(select 1 from public.season_participants sp where sp.season_id=sc and sp.competition_id='copa_brasil' and not exists(select 1 from public.season_final_tables ft cross join lateral jsonb_array_elements(ft.standings) t where ft.season_id=sa and ft.competition_id='brasileirao' and t->>'club_id'=sp.club_id and (t->>'pos')::int<=16)),'Copa do Brasil sem mérito esportivo';
 assert not exists(select 1 from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id where sp.season_id=sc and sp.competition_id='libertadores'
   group by sp.group_label,cl.country having count(*)>1),'Grupo com compatriotas';
 assert not exists(select 1 from public.season_participants where season_id=sc and competition_id='libertadores' group by group_label,seed having count(*)<>1),'Grupo com pote repetido';
 assert (select count(*) from public.season_transitions where from_season=sa)=1,'Transição duplicada';
 assert not exists(select 1 from public.season_transitions where from_season=(select v from test_seasons where k='b')),'Histórico de outro usuário alterado';
 raise notice 'PASS tabela final, classificação por mérito, grupos e continuidade individual';
end $$;
rollback;
