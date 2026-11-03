-- Disposable local database; every fixture, transfer and monthly settlement rolls back.
do $$ begin if current_database() not like 'simulation_validation_%' then raise exception 'Disposable local database required';end if;end $$;
begin;
insert into auth.users(id,email) values('54540000-0000-0000-0000-000000000001','club-economy@example.test');
insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins,level,xp)
 values('54540000-0000-0000-0000-000000000011','54540000-0000-0000-0000-000000000001','ClubEconomyTest','sport','1',30,12345,3,250);
select set_config('request.jwt.claim.sub','54540000-0000-0000-0000-000000000001',true);
select public.career_runtime_initialize() is not null;
do $test$
#variable_conflict use_column
declare cid uuid:='54540000-0000-0000-0000-000000000011';d date:='2026-01-05';sid uuid;fx bigint;fx2 bigint;pid text;p2 text;
 r jsonb;r2 jsonb;req uuid;oid uuid;wage bigint;coins_before int;energy_before int;cash_before bigint;away_before bigint;opponent text;gate bigint;prize bigint;invoice jsonb;monthly bigint;post_month bigint;starting_contracts int;
begin
 update public.cw_world set today=d,needs_sync=false where career_id=cid;
 select primary_season into sid from public.cw_world where career_id=cid;
 if public.cw_money_label(80)<>'R$ 80.000' or public.cw_money_label(100)<>'R$ 100.000' then raise exception 'Stored salary denomination changed';end if;
 if public.cw_salary_floor('lamine-yamal-esp')*1000<1000000 then raise exception 'Elite salary is below the requested scale';end if;
 gate:=public.cw_match_gate(cid,'sport','brasileirao');
 if gate*1000 not between 200000 and 300000 or public.cw_match_gate(cid,'flamengo','brasileirao')*1000 not between 1000000 and 3000000 then raise exception 'Stadium estimates outside requested ranges';end if;
 select coins,bonus_energy into coins_before,energy_before from public.careers where id=cid;
 select cash into cash_before from public.cw_clubs where career_id=cid and club_id='sport';
 perform public.cw_prepare_club_economy(cid,'sport');
 if(select cash from public.cw_clubs where career_id=cid and club_id='sport')<>cash_before then raise exception 'Commercial rebalance changed earned cash';end if;
 select monthly_revenue into monthly from public.cw_clubs where career_id=cid and club_id='sport';
 if monthly<public.cw_commercial_income('sport') then raise exception 'Commercial forecast not applied';end if;
 -- A real fixture update books the winning club's bonus and the home stadium, never personal coins.
 select id,away_club,competition_id into fx,opponent,p2 from public.season_fixtures where season_id=sid and home_club='sport' and stage='league' and status='pending' order by id limit 1;
 if fx is null then raise exception 'Missing home fixture';end if;
 select cash into away_before from public.cw_clubs where career_id=cid and club_id=opponent;
 gate:=public.cw_match_gate(cid,'sport',p2);prize:=public.cw_match_prize(cid,'sport',p2);
 update public.season_fixtures set status='played',home_goals=2,away_goals=0,player_match=true,coach_club='sport',played_at=now() where id=fx;
 perform public.base_award_match(fx);perform public.base_award_match(fx);
 invoice:=public.cw_fixture_income(fx,'sport');
 if(invoice->>'gate')::bigint<>gate or(invoice->>'prize')::bigint<>prize or(invoice->>'operations')::bigint<>-ceil(gate*.20)::bigint then raise exception 'Fixture income incorrect: %',invoice;end if;
 if(select cash from public.cw_clubs where career_id=cid and club_id='sport')<>cash_before+gate-ceil(gate*.20)::bigint+prize then raise exception 'Winning bonus not deposited in club cash';end if;
 if(select cash from public.cw_clubs where career_id=cid and club_id=opponent)<>away_before then raise exception 'Away losing club received gate/prize';end if;
 if(select coins from public.careers where id=cid)<>coins_before or(select coins from public.base_match_rewards where fixture_id=fx)<>0 then raise exception 'Football bonus leaked into personal coins';end if;
 if(select bonus_energy from public.careers where id=cid)<>energy_before+1 then raise exception 'Win energy reward lost or duplicated';end if;
 update public.season_fixtures set home_goals=home_goals where id=fx;
 if(select count(*) from public.cw_finance where career_id=cid and club_id='sport' and reference='match:'||fx)<>3 then raise exception 'Repeated result duplicated receipt';end if;
 -- Draws pay both clubs; stadium revenue still belongs only to the home club.
 select id,away_club,competition_id into fx2,opponent,p2 from public.season_fixtures where season_id=sid and home_club='sport' and stage='league' and status='pending' order by id limit 1;
 update public.season_fixtures set status='played',home_goals=1,away_goals=1,player_match=false,played_at=now() where id=fx2;
 if not exists(select 1 from public.cw_finance where career_id=cid and club_id=opponent and reference='match:'||fx2 and kind='match_prize' and amount>0)
  or exists(select 1 from public.cw_finance where career_id=cid and club_id=opponent and reference='match:'||fx2 and kind='matchday') then raise exception 'Draw gate/prize routing incorrect';end if;
 -- A free player receives one direct salary/signing offer, without seller fee or a second form.
 update public.cw_clubs set cash=20000000,debt=0,financial_risk=0 where career_id=cid and club_id='sport';
 select mp.player_id into pid from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
  where mp.career_id=cid and mp.club_id<>'sport' and pr.rating between 55 and 65 order by mp.player_id limit 1;
 select mp.player_id into p2 from public.mgr_players mp where career_id=cid and club_id<>'sport' and player_id<>pid order by player_id limit 1;
 update public.cw_contracts set status='expired',starts_on=d-365,expires_on=d-1,ended_on=d-1 where career_id=cid and player_id=pid and status='active';
 update public.mgr_players set club_id=null where career_id=cid and player_id=pid;
 wage:=public.cw_salary_demand(cid,pid,'sport');
 begin perform public.career_free_agent_offer(pid,1,3,0,'rotation',0,0,gen_random_uuid());raise exception 'Expected salary rejection';
 exception when raise_exception then if sqlerrm not like 'Salário mensal insuficiente.%R$%' then raise;end if;end;
 if exists(select 1 from public.cw_negotiations where career_id=cid and player_id=pid and buyer_club='sport') then raise exception 'Failed direct offer left partial negotiation';end if;
 req:=gen_random_uuid();r:=public.career_free_agent_offer(pid,wage,3,2*wage,'rotation',0,0,req);oid:=(r->>'id')::uuid;
 r2:=public.career_free_agent_offer(pid,wage,3,2*wage,'rotation',0,0,req);
 if(r-'replayed')<>(r2-'replayed') or not(r2->>'replayed')::boolean or not(r->>'direct')::boolean then raise exception 'Direct offer not replay-safe';end if;
 if not exists(select 1 from public.cw_negotiations where id=oid and seller_club is null and status='player_pending' and fee=0 and installments=1 and monthly_salary=wage and signing_bonus=2*wage)
  or(select count(*) from public.cw_negotiations where career_id=cid and player_id=pid and buyer_club='sport')<>1 then raise exception 'Free offer created seller stage or duplicate';end if;
 begin perform public.career_free_agent_offer(p2,100000,3,100000,'rotation',0,0,gen_random_uuid());raise exception 'Expected owned-player rejection';
 exception when raise_exception then if sqlerrm not like 'O atleta possui vínculo%' then raise;end if;end;
 update public.cw_negotiations set decision_roll=.5 where id=oid;
 update public.cw_world set today=d+2 where career_id=cid;
 perform public.cw_market_tick(cid);
 if not exists(select 1 from public.cw_negotiations where id=oid and status='completed') or(select club_id from public.mgr_players where career_id=cid and player_id=pid)<>'sport' then raise exception 'Direct free-agent signing did not complete';end if;
 perform public.career_free_agent_offer(pid,wage,3,2*wage,'rotation',0,0,req);
 if(select count(*) from public.cw_contracts where career_id=cid and player_id=pid and status='active')<>1 or(select count(*) from public.cw_finance where career_id=cid and kind='player_signing' and reference=oid::text)<>1 then raise exception 'Retried signature duplicated contract/signing bonus';end if;
 if exists(select 1 from public.cw_finance where career_id=cid and kind='transfer' and reference=oid||':0') then raise exception 'Free signing charged a transfer fee';end if;
 -- Month close has a single commercial entry, without adding stadium receipts a second time.
 perform public.cw_settle_month(cid,'2026-01-01');
 if(select amount from public.cw_finance where career_id=cid and club_id='sport' and kind='commercial' and reference='2026-01')<>monthly then raise exception 'Stadium revenue counted again in commercial settlement';end if;
 select cash into post_month from public.cw_clubs where career_id=cid and club_id='sport';
 perform public.cw_settle_month(cid,'2026-01-01');
 if(select cash from public.cw_clubs where career_id=cid and club_id='sport')<>post_month then raise exception 'Month paid twice';end if;
 if(select coins from public.careers where id=cid)>=coins_before+10000 then raise exception 'Coach salary inflated personal wallet by conversion factor';end if;
 raise notice 'PASS BRL denomination, stadium ranges, club-only result bonus, one receipt, retained energy, direct zero-fee free-agent offer, salary/ownership checks, one contract, monthly gate deduplication and personal wallet scale';
end $test$;
rollback;
-- Finish a live match through the public API, exercising the actual cached post-match summary.
begin;
insert into auth.users(id,email) values('54540000-0000-0000-0000-000000000002','club-live@example.test');
insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins)
 values('54540000-0000-0000-0000-000000000012','54540000-0000-0000-0000-000000000002','ClubLiveTest','sport','1',30,1000);
select set_config('request.jwt.claim.sub','54540000-0000-0000-0000-000000000002',true);
select public.career_runtime_initialize() is not null;
do $test$
declare cid uuid:='54540000-0000-0000-0000-000000000012';r jsonb;again jsonb;fx bigint;due date;i int;coins_before int;cash_after bigint;
begin
 select min(fd.due_on) into due from public.cw_fixture_dates fd join public.season_fixtures f on f.id=fd.fixture_id join public.cw_world w on w.primary_season=f.season_id
 where w.career_id=cid and f.status='pending' and 'sport' in(f.home_club,f.away_club);
 update public.cw_world set today=due,needs_sync=false where career_id=cid;
 select coins into coins_before from public.careers where id=cid;
 r:=public.mgr_match_start();fx:=(r->>'fixture_id')::bigint;
 for i in 1..12 loop
  exit when r->>'status'='finished';
  r:=public.mgr_match_step(fx,(r->>'minute')::int,120,null,true,0);
 end loop;
 if r->>'status' is distinct from 'finished' or r->'summary'->'rewards'->'club'->>'currency' is distinct from 'BRL' then raise exception 'Live summary missing real club income: %',r->'summary'->'rewards';end if;
 if(r->'summary'->'rewards'->>'coins')::int<>0 or(select coins from public.careers where id=cid)<>coins_before then raise exception 'Live win still credits personal wallet';end if;
 select cash into cash_after from public.cw_clubs where career_id=cid and club_id='sport';
 again:=public.mgr_match_step(fx,0,120,null,true,0);
 if again->'summary'<>r->'summary' or(select cash from public.cw_clubs where career_id=cid and club_id='sport')<>cash_after then raise exception 'Finished response replay changed summary or cash';end if;
 raise notice 'PASS live match: completed summary includes club BRL income, no personal coins and immutable replay';
end $test$;
rollback;
