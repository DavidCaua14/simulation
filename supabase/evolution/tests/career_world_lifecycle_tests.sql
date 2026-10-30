begin;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
select public.mgr_hub() is not null;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000002',true);
select public.mgr_hub() is not null;
do $test$
#variable_conflict use_column
declare c1 uuid:='31313131-0000-0000-0000-000000000011';c2 uuid:='31313131-0000-0000-0000-000000000022';pid text;v_id uuid;v_id2 uuid;ct public.cw_contracts;res jsonb;sid uuid;fprint text;before_debt bigint;before_cred numeric;old_club text;v_status text;before_personal int;coach_pay bigint;old_fired int;
begin
 -- English coach buys a Brazilian; the same pipeline is available in both directions.
 update public.cw_world set today='2026-07-15',needs_sync=false where career_id in(c1,c2);
 update public.cw_clubs set cash=10000000 where career_id in(c1,c2);
 select mp.player_id into pid from public.mgr_players mp join public.sim_clubs sc on sc.id=mp.club_id where mp.career_id=c2 and public.cw_region(mp.club_id)='BRA' and mp.club_id<>'flamengo' order by public.cw_player_value(c2,mp.player_id) limit 1;
 res:=public.career_transfer_bid(pid,1000000,1,0,false,gen_random_uuid());v_id:=(res->>'id')::uuid;
 update public.cw_negotiations set decision_roll=.5 where id=v_id;
 update public.cw_world set today=today+2 where career_id=c2;perform public.cw_market_tick(c2);
 perform public.career_player_offer(v_id,10000,3,200,'starter',0,0,gen_random_uuid());
 update public.cw_world set today=today+2 where career_id=c2;perform public.cw_market_tick(c2);
 if(select status from public.cw_negotiations where id=v_id)<>'completed' or(select club_id from public.mgr_players where career_id=c2 and player_id=pid)<>'arsenal' then raise exception 'BRA to ENG transfer failed';end if;
 -- Incoming offers cannot sell a user's athlete without a decision.
 select player_id into pid from public.mgr_players where career_id=c2 and club_id='arsenal' and player_id<>pid limit 1;
 select * into ct from public.cw_contracts where career_id=c2 and player_id=pid and status='active';
 insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,valuation,monthly_salary,contract_years,created_on,reply_on,expires_on,agreed_owner_contract,decision_roll)
 values(c2,pid,'arsenal','flamengo','ai','seller_review',100000,100000,10000,3,'2026-07-19','2026-07-19','2026-07-26',ct.id,.5) returning id into v_id;
 perform public.cw_reserve_offer(v_id);perform public.cw_market_tick(c2);
 if(select club_id from public.mgr_players where career_id=c2 and player_id=pid)<>'arsenal' then raise exception 'AI forced sale';end if;
 perform public.career_transfer_respond(v_id,'counter',110000,gen_random_uuid());
 update public.cw_world set today=today+2 where career_id=c2;perform public.cw_market_tick(c2);
 if(select club_id from public.mgr_players where career_id=c2 and player_id=pid)<>'flamengo' then raise exception 'Accepted incoming sale failed';end if;
 -- A pre-contract is signed now but cannot move the athlete before the old expiry.
 select x.* into ct from public.cw_contracts x join public.sim_clubs sc on sc.id=x.club_id where x.career_id=c2 and x.status='active' and x.club_id not in('arsenal','flamengo') and public.cw_region(x.club_id)='BRA' order by x.monthly_salary limit 1;
 update public.cw_contracts set expires_on='2026-09-03' where id=ct.id;
 res:=public.career_transfer_bid(ct.player_id,0,1,0,true,gen_random_uuid());v_id:=(res->>'id')::uuid;
 update public.cw_negotiations set decision_roll=.5 where id=v_id;
 perform public.career_player_offer(v_id,10000,2,500,'starter',0,0,gen_random_uuid());
 update public.cw_world set today=today+2 where career_id=c2;perform public.cw_market_tick(c2);
 if(select status from public.cw_negotiations where id=v_id)<>'precontract' or(select club_id from public.mgr_players where career_id=c2 and player_id=ct.player_id)<>ct.club_id then raise exception 'Precontract moved before expiry';end if;
 update public.cw_world set today='2026-09-04' where career_id=c2;perform public.cw_finance_tick(c2);perform public.cw_market_tick(c2);
 if(select status from public.cw_negotiations where id=v_id)<>'completed' or(select club_id from public.mgr_players where career_id=c2 and player_id=ct.player_id)<>'arsenal' then raise exception 'Precontract failed outside window';end if;
 -- Date expiry, not a request retry, closes pending deals and frees their resources.
 update public.cw_world set today='2027-01-15' where career_id=c2;
 select mp.player_id into pid from public.mgr_players mp where career_id=c2 and club_id='palmeiras' limit 1;
 res:=public.career_transfer_bid(pid,1000,1,0,false,gen_random_uuid());v_id:=(res->>'id')::uuid;
 update public.cw_world set today=today+8 where career_id=c2;perform public.cw_market_tick(c2);
 if(select status from public.cw_negotiations where id=v_id)<>'expired' or exists(select 1 from public.cw_commitments where negotiation_id=v_id and status='reserved') then raise exception 'Expiry failed';end if;
 update public.cw_world set today='2026-01-12' where career_id=c1;
 -- Job moves reuse the actual regional season and preserve all existing results.
 perform set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
 select md5(string_agg(to_jsonb(f)::text,'' order by f.id)) into fprint from public.season_fixtures f where status='played';
 select season_id into sid from public.cw_seasons where career_id=c1 and region='ENG';
 insert into public.season_offers(career_id,season_id,from_club,bonus_coins,pitch,kind,expires_day,salary,contract_years,budget_guarantee,expires_on)
 select c1,primary_season,'arsenal',100,'Teste internacional','coach',elapsed_days+7,200,2,100000,today+7 from public.cw_world where career_id=c1 returning id into v_id;
 perform public.career_job_negotiate(v_id,210,2,90000,gen_random_uuid());res:=public.mgr_offer_respond(v_id,true);
 if(select primary_season from public.cw_world where career_id=c1)<>sid or(select club_id from public.mgr_coach where career_id=c1)<>'arsenal' then raise exception 'Cross-region employment reset season';end if;
 if(select md5(string_agg(to_jsonb(f)::text,'' order by f.id)) from public.season_fixtures f where status='played') is distinct from fprint then raise exception 'Employment rewrote results';end if;
 if(select count(*) from public.mgr_spells where career_id=c1)<2 then raise exception 'Career history missing';end if;
 perform public.career_coach_renew(1,(select monthly_salary from public.cw_coach where career_id=c1),gen_random_uuid());
 -- A persistent financial crisis dismisses the coach; repeat ticks cannot dismiss twice.
 select credibility into before_cred from public.cw_coach where career_id=c1;
 update public.cw_clubs set cash=0,debt=100000000,distress_since='2025-01-01',rescue_year=2026 where career_id=c1 and club_id='arsenal';
 perform public.cw_finance_tick(c1);
 if(select status from public.mgr_coach where career_id=c1)<>'unemployed' or(select credibility from public.cw_coach where career_id=c1)>=before_cred then raise exception 'Financial dismissal failed';end if;
 perform public.cw_finance_tick(c1);
 if(select financial_dismissals from public.cw_coach where career_id=c1)<>1 then raise exception 'Duplicate dismissal';end if;
 update public.cw_clubs set cash=200000000 where career_id=c1 and club_id='arsenal';perform public.cw_finance_tick(c1);
 if(select debt from public.cw_clubs where career_id=c1 and club_id='arsenal')<>0 or not exists(select 1 from public.sim_clubs where id='arsenal') then raise exception 'Club recovery failed';end if;
 -- A zero-cash club records unpaid wages; paying arrears later credits the coach once.
 update public.cw_clubs set cash=0,monthly_revenue=0,debt=0 where career_id=c2 and club_id='arsenal';
 select coins into before_personal from public.careers where id=c2;
 select monthly_salary into coach_pay from public.cw_coach where career_id=c2;
 perform public.cw_settle_month(c2,'2026-08-01');
 if (select sum(arrears) from public.cw_contracts where career_id=c2 and club_id='arsenal')<=0 or (select debt from public.cw_clubs where career_id=c2 and club_id='arsenal')<=0 then raise exception 'Unpaid wages missing';end if;
 if(select coins from public.careers where id=c2)<>before_personal then raise exception 'Unfunded coach salary was credited';end if;
 update public.cw_clubs set cash=5000000 where career_id=c2 and club_id='arsenal';
 perform public.cw_repay_arrears(c2);perform public.cw_repay_arrears(c2);
 if(select coins from public.careers where id=c2)<>before_personal+coach_pay or(select sum(arrears) from public.cw_contracts where career_id=c2 and club_id='arsenal')<>0 then raise exception 'Arrears duplicated or unpaid';end if;
 -- A normal agreement crossing the closing date waits for the next window, not a pre-contract bypass.
 update public.cw_world set today='2027-02-03' where career_id=c2;
 select x.* into ct from public.cw_contracts x where x.career_id=c2 and x.club_id='palmeiras' and x.status='active' and x.expires_on>'2027-07-01' limit 1;
 insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,valuation,monthly_salary,contract_years,created_on,reply_on,expires_on,agreed_owner_contract,decision_roll)
 values(c2,ct.player_id,ct.club_id,'arsenal','user','player_pending',100000,10000,10000,3,'2027-01-31','2027-02-03','2027-02-07',ct.id,.5) returning id into v_id;
 perform public.cw_reserve_offer(v_id);perform public.cw_market_tick(c2);
 if(select status from public.cw_negotiations where id=v_id)<>'agreed' or(select register_on from public.cw_negotiations where id=v_id)<>date '2027-06-14' or(select club_id from public.mgr_players where career_id=c2 and player_id=ct.player_id)<>ct.club_id then raise exception 'Closed-window agreement bypassed registration';end if;
 update public.cw_world set today='2027-06-14' where career_id=c2;perform public.cw_market_tick(c2);
 if(select status from public.cw_negotiations where id=v_id)<>'completed' then raise exception 'Agreement failed to register in new window';end if;
 -- Natural expiry is distinct from a dismissal and does not hurt credibility.
 select fired_count into old_fired from public.mgr_coach where career_id=c2;
 select credibility into before_cred from public.cw_coach where career_id=c2;
 update public.cw_coach set contract_until=(select today-1 from public.cw_world where career_id=c2) where career_id=c2;
 perform public.cw_jobs_tick(c2);
 if(select status from public.mgr_coach where career_id=c2)<>'unemployed' or(select fired_count from public.mgr_coach where career_id=c2)<>old_fired or(select credibility from public.cw_coach where career_id=c2)<>before_cred then raise exception 'Natural contract expiry treated as bad performance';end if;
 raise notice 'PASS both international directions, explicit incoming sale, precontract/expiry, international job without reset, financial dismissal/credibility and club recovery';
end $test$;
rollback;
