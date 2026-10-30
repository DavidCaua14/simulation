begin;
create temp table protected_fixtures as select id,to_jsonb(f) as data from public.season_fixtures f where status='played';
create temp table protected_live as select fixture_id,to_jsonb(m) as data from public.mgr_matches m where status='live';
create temp table protected_players as select career_id,player_id,to_jsonb(mp) as data from public.mgr_players mp;
create temp table protected_wallet as select id,coins,diamonds,bonus_energy,xp from public.careers;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
select public.mgr_hub() is not null;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000002',true);
select public.mgr_hub() is not null;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
do $test$
#variable_conflict use_column
declare c1 uuid:='31313131-0000-0000-0000-000000000011';c2 uuid:='31313131-0000-0000-0000-000000000022';pid text;pid2 text;old_club text;v_id uuid;v_id2 uuid;res jsonb;ct public.cw_contracts;req uuid:=gen_random_uuid();v_cash bigint;v_coins int;v_pay bigint;d date;other_club text;
begin
 if exists(select 1 from protected_wallet b join public.careers c using(id) where row(b.coins,b.diamonds,b.bonus_energy,b.xp) is distinct from row(c.coins,c.diamonds,c.bonus_energy,c.xp)) then raise exception 'Initialization rewrote balances';end if;
 if exists(select 1 from protected_fixtures b join public.season_fixtures f using(id) where b.data<>to_jsonb(f)) then raise exception 'Initialization rewrote results';end if;
 if exists(select 1 from protected_players b join public.mgr_players mp using(career_id,player_id) where b.data<>to_jsonb(mp)) then raise exception 'Initialization rewrote player condition or assignment';end if;
 if exists(select 1 from protected_live b join public.mgr_matches m using(fixture_id) where b.data<>to_jsonb(m)) then raise exception 'Initialization rewrote live matches';end if;
 if(select count(*) from public.cw_world where career_id in(c1,c2))<>2 or(select count(*) from public.cw_seasons where career_id=c1)<>2 then raise exception 'Parallel regions missing';end if;
 if exists(select 1 from public.mgr_players mp where mp.career_id=c1 and mp.club_id is not null and not exists(select 1 from public.cw_contracts ct where ct.career_id=c1 and ct.player_id=mp.player_id and ct.club_id=mp.club_id and status='active')) then raise exception 'Player without owned contract';end if;
 if jsonb_array_length(public.career_player_search())<>30 then raise exception 'Global search failed';end if;
 if not exists(select 1 from jsonb_array_elements(public.career_player_search('', '', 'ENG')) x where x->>'club_id'='arsenal') then raise notice 'European page has other top clubs';end if;
 if exists(select 1 from jsonb_array_elements(public.career_player_search('','','','','10000000'::bigint,0,'ENG')) x where (select country from public.sim_clubs where id=x->>'club_id')<>'ENG') then raise exception 'Global country filter ignored';end if;
 -- Dates and fixtures have a single owner; two clubs cannot occupy the same date twice.
 if exists(select 1 from public.cw_club_dates group by career_id,club_id,due_on having count(*)>1) then raise exception 'Calendar collision';end if;
 update public.cw_world set today='2026-01-10',needs_sync=false where career_id=c1;
 update public.cw_clubs set cash=5000000 where career_id=c1 and club_id='flamengo';
 select mp.player_id,mp.club_id into pid,old_club from public.mgr_players mp join public.sim_clubs sc on sc.id=mp.club_id where mp.career_id=c1 and public.cw_region(mp.club_id)='ENG' and mp.club_id<>'arsenal' and (select count(*) from public.mgr_players y where y.career_id=c1 and y.club_id=mp.club_id)>20 order by public.cw_player_value(c1,mp.player_id) limit 1;
 select club_id into other_club from public.mgr_players where career_id=c2 and player_id=pid;
 res:=public.career_transfer_bid(pid,1000000,3,100,false,req);v_id:=(res->>'id')::uuid;
 if (public.career_transfer_bid(pid,1000000,3,100,false,req)->>'id')::uuid<>v_id then raise exception 'Duplicate request';end if;
 update public.cw_negotiations set decision_roll=.5 where cw_negotiations.id=v_id;
 update public.cw_world set today=today+2 where career_id=c1;perform public.cw_market_tick(c1);
 if(select status from public.cw_negotiations where cw_negotiations.id=v_id)<>'player_counter' then raise exception 'Club approval failed: %',(select status from public.cw_negotiations where cw_negotiations.id=v_id);end if;
 perform public.career_player_offer(v_id,10000,3,500,'starter',10,5,gen_random_uuid());
 if (select club_id from public.mgr_players where career_id=c1 and player_id=pid)<>old_club then raise exception 'Moved before player accepted';end if;
 update public.cw_world set today=today+2 where career_id=c1;perform public.cw_market_tick(c1);
 if (select status from public.cw_negotiations where cw_negotiations.id=v_id)<>'completed' then raise exception 'Transfer not completed: %',(select status||':'||response from public.cw_negotiations where cw_negotiations.id=v_id);end if;
 if (select club_id from public.mgr_players where career_id=c1 and player_id=pid)<>'flamengo' then raise exception 'Wrong destination';end if;
 if (select club_id from public.mgr_players where career_id=c2 and player_id=pid) is distinct from other_club then raise exception 'Transfer leaked across careers';end if;
 if (select count(*) from public.cw_contracts where career_id=c1 and player_id=pid and status='active')<>1 then raise exception 'Multiple contracts';end if;
 if(select count(*) from public.cw_commitments where negotiation_id=v_id and kind='installment' and status='reserved')<>2 then raise exception 'Installments missing';end if;
 select cash into v_cash from public.cw_clubs where career_id=c1 and club_id='flamengo';
 perform public.cw_register_transfer(v_id);perform public.cw_market_tick(c1);
 if (select c.cash from public.cw_clubs c where career_id=c1 and club_id='flamengo')<>v_cash then raise exception 'Transfer paid twice';end if;
 if(select count(*) from public.mgr_transfers where career_id=c1 and player_id=pid and to_club='flamengo')<>1 then raise exception 'Transfer duplicated';end if;
 if (select coalesce(sum(amount),0) from public.cw_commitments where negotiation_id=v_id and kind='installment')-(select amount from public.cw_finance where career_id=c1 and club_id='flamengo' and kind='transfer' and reference=v_id||':0')<>1000000 then raise exception 'Installments do not conserve agreed fee';end if;
 -- No base-card synchronization can undo a legal sale.
 perform public.mgr_sync_base_cards(c1);
 if(select club_id from public.mgr_players where career_id=c1 and player_id=pid)<>'flamengo' then raise exception 'Base sync rewrote assignment';end if;
 -- Renewal changes the contract without a player sale, and salaries remain versioned.
 res:=public.career_contract_renew(pid,gen_random_uuid());v_id2:=(res->>'id')::uuid;
 update public.cw_negotiations set decision_roll=.5 where cw_negotiations.id=v_id2;
 perform public.career_player_offer(v_id2,12000,2,0,'starter',0,0,gen_random_uuid());
 update public.cw_world set today=today+2 where career_id=c1;perform public.cw_market_tick(c1);
 if(select status from public.cw_negotiations where cw_negotiations.id=v_id2)<>'completed' then raise exception 'Renewal failed';end if;
 if(select count(*) from public.cw_contracts where career_id=c1 and player_id=pid and status='active')<>1 then raise exception 'Renewal duplicates active contract';end if;
 -- Month settlement and club investment are idempotent and separate personal funds.
 select c.coins into v_coins from public.careers c where c.id=c1;
 perform public.cw_settle_month(c1,'2026-01-01');select c.coins into v_pay from public.careers c where c.id=c1;
 if v_pay<=v_coins then raise exception 'Coach salary was not credited';end if;
 select c.cash into v_cash from public.cw_clubs c where career_id=c1 and club_id='flamengo';
 perform public.cw_settle_month(c1,'2026-01-01');
 if (select c.coins from public.careers c where c.id=c1)<>v_pay or (select c.cash from public.cw_clubs c where career_id=c1 and club_id='flamengo')<>v_cash then raise exception 'Monthly payroll duplicated';end if;
 req:=gen_random_uuid();perform public.career_club_invest(50,req);perform public.career_club_invest(50,req);
 if(select c.coins from public.careers c where c.id=c1)<>v_pay-50 or(select c.cash from public.cw_clubs c where career_id=c1 and club_id='flamengo')<>v_cash+50 then raise exception 'Investment not exactly once';end if;
 -- Foreign identifiers cannot select or mutate another career's negotiation.
 select mp.player_id into pid2 from public.mgr_players mp where mp.career_id=c1 and mp.club_id<> 'flamengo' limit 1;
 perform set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000002',true);
 begin perform public.career_transfer_respond(v_id,'reject',0,gen_random_uuid());raise exception 'FAILED foreign negotiation accepted';exception when others then if sqlerrm='FAILED foreign negotiation accepted' then raise;end if;end;
 perform set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
 -- News is immutable per event and read flags stay local.
 perform public.cw_news_add(c1,'test:dedup','world','Uma notícia','Texto');perform public.cw_news_add(c1,'test:dedup','world','Uma notícia','Texto');
 if(select count(*) from public.cw_news where career_id=c1 and event_key='test:dedup')<>1 then raise exception 'News duplicated';end if;
 -- Losing funding before final acceptance must leave the player and all payments untouched.
 update public.cw_clubs set cash=5000000 where career_id=c1 and club_id='flamengo';
 select mp.player_id into pid2 from public.mgr_players mp where mp.career_id=c1 and mp.club_id='chelsea' order by public.cw_player_value(c1,mp.player_id) limit 1;
 res:=public.career_transfer_bid(pid2,1000000,1,0,false,gen_random_uuid());v_id2:=(res->>'id')::uuid;
 update public.cw_negotiations set decision_roll=.5 where id=v_id2;
 update public.cw_world set today=today+2 where career_id=c1;perform public.cw_market_tick(c1);
 perform public.career_player_offer(v_id2,10000,3,0,'starter',0,0,gen_random_uuid());
 update public.cw_clubs set cash=0 where career_id=c1 and club_id='flamengo';
 update public.cw_world set today=today+2 where career_id=c1;perform public.cw_market_tick(c1);
 if(select status from public.cw_negotiations where id=v_id2)<>'failed_funds' or(select club_id from public.mgr_players where career_id=c1 and player_id=pid2)<>'chelsea' or exists(select 1 from public.cw_commitments where negotiation_id=v_id2 and status='reserved') then raise exception 'Funding failure corrupted transfer';end if;
 select * into ct from public.cw_contracts where career_id=c1 and club_id='arsenal' and status='active' order by monthly_salary limit 1;
 insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,valuation,monthly_salary,contract_years,created_on,reply_on,expires_on,agreed_owner_contract,decision_roll)
 select c1,ct.player_id,'arsenal','flamengo','user','player_pending',10000,10000,100000,3,today,today,today+7,ct.id,.01 from public.cw_world where career_id=c1 returning id into v_id2;
 perform public.cw_market_tick(c1);
 if(select status from public.cw_negotiations where id=v_id2)<>'rejected' or(select response from public.cw_negotiations where id=v_id2) not like '%projeto%' then raise exception 'Higher salary guaranteed a project acceptance';end if;
 perform public.cw_simulate_due(c1,1);
 if not exists(select 1 from public.cw_appearances where career_id=c1) then raise exception 'AI appearance archive missing';end if;
 if exists(select 1 from public.mgr_matches m where m.career_id=c1 and m.status='finished' and m.minute<90 and m.fixture_id in(select fixture_id from public.cw_appearances where career_id=c1)) then raise exception 'AI match stopped at halftime';end if;
 raise notice 'PASS foundation, parallel regions, international purchase, athlete approval, installments, renewal, per-career isolation, monthly payroll, investment and idempotency';
end $test$;
do $$declare f record;begin
 for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and(p.proname like 'cw\_%' escape '\' or p.proname like '%before_world%') loop
 if has_function_privilege('authenticated',f.sig,'execute') or has_function_privilege('anon',f.sig,'execute') then raise exception 'Exposed helper: %',f.sig;end if;end loop;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
do $$begin
 if exists(select 1 from public.cw_world where career_id<>'31313131-0000-0000-0000-000000000011') or exists(select 1 from public.cw_contracts where career_id<>'31313131-0000-0000-0000-000000000011') then raise exception 'RLS leaks a career';end if;
 begin update public.cw_clubs set cash=999;raise exception 'FAILED client write';exception when insufficient_privilege then null;end;
 begin perform decision_roll from public.cw_negotiations limit 1;raise exception 'FAILED exposed AI roll';exception when insufficient_privilege then null;end;
 raise notice 'PASS RLS and private helper ACLs';
end $$;
reset role;
rollback;
