-- Testes da evolução 32. Roda numa transação e desfaz tudo (ROLLBACK).
-- ATENÇÃO: teste do banco LOCAL descartável (scripts/test-seasons-db.py). Não rode no Supabase de produção:
-- ele usa carreiras fictícias de teste. Em produção, use supabase/releases/diagnostico_elenco.sql.
do $guard$ begin
 if not exists(select 1 from public.careers where id='31313131-0000-0000-0000-000000000011') then
  raise exception 'Este arquivo é só para o banco de teste local (carreiras fictícias). Nada foi alterado. Em produção, rode supabase/releases/diagnostico_elenco.sql.';
 end if;
end $guard$;
begin;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
select public.mgr_hub() is not null;
do $test$
#variable_conflict use_column
declare car uuid:='31313131-0000-0000-0000-000000000011';own text;pid text;pid2 text;other text;fx bigint;base numeric;low numeric;n int;r jsonb;cash0 bigint;cash1 bigint;
 d date;ct public.cw_contracts;num int;used int;nid uuid;
begin
 select club_id into own from public.mgr_coach where career_id=car;
 if own is null then raise exception 'Carreira de teste sem clube';end if;
 update public.cw_world set needs_sync=false where career_id=car;

 -- 1) elenco devolve satisfação, contrato, número e limite
 r:=public.mgr_squad();
 if not (r ? 'squad') or (r->'squad'->>'limit')::int<>40 then raise exception 'Limite de elenco ausente: %',r->'squad';end if;
 if exists(select 1 from jsonb_array_elements(r->'players') e where not(e ? 'morale') or not(e ? 'contract_expires') or e->>'number' is null) then raise exception 'Elenco sem satisfação/contrato/número';end if;
 raise notice 'PASS elenco com satisfação, contrato, número e limite (%/%)',r->'squad'->>'count',r->'squad'->>'limit';

 -- 2) satisfação afeta o rendimento individual na súmula
 if abs(public.cw_morale_factor(0)-.88)>.001 or public.cw_morale_factor(60)<>1 or abs(public.cw_morale_factor(100)-1.03)>.001 then raise exception 'Curva de satisfação';end if;
 select f.id into fx from public.season_fixtures f join public.cw_fixture_dates fd on fd.fixture_id=f.id where fd.career_id=car and f.status='pending' and own not in(f.home_club,f.away_club)
  and not exists(select 1 from public.mgr_matches m where m.fixture_id=f.id) order by fd.due_on limit 1;
 select home_club into other from public.season_fixtures where id=fx;
 update public.cw_players cp set morale=10 from public.mgr_players mp where mp.career_id=car and mp.club_id=other and cp.career_id=car and cp.player_id=mp.player_id;
 perform public.mgr_match_create(fx,car,null,null);
 select mp.player_id,mp.c_att into pid,low from public.mgr_match_players mp where mp.fixture_id=fx and mp.club_id=other and mp.starter order by mp.player_id limit 1;
 select 0.35*a.finishing+0.25*a.off_ball+0.20*a.dribbling+0.20*a.pace into base from public.sim_player_attrs a where a.player_id=pid;
 if low is null then raise notice 'SKIP atleta não relacionado para a partida';
 elsif abs(low-round(base*public.cw_morale_factor(10),2))>.02 then raise exception 'Insatisfação não reduziu o rendimento: % vs %',low,base;
 else raise notice 'PASS insatisfação reduz o rendimento individual (% → %)',round(base,2),low;end if;

 -- 3) número de camisa sem repetir no novo clube
 select mp.player_id into pid2 from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
  where mp.career_id=car and mp.club_id=other and sp.shirt_number is not null
   and exists(select 1 from public.mgr_players m2 join public.sim_players s2 on s2.id=m2.player_id where m2.career_id=car and m2.club_id=own and s2.shirt_number=sp.shirt_number) limit 1;
 if pid2 is not null then
  update public.mgr_players set club_id=own where career_id=car and player_id=pid2;
  num:=public.cw_shirt_number(car,pid2);
  select count(*) into used from public.mgr_players mp where mp.career_id=car and mp.club_id=own and public.cw_shirt_number(car,mp.player_id)=num;
  if used<>1 then raise exception 'Número % repetido no novo clube',num;end if;
  if not exists(select 1 from jsonb_array_elements(public.mgr_squad()->'players') e where e->>'id'=pid2 and (e->>'number')::int=num) then raise exception 'Carta não mostra o novo número';end if;
  raise notice 'PASS carta do atleta transferido usa número livre no novo clube (%)',num;
  update public.mgr_players set club_id=other where career_id=car and player_id=pid2;
 end if;

 -- 4) limite de elenco na compra
 update public.cw_rules set rules=rules||'{"squad_limit":5}';
 select mp.player_id into pid from public.mgr_players mp join public.cw_players cp using(career_id,player_id) where mp.career_id=car and mp.club_id=other and public.cw_age(car,mp.player_id)>=21 limit 1;
 begin perform public.career_transfer_bid(pid,1000,1,0,false,gen_random_uuid());raise exception 'Comprou com elenco cheio';
 exception when raise_exception then if sqlerrm not like 'Elenco cheio%' then raise;end if;end;
 update public.cw_rules set rules=rules||'{"squad_limit":40}';
 raise notice 'PASS limite de elenco bloqueia nova contratação de adulto';

 -- 5) rescisão: paga até seis salários e o atleta fica livre
 select ct.* into ct from public.cw_contracts ct where ct.career_id=car and ct.club_id=own and ct.status='active' order by ct.monthly_salary limit 1;
 update public.cw_clubs set cash=cash+10000000 where career_id=car and club_id=own;
 select cash into cash0 from public.cw_clubs where career_id=car and club_id=own;
 r:=public.career_player_release(ct.player_id,gen_random_uuid());
 select cash into cash1 from public.cw_clubs where career_id=car and club_id=own;
 if cash0-cash1<>(r->>'cost')::bigint or (r->>'cost')::bigint>ct.monthly_salary*6+ct.arrears then raise exception 'Custo de rescisão incorreto';end if;
 if (select club_id from public.mgr_players where career_id=car and player_id=ct.player_id) is not null then raise exception 'Atleta não ficou livre';end if;
 raise notice 'PASS rescisão paga % e libera o atleta',r->>'cost';

 -- 6) lista de transferências gera proposta de outro clube (janela aberta)
 select mp.player_id into pid from public.mgr_players mp where mp.career_id=car and mp.club_id=own order by mp.player_id limit 1;
 perform public.career_player_list(pid,true);
 if not (select transfer_listed from public.cw_players where career_id=car and player_id=pid) then raise exception 'Lista não gravada';end if;
 select today into d from public.cw_world where career_id=car;
 update public.cw_world set today=make_date(extract(year from d)::int,1,10) where career_id=car;
 for n in 1..40 loop
  perform public.cw_v32_tick(car);
  exit when exists(select 1 from public.cw_negotiations where career_id=car and player_id=pid and seller_club=own and status='seller_review');
 end loop;
 if not exists(select 1 from public.cw_negotiations where career_id=car and player_id=pid and seller_club=own and status='seller_review') then raise exception 'Atleta listado não recebeu proposta';end if;
 raise notice 'PASS atleta listado recebe proposta para sua decisão';

 -- 7) contrato no fim: pré-contrato com outro clube e saída de graça
 select ct.* into ct from public.cw_contracts ct where ct.career_id=car and ct.club_id=own and ct.status='active' and ct.player_id<>pid
  and not exists(select 1 from public.cw_negotiations n where n.career_id=car and n.player_id=ct.player_id) order by ct.player_id limit 1;
 update public.cw_world set today=make_date(extract(year from d)::int+1,3,1) where career_id=car;
 select today into d from public.cw_world where career_id=car;
 update public.cw_contracts set expires_on=d+40 where id=ct.id;
 update public.cw_players set morale=40 where career_id=car and player_id=ct.player_id;
 for n in 1..40 loop
  perform public.cw_v32_tick(car);
  exit when exists(select 1 from public.cw_negotiations where career_id=car and player_id=ct.player_id and status='precontract');
 end loop;
 select id into nid from public.cw_negotiations where career_id=car and player_id=ct.player_id and status='precontract';
 if nid is null then raise exception 'Sem pré-contrato para contrato no fim';end if;
 begin perform public.career_contract_renew(ct.player_id,gen_random_uuid());raise exception 'Renovou após pré-contrato';
 exception when raise_exception then if sqlerrm not like '%compromisso firmado%' then raise;end if;end;
 update public.cw_world set today=d+41,needs_sync=false where career_id=car;
 perform public.cw_finance_tick(car);perform public.cw_market_tick(car);
 if (select status from public.cw_negotiations where id=nid)<>'completed' then raise exception 'Pré-contrato não registrado: %',(select status||' '||coalesce(response,'') from public.cw_negotiations where id=nid);end if;
 if (select club_id from public.mgr_players where career_id=car and player_id=ct.player_id)=own then raise exception 'Atleta continuou no clube';end if;
 if (select fee from public.cw_negotiations where id=nid)<>0 then raise exception 'Saída deveria ser de graça';end if;
 raise notice 'PASS contrato não renovado: pré-contrato e saída de graça para %',(select buyer_club from public.cw_negotiations where id=nid);

 -- 8) renovação respeita o limite de 5 anos
 select ct.* into ct from public.cw_contracts ct where ct.career_id=car and ct.club_id=own and ct.status='active'
  and not exists(select 1 from public.cw_negotiations n where n.career_id=car and n.player_id=ct.player_id and n.status in('agreed','precontract')) limit 1;
 r:=public.career_contract_renew(ct.player_id,gen_random_uuid());
 begin perform public.career_player_offer((r->>'id')::uuid,ct.monthly_salary*2,6,0,'starter',0,0,gen_random_uuid());raise exception 'Aceitou contrato de 6 anos';
 exception when raise_exception then if sqlerrm<>'Contrato inválido' then raise;end if;end;
 raise notice 'PASS renovação limitada a 5 anos';

 -- 9) clube à beira da falência: demissão por irresponsabilidade financeira
 update public.cw_coach_contracts set starts_on=d-200 where career_id=car and ended_on is null;
 select today into d from public.cw_world where career_id=car;
 update public.cw_clubs set financial_risk=95,distress_since=d-30 where career_id=car and club_id=own;
 perform public.cw_v32_tick(car);
 if (select status from public.mgr_coach where career_id=car)<>'unemployed' then raise exception 'Treinador não foi demitido com o clube falindo';end if;
 raise notice 'PASS demissão por irresponsabilidade financeira';
end $test$;
rollback;
