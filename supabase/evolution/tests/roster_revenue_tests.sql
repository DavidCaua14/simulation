-- Disposable local database only; real registration and lineup actions use a synthetic career and roll back.
do $$ begin if current_database() not like 'simulation_validation_%' then raise exception 'Disposable local database required';end if;end $$;
begin;
insert into auth.users(id,email) values('57570000-0000-0000-0000-000000000001','roster-revenue@example.test');
insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins,level,xp)
 values('57570000-0000-0000-0000-000000000011','57570000-0000-0000-0000-000000000001','RosterRevenueTest','cuiaba','1',30,12345,3,250);
select set_config('request.jwt.claim.sub','57570000-0000-0000-0000-000000000001',true);
select public.career_runtime_initialize() is not null;
do $test$
#variable_conflict use_column
declare cid uuid:='57570000-0000-0000-0000-000000000011';d date:='2026-01-05';pid text;oid uuid;rid uuid;r jsonb;deal jsonb;s jsonb;rev text;wage bigint;cash bigint;wallet int;bench text[];sid uuid;fx bigint;comp text;gate bigint;prize bigint;invoice jsonb;
begin
 update public.cw_world set today=d,needs_sync=false where career_id=cid;
 update public.cw_clubs set cash=20000000,debt=0,financial_risk=0,monthly_revenue=1000000 where career_id=cid;
 rev:=public.career_world_status()->>'roster_revision';
 select mp.player_id into pid from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
  where mp.career_id=cid and mp.club_id<>'cuiaba' and sp.position in('ZAG','MC','GOL') and pr.rating between 60 and 68 order by mp.player_id limit 1;
 if pid is null then raise exception 'Missing ordinary target';end if;
 update public.cw_contracts set status='expired',starts_on=d-365,expires_on=d-1,ended_on=d-1 where career_id=cid and player_id=pid and status='active';
 update public.mgr_players set club_id=null,condition=92,rhythm=77 where career_id=cid and player_id=pid;
 wage:=public.cw_salary_demand(cid,pid,'cuiaba')*2;
 r:=public.career_free_agent_offer(pid,wage,2,2*wage,'rotation',0,0,gen_random_uuid());oid:=(r->>'id')::uuid;
 select x into deal from jsonb_array_elements(public.career_negotiations())x where x->>'id'=oid::text;
 if deal->>'arrival_status'<>'player_decision' then raise exception 'Pending proposal shown as registered';end if;
 -- Reproduce an incomplete personal-state row without rewriting any existing skill or career history.
 delete from public.cw_players where career_id=cid and player_id=pid;
 update public.cw_negotiations set reply_on=d,decision_roll=.9 where id=oid;
 perform public.cw_market_tick(cid);
 if not exists(select 1 from public.cw_negotiations where id=oid and status='completed') then raise exception 'Player did not register: %',(select response from public.cw_negotiations where id=oid);end if;
 if public.career_world_status()->>'roster_revision'=rev then raise exception 'Same-day registration did not invalidate roster';end if;
 s:=public.mgr_squad();
 if not exists(select 1 from jsonb_array_elements(s->'players')p where p->>'id'=pid and(p->>'available')::boolean and p->>'club_id'='cuiaba') then raise exception 'Registered player missing from selectable squad';end if;
 if not exists(select 1 from public.mgr_players where career_id=cid and player_id=pid and condition=92 and rhythm=77) then raise exception 'Registration reset personal fitness';end if;
 select x into deal from jsonb_array_elements(public.career_negotiations())x where x->>'id'=oid::text;
 if deal->>'arrival_status'<>'registered' then raise exception 'Completed arrival is not linked to squad';end if;
 select coalesce(array_agg(value),array[]::text[]) into bench from jsonb_array_elements_text(s->'lineup'->'bench');
 bench[1]:=pid;
 perform public.mgr_lineup_save(s->'lineup'->>'formation',s->'lineup'->'slots',to_jsonb(bench),s->'lineup'->'tactics');
 if not exists(select 1 from public.mgr_lineups where career_id=cid and club_id='cuiaba' and pid=any(bench)) then raise exception 'New registration cannot be selected in actual lineup';end if;
 select cash into cash from public.cw_clubs where career_id=cid and club_id='cuiaba';select coins into wallet from public.careers where id=cid;
 perform public.cw_register_transfer(oid);
 if(select cash from public.cw_clubs where career_id=cid and club_id='cuiaba')<>cash or(select coins from public.careers where id=cid)<>wallet then raise exception 'Viewing/retrying registration charged again';end if;
 -- Agreed does not mean registered: the closed-window agreement remains saved without moving its player.
 insert into public.cw_negotiations(career_id,player_id,buyer_club,initiator,status,fee,valuation,monthly_salary,contract_years,created_on,reply_on,expires_on,register_on)
  values(cid,pid,'cuiaba','user','agreed',0,1000,wage,2,d,d,d+7,'2026-07-10') returning id into rid;
 update public.cw_world set today='2026-05-05' where career_id=cid;
 select x into deal from jsonb_array_elements(public.career_negotiations())x where x->>'id'=rid::text;
 if deal->>'arrival_status'<>'waiting_window' or deal->>'register_on'<>'2026-07-10' then raise exception 'Pending registration date not explained';end if;
 perform public.cw_neg_close(rid,'rejected','Fixture cleanup');
 update public.cw_world set today=d where career_id=cid;
 -- Income is anchored to club size. Extreme prestige never turns a small club's gate into millions.
 if public.cw_match_gate(cid,'cuiaba','brasileirao')<>250 or public.cw_match_prize(cid,'cuiaba','brasileirao')<>125 then raise exception 'Cuiaba ordinary income out of scale';end if;
 update public.cw_clubs set prestige=100 where career_id=cid and club_id='cuiaba';
 if public.cw_match_gate(cid,'cuiaba','brasileirao')>300 or public.cw_match_prize(cid,'cuiaba','brasileirao')>175
  or public.cw_match_gate(cid,'cuiaba','libertadores')>375 or public.cw_match_prize(cid,'cuiaba','libertadores')>200 then raise exception 'Small club bypassed economic ceiling';end if;
 if public.cw_match_gate(cid,'flamengo','brasileirao') not between 1000 and 3000 then raise exception 'Large club gate collapsed';end if;
 update public.cw_clubs set prestige=60 where career_id=cid and club_id='cuiaba';
 select primary_season into sid from public.cw_world where career_id=cid;
 select id,competition_id into fx,comp from public.season_fixtures where season_id=sid and home_club='cuiaba' and status='pending' and stage='league' order by id limit 1;
 gate:=public.cw_match_gate(cid,'cuiaba',comp);prize:=public.cw_match_prize(cid,'cuiaba',comp);
 select cash into cash from public.cw_clubs where career_id=cid and club_id='cuiaba';
 update public.season_fixtures set status='played',home_goals=2,away_goals=0,player_match=false,played_at=now() where id=fx;
 invoice:=public.cw_fixture_income(fx,'cuiaba');
 if(invoice->>'gate')::bigint<>gate or(invoice->>'prize')::bigint<>prize or(invoice->>'operations')::bigint<>-ceil(gate*.2)::bigint
  or(invoice->>'total')::bigint<>gate+prize-ceil(gate*.2)::bigint then raise exception 'Club statement does not reconcile';end if;
 update public.season_fixtures set home_goals=home_goals where id=fx;
 if(select cash from public.cw_clubs where career_id=cid and club_id='cuiaba')<>cash+(invoice->>'total')::bigint then raise exception 'Receipt replay duplicated revenue';end if;
 if(select today from public.cw_world where career_id=cid)<>d or(select coins from public.careers where id=cid)<>wallet then raise exception 'Revenue or squad view affected date/personal wallet';end if;
 raise notice 'PASS registered transfer to actual lineup, same-day roster revision, missing state repair, replay safety, explicit arrival stages, small-club ceilings, realistic future receipts and reconciled match statement';
end $test$;
rollback;
