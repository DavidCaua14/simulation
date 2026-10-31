-- Only run in a disposable database. All test mutations roll back.
set track_functions='all';
begin;
insert into auth.users(id,email) values('45454545-0000-0000-0000-000000000001','scoped@example.test');
insert into public.careers(id,user_id,nickname,club_id,coins,energy,energy_reset_at,photo_id,age)
values('45454545-0000-0000-0000-000000000011','45454545-0000-0000-0000-000000000001','ScopedRuntimeTest','flamengo',12000,10,now(),'1',30);
select set_config('request.jwt.claim.sub','45454545-0000-0000-0000-000000000001',true);
select public.career_runtime_initialize() is not null;
do $test$
#variable_conflict use_column
declare cid uuid:='45454545-0000-0000-0000-000000000011';h jsonb;r jsonb;r2 jsonb;req uuid;f bigint;oid uuid;d date;before jsonb;count_before int;tries int;pid text;nid uuid;sid uuid;money_before int;score_one jsonb;score_two jsonb;return_season uuid;finance_club text;
begin
 if(select count(*) from public.cw_seasons where career_id=cid)<>1 then raise exception 'Inactive region was allocated';end if;
 if(select count(*) from public.mgr_players where career_id=cid)>2000 then raise exception 'Global roster was allocated';end if;
 select jsonb_build_object('career',to_jsonb(c),'world',to_jsonb(w)) into before from public.careers c join public.cw_world w on w.career_id=c.id where c.id=cid;
 h:=public.career_hub_read();h:=public.career_hub_read();
 if before<>(select jsonb_build_object('career',to_jsonb(c),'world',to_jsonb(w)) from public.careers c join public.cw_world w on w.career_id=c.id where c.id=cid) then raise exception 'Hub wrote progress';end if;
 if jsonb_array_length(public.career_player_search('','','ENG'))<>30 then raise exception 'Foreign catalogue unavailable';end if;
 select count(*) into count_before from public.mgr_players where career_id=cid;
 if exists(select 1 from public.cw_seasons where career_id=cid and region='ENG') then raise exception 'Search activated foreign league';end if;
 -- A lost response from before migration replays its legacy receipt, never its mutation.
 select today into d from public.cw_world where career_id=cid;req:=gen_random_uuid();
 insert into public.econ_requests(career_id,request_id,action,response) values(cid,req,'world_advance',jsonb_build_object('legacy_receipt',true,'days',3,'matches',2,'more',false,'today',d));
 r:=public.career_world_prepare(3,req,-1);r2:=public.career_world_prepare(3,req,-1);
 if r<>r2 or not(r->>'legacy_receipt')::boolean or(select today from public.cw_world where career_id=cid)<>d then raise exception 'Legacy request was applied twice';end if;
 r:=public.career_world_prepare(3,gen_random_uuid(),-1);
 if not(r->>'requires_refresh')::boolean or(select today from public.cw_world where career_id=cid)<>d then raise exception 'Unknown old request advanced after migration';end if;
 -- Resolving an inactive foreign year creates financial prizes, never its full mutable roster.
 begin
  select count(*) into count_before from public.mgr_players where career_id=cid;
  select coins into money_before from public.careers where id=cid;
  sid:=public.cw_create_region(cid,'ENG',2025);
  perform public.cw_summarize_region(cid,sid,'2026-06-30');
  if(select status from public.career_seasons where id=sid)<>'finished' or exists(select 1 from public.season_competitions where season_id=sid and status<>'finished') then raise exception 'Inactive foreign year did not finish';end if;
  if(select count(*) from public.mgr_players where career_id=cid)<>count_before or(select coins from public.careers where id=cid)<>money_before then raise exception 'Inactive year copied roster or rewarded account';end if;
  raise exception using errcode='P4501',message='rollback inactive year trial';
 exception when sqlstate 'P4501' then null;end;
 -- No attention pending, synchronize and reach the first local round.
 for tries in 1..12 loop
  if public.cw_attention(cid) is not null then perform public.career_attention_ack(public.cw_attention(cid)->>'key');end if;
  r:=public.career_world_advance(7,gen_random_uuid());
  exit when coalesce((r->>'stopped_for_match')::boolean,false) and not coalesce((r->>'more')::boolean,false);
 end loop;
 if not coalesce((r->>'stopped_for_match')::boolean,false) then raise exception 'Failed to reach next user match: %',r;end if;
 if not exists(select 1 from public.season_fixtures f join public.career_seasons s on s.id=f.season_id where s.career_id=cid and f.stats->>'simulation'='summary') then raise exception 'No summarized AI match';end if;
 if exists(select 1 from public.mgr_matches where career_id=cid and user_side is null) then raise exception 'AI engine states retained';end if;
 -- Identical saved state and fixture must give the same score, including shootouts.
 select fx.id into f from public.season_fixtures fx join public.cw_world w on w.primary_season=fx.season_id
 where w.career_id=cid and fx.status='pending' and 'flamengo' not in(fx.home_club,fx.away_club) order by fx.id limit 1;
 begin
  perform public.mgr_sim_fixture(f,cid);
  select jsonb_build_array(home_goals,away_goals,home_pens,away_pens,tie_winner) into score_one from public.season_fixtures where id=f;
  raise exception using errcode='P4501',message='rollback summary trial';
 exception when sqlstate 'P4501' then null;end;
 begin
  perform public.mgr_sim_fixture(f,cid);
  select jsonb_build_array(home_goals,away_goals,home_pens,away_pens,tie_winner) into score_two from public.season_fixtures where id=f;
  raise exception using errcode='P4501',message='rollback summary trial';
 exception when sqlstate 'P4501' then null;end;
 if score_one is distinct from score_two then raise exception 'Summary score is not deterministic';end if;
 begin
  perform public.mgr_match_create(f,cid,null,null);
  update public.mgr_matches set state=state||jsonb_build_object('summary_seed','fixed-shootout-test') where fixture_id=f;
  score_one:=to_jsonb(public.mgr_shootout(f,90));score_two:=to_jsonb(public.mgr_shootout(f,90));
  if score_one<>score_two then raise exception 'Shootout is not deterministic';end if;
  raise exception using errcode='P4501',message='rollback shootout trial';
 exception when sqlstate 'P4501' then null;end;
 -- A proposal blocks time movement; a repeated request returns its exact receipt.
 select today into d from public.cw_world where career_id=cid;
 insert into public.season_offers(career_id,season_id,from_club,bonus_coins,pitch,kind,expires_day,expires_on,salary,contract_years,budget_guarantee)
 select cid,primary_season,'santos',0,'Test offer','coach',elapsed_days+7,today+7,100,2,0 from public.cw_world where career_id=cid returning id into oid;
 req:=gen_random_uuid();r:=public.career_world_advance(7,req);r2:=public.career_world_advance(7,req);
 if r<>r2 or not(r->>'requires_attention')::boolean then raise exception 'Attention or idempotency failed';end if;
 if(select today from public.cw_world where career_id=cid)<>d then raise exception 'Skipped a decision';end if;
 if(select status from public.season_offers where id=oid)<>'pending' then raise exception 'Offer expired unseen';end if;
 begin perform public.career_world_advance(1,req);raise exception 'Expected idempotency parameter rejection';exception when raise_exception then if sqlerrm='Expected idempotency parameter rejection' then raise;end if;end;
 perform public.career_attention_ack(public.cw_attention(cid)->>'key');
 insert into public.season_offers(career_id,season_id,from_club,bonus_coins,pitch,kind,expires_day,expires_on,salary,contract_years,budget_guarantee)
 select cid,primary_season,'palmeiras',0,'Second offer','coach',elapsed_days+7,today+7,100,2,0 from public.cw_world where career_id=cid;
 perform public.career_attention_ack(public.cw_attention(cid)->>'key');
 if public.cw_attention(cid) is not null then raise exception 'Acknowledged proposals bounced back';end if;
 update public.season_offers set status='declined' where career_id=cid and status='pending';
 -- A pending job must not keep an already completed season active forever.
 begin
  perform public.mgr_end_spell(cid,'left');
  select primary_season into sid from public.cw_world where career_id=cid;
  update public.season_fixtures set status='played',home_goals=0,away_goals=0 where season_id=sid and status='pending';
  perform public.sim_advance(sid,'serie_b');
  update public.season_fixtures set status='played',home_goals=1,away_goals=0 where season_id=sid and status='pending';
  perform public.sim_advance(sid,'serie_b');
  for finance_club in select distinct club_id from public.season_participants where season_id=sid loop perform public.cw_ensure_club_finance(cid,finance_club);end loop;
  update public.season_competitions co set status='finished',champion_club=(select min(club_id) from public.season_participants p where p.season_id=sid and p.competition_id=co.competition_id),runner_up_club=(select max(club_id) from public.season_participants p where p.season_id=sid and p.competition_id=co.competition_id) where co.season_id=sid;
  insert into public.season_offers(career_id,season_id,from_club,bonus_coins,pitch,kind,expires_day,expires_on,salary,contract_years,budget_guarantee)
   select cid,primary_season,'santos',0,'Season boundary offer','coach',elapsed_days+7,today+7,100,2,0 from public.cw_world where career_id=cid;
  r:=public.career_world_advance(0,gen_random_uuid());
  if(select status from public.career_seasons where id=sid)<>'finished' or not(r->>'requires_attention')::boolean then raise exception 'Pending job prevented completed season closure';end if;
  raise exception using errcode='P4501',message='rollback completed season trial';
 exception when sqlstate 'P4501' then null;end;
 -- Manual foreign deals materialize only the foreign club, with existing negotiation rules.
 select p.id into pid from public.sim_players p join public.sim_player_pos_ratings pr on pr.player_id=p.id and pr.pos=p.position where p.club_id='arsenal' and p.active order by pr.rating,p.id limit 1;
 perform public.mgr_player_detail(pid,null);
 if not exists(select 1 from public.cw_contracts where career_id=cid and player_id=pid and status='active') then raise exception 'Foreign contract not materialized';end if;
 if(select count(*) from public.cw_seasons where career_id=cid)<>1 then raise exception 'Player detail activated foreign league';end if;
 update public.cw_clubs set cash=5000000 where career_id=cid and club_id='flamengo';
 r:=public.career_transfer_bid(pid,1000000,1,0,false,gen_random_uuid());nid:=(r->>'id')::uuid;
 update public.cw_negotiations set decision_roll=.5 where id=nid;
 update public.cw_world set today=today+2 where career_id=cid;perform public.cw_market_tick(cid);
 if(select status from public.cw_negotiations where id=nid)<>'player_counter' then raise exception 'Foreign bid failed';end if;
 perform public.career_player_offer(nid,10000,3,500,'starter',0,0,gen_random_uuid());
 update public.cw_world set today=today+2 where career_id=cid;perform public.cw_market_tick(cid);
 if(select status from public.cw_negotiations where id=nid)<>'completed' or(select club_id from public.mgr_players where career_id=cid and player_id=pid)<>'flamengo' then raise exception 'Foreign transfer not completed';end if;
 select coins into money_before from public.careers where id=cid;
 select primary_season into sid from public.cw_world where career_id=cid;
 insert into public.season_offers(career_id,season_id,from_club,bonus_coins,pitch,kind,expires_day,expires_on,salary,contract_years,budget_guarantee)
 select cid,primary_season,'arsenal',0,'Foreign job','coach',elapsed_days+7,today+7,100,2,0 from public.cw_world where career_id=cid returning id into oid;
 perform public.mgr_offer_respond(oid,true);
 if(select club_id from public.mgr_coach where career_id=cid)<>'arsenal' or(select primary_season from public.cw_world where career_id=cid)=sid then raise exception 'Country switch failed';end if;
 if(select club_id from public.mgr_players where career_id=cid and player_id=pid)<>'flamengo' then raise exception 'Switch undid previous transfer';end if;
 if(select coins from public.careers where id=cid)<>money_before then raise exception 'Inactive summary changed account money';end if;
 if not exists(select 1 from public.season_fixtures f join public.career_seasons s on s.id=f.season_id where s.career_id=cid and f.stats->>'simulation'='inactive_summary') then raise exception 'No lazy foreign summary';end if;
 -- Returning to the country reuses the exact season and previously played results.
 select primary_season into return_season from public.cw_world where career_id=cid;
 select today into d from public.cw_world where career_id=cid;
 insert into public.season_offers(career_id,season_id,from_club,bonus_coins,pitch,kind,expires_day,expires_on,salary,contract_years,budget_guarantee)
 select cid,primary_season,'santos',0,'Return job','coach',elapsed_days+7,today+7,100,2,0 from public.cw_world where career_id=cid returning id into oid;
 perform public.mgr_offer_respond(oid,true);
 if(select primary_season from public.cw_world where career_id=cid)<>sid or(select today from public.cw_world where career_id=cid)<>d then raise exception 'Return recreated season or reset date';end if;
 if(select count(*) from public.cw_seasons where career_id=cid)<>2 then raise exception 'Duplicate country season';end if;
 insert into public.season_offers(career_id,season_id,from_club,bonus_coins,pitch,kind,expires_day,expires_on,salary,contract_years,budget_guarantee)
 select cid,primary_season,'arsenal',0,'Back to England','coach',elapsed_days+7,today+7,100,2,0 from public.cw_world where career_id=cid returning id into oid;
 perform public.mgr_offer_respond(oid,true);
 if(select primary_season from public.cw_world where career_id=cid)<>return_season then raise exception 'English season recreated';end if;
 -- Inactive knockout draws use seeded penalties and never award personal progression.
 begin
  select coins into money_before from public.careers where id=cid;
  insert into public.career_seasons(career_id,season_no,year,region,mode,status) values(cid,9999,2035,'ENG','world','archived') returning id into sid;
  insert into public.season_participants(season_id,competition_id,club_id) values(sid,'fa_cup','arsenal'),(sid,'fa_cup','chelsea');
  insert into public.season_competitions(season_id,competition_id,stage) values(sid,'fa_cup','final');
  insert into public.season_fixtures(season_id,competition_id,stage,round_no,tie_no,leg,home_club,away_club,status,home_goals,away_goals,stats)
   values(sid,'fa_cup','final',1,1,1,'arsenal','chelsea','played',0,0,'{"simulation":"inactive_summary","algorithm":1}') returning id into f;
  perform public.cw_summarize_region(cid,sid,d);
  if not exists(select 1 from public.season_fixtures where id=f and tie_winner is not null and home_pens is not null and home_pens<>away_pens) then raise exception 'Inactive penalties unresolved';end if;
  select jsonb_build_array(tie_winner,home_pens,away_pens) into score_one from public.season_fixtures where id=f;
  perform public.cw_summarize_region(cid,sid,d);
  select jsonb_build_array(tie_winner,home_pens,away_pens) into score_two from public.season_fixtures where id=f;
  if score_one<>score_two or(select coins from public.careers where id=cid)<>money_before then raise exception 'Inactive results changed or rewarded user';end if;
  raise exception using errcode='P4501',message='rollback inactive knockout trial';
 exception when sqlstate 'P4501' then null;end;
 -- Month settlement is once-only, including previous clubs and salaries, with direct AI summaries.
 perform public.cw_settle_month(cid,date_trunc('month',(select today from public.cw_world where career_id=cid))::date);
 select jsonb_build_object('clubs',(select jsonb_agg(to_jsonb(z) order by club_id) from public.cw_clubs z where career_id=cid),'coins',(select coins from public.careers where id=cid)) into before;
 perform public.cw_settle_month(cid,date_trunc('month',(select today from public.cw_world where career_id=cid))::date);
 if before<>jsonb_build_object('clubs',(select jsonb_agg(to_jsonb(z) order by club_id) from public.cw_clubs z where career_id=cid),'coins',(select coins from public.careers where id=cid)) then raise exception 'Month settled twice';end if;
 if exists(select 1 from public.cw_finance cf where cf.career_id=cid and cf.kind='wages' and cf.reference not like 'club:%'
 and not exists(select 1 from public.cw_coach_contracts cc where cc.career_id=cid and cc.club_id=cf.club_id)) then raise exception 'AI wages not summarized directly';end if;
 if has_function_privilege('anon','public.mgr_shootout(bigint,integer)','EXECUTE') or has_function_privilege('anon','public.mgr_match_create(bigint,uuid,character,jsonb)','EXECUTE') or has_function_privilege('authenticated','public.cw_materialize_club(uuid,text)','EXECUTE') then raise exception 'Internal RPC exposed';end if;
 if jsonb_array_length(public.career_calendar(null,'preview',0))>30 then raise exception 'Unbounded initial calendar';end if;
 -- Starting/resuming a human match retains the detailed engine and charges energy once.
 for tries in 1..30 loop
  if public.cw_attention(cid) is not null then perform public.career_attention_ack(public.cw_attention(cid)->>'key');end if;
  r:=public.career_world_advance(7,gen_random_uuid());exit when coalesce((r->>'stopped_for_match')::boolean,false) and not coalesce((r->>'more')::boolean,false);
 end loop;
 if not coalesce((r->>'stopped_for_match')::boolean,false) then raise exception 'Foreign match never became ready';end if;
 r:=public.mgr_match_start();r2:=public.mgr_match_start();
 if r->>'fixture_id' is distinct from r2->>'fixture_id' then raise exception 'Live match not resumed';end if;
 -- A legacy live match defers activation until its detailed engine finishes.
 f:=(r->>'fixture_id')::bigint;
 update public.cw_runtime set enabled=false,deferred_live=true where career_id=cid;
 perform public.cw_runtime_ensure(cid);
 if public.cw_runtime_enabled(cid) then raise exception 'Live match migrated mid-engine';end if;
 select energy into money_before from public.careers where id=cid;
 r2:=public.mgr_match_start();
 if r2->>'fixture_id'<>f::text or(select energy from public.careers where id=cid)<>money_before then raise exception 'Live resume duplicated energy charge';end if;
 perform public.mgr_engine_run(f,45,null);perform public.mgr_engine_run(f,90,null);perform public.mgr_match_finish(f);
 perform public.cw_runtime_ensure(cid);
 if not public.cw_runtime_enabled(cid) or(select deferred_live from public.cw_runtime where career_id=cid) then raise exception 'Activation after live match failed';end if;
 -- Explicit read endpoint cannot write even inside a read-only transaction (separate test below).
 raise notice 'PASS scoped creation, search, pure reads, AI summaries, attention, receipts, international transfers, country switch, monthly settlement and live match';
 raise notice 'Advance metrics: %',(select row_to_json(m) from public.cw_runtime_metrics m where career_id=cid);
end $test$;
rollback;

begin read only;
select set_config('request.jwt.claim.sub',(select c.user_id::text from public.careers c join public.cw_world w on w.career_id=c.id limit 1),true);
select public.career_hub_read() is not null;
select public.career_calendar(null,'preview',0) is not null;
rollback;
