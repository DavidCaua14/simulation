-- Destructive fixtures are allowed only in the disposable local test database.
do $$ begin if current_database() not like 'simulation_validation_%' then raise exception 'Disposable local database required';end if;end $$;
begin;
insert into auth.users(id,email) values('51510000-0000-0000-0000-000000000001','offseason@example.test');
insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins,level,xp,bonus_energy)
 values('51510000-0000-0000-0000-000000000011','51510000-0000-0000-0000-000000000001','OffseasonTest','avai','1',30,16261,3,250,53);
select set_config('request.jwt.claim.sub','51510000-0000-0000-0000-000000000001',true);
select public.career_runtime_initialize() is not null;
do $test$
#variable_conflict use_column
declare cid uuid:='51510000-0000-0000-0000-000000000011';sid uuid;oid uuid;fx bigint;foreign_sid uuid;old_foreign jsonb;
 d date;r jsonb;r2 jsonb;car public.careers;season public.career_seasons;before_data jsonb;version_before bigint;
begin
 select primary_season,today into sid,d from public.cw_world where career_id=cid;
 update public.cw_clubs set cash=5000000,debt=0 where career_id=cid and club_id='santos';
 -- Active-season transfers continue to use the existing calendar and the same day.
 begin
  insert into public.season_offers(career_id,season_id,from_club,bonus_coins,pitch,kind,expires_day,expires_on,salary,contract_years,budget_guarantee)
   select cid,sid,'santos',650,'Active offer','coach',elapsed_days+7,today+7,245,2,283044 from public.cw_world where career_id=cid returning id into oid;
  update public.cw_world set needs_sync=false where career_id=cid;
  r:=public.mgr_offer_respond(oid,true);
  if not(r->>'accepted')::boolean or(r->>'off_season')::boolean or(select today from public.cw_world where career_id=cid)<>d then raise exception 'Active-season offer regressed';end if;
  raise exception using errcode='P5101',message='rollback active offer trial';
 exception when sqlstate 'P5101' then null;end;
 -- Live games and expired offers retain their existing protections.
 begin
  select id into fx from public.season_fixtures where season_id=sid and home_club='avai' order by id limit 1;
  insert into public.mgr_matches(fixture_id,career_id,season_id,user_side,status,state) values(fx,cid,sid,'h','live','{}');
  insert into public.season_offers(career_id,season_id,from_club,bonus_coins,pitch,kind,expires_day,expires_on,salary,contract_years,budget_guarantee)
   select cid,sid,'santos',650,'Live offer','coach',elapsed_days+7,today+7,245,2,283044 from public.cw_world where career_id=cid returning id into oid;
  begin perform public.mgr_offer_respond(oid,true);raise exception 'Expected live-game rejection';
  exception when raise_exception then if sqlerrm<>'Termine a partida em andamento' then raise;end if;end;
  if(select status from public.season_offers where id=oid)<>'pending' or not exists(select 1 from public.mgr_matches where fixture_id=fx and status='live') then raise exception 'Live-game rejection changed state';end if;
  raise exception using errcode='P5101',message='rollback live offer trial';
 exception when sqlstate 'P5101' then null;end;
 begin
  insert into public.season_offers(career_id,season_id,from_club,bonus_coins,pitch,kind,expires_day,expires_on,salary,contract_years,budget_guarantee)
   select cid,sid,'santos',650,'Expired offer','coach',elapsed_days-1,today-1,245,2,283044 from public.cw_world where career_id=cid returning id into oid;
  begin perform public.mgr_offer_respond(oid,true);raise exception 'Expected expiry rejection';
  exception when raise_exception then if sqlerrm<>'Proposta encerrada' then raise;end if;end;
  if(select coins from public.careers where id=cid)<>16261 then raise exception 'Rejected offer paid a bonus';end if;
  raise exception using errcode='P5101',message='rollback expired offer trial';
 exception when sqlstate 'P5101' then null;end;
 -- A foreign finished year gets an upcoming active calendar without a date jump.
 begin
  update public.season_fixtures set status='played',home_goals=0,away_goals=0 where season_id=sid;
  update public.career_seasons set status='finished',finished_at=now() where id=sid;
  update public.cw_world set today='2026-06-30',needs_sync=false where career_id=cid;
  foreign_sid:=public.cw_create_region(cid,'ENG',2025);
  perform public.cw_summarize_region(cid,foreign_sid,'2026-06-30');
  select to_jsonb(s) into old_foreign from public.career_seasons s where id=foreign_sid;
  if old_foreign->>'status'<>'finished' then raise exception 'Invalid foreign fixture: year did not close';end if;
  perform public.cw_materialize_club(cid,'arsenal');
  update public.cw_clubs set cash=5000000,debt=0 where career_id=cid and club_id='arsenal';
  insert into public.season_offers(career_id,season_id,from_club,bonus_coins,pitch,kind,expires_day,expires_on,salary,contract_years,budget_guarantee)
   select cid,sid,'arsenal',650,'Foreign offseason','coach',elapsed_days+7,today+7,245,2,283044 from public.cw_world where career_id=cid returning id into oid;
  r:=public.mgr_offer_respond(oid,true);
  if not(r->>'accepted')::boolean or not(r->>'off_season')::boolean or(select today from public.cw_world where career_id=cid)<>'2026-06-30'::date then raise exception 'Foreign offseason did not preserve date';end if;
  if not exists(select 1 from public.career_seasons s join public.cw_world w on w.primary_season=s.id where w.career_id=cid and s.region='ENG' and s.year=2026 and s.status='active') then raise exception 'Foreign upcoming calendar missing';end if;
  if(select to_jsonb(s) from public.career_seasons s where id=foreign_sid)<>old_foreign then raise exception 'Foreign historical season was rewritten';end if;
  r2:=public.mgr_offer_respond(oid,true);
  if(select count(*) from public.cw_seasons where career_id=cid and region='ENG' and year=2026)<>1 then raise exception 'Foreign calendar duplicated';end if;
  raise exception using errcode='P5101',message='rollback foreign offer trial';
 exception when sqlstate 'P5101' then null;end;
 -- Minimal terminal-season fixture, including one protected historical result.
 select id into fx from public.season_fixtures where season_id=sid and home_club='avai' order by id limit 1;
 update public.season_fixtures set status='played',home_goals=2,away_goals=1,player_match=true,coach_club='avai' where id=fx;
 update public.season_fixtures set status='played',home_goals=0,away_goals=0 where season_id=sid and status='pending';
 update public.career_seasons set status='finished',finished_at=now(),summary='{"history":"protected-closed-year"}' where id=sid;
 update public.cw_world set today='2026-11-11',needs_sync=true where career_id=cid;
 select * into car from public.careers where id=cid;
 select * into season from public.career_seasons where id=sid;
 select version into version_before from public.cw_runtime where career_id=cid;
 select to_jsonb(f) into before_data from public.season_fixtures f where id=fx;
 insert into public.season_offers(career_id,season_id,from_club,bonus_coins,pitch,kind,expires_day,expires_on,salary,contract_years,budget_guarantee)
  select cid,sid,'santos',650,'Closed-year offer','coach',elapsed_days+7,today+7,245,2,283044 from public.cw_world where career_id=cid returning id into oid;
 r:=public.mgr_offer_respond(oid,true);r2:=public.mgr_offer_respond(oid,true);
 if not(r->>'accepted')::boolean or not(r->>'off_season')::boolean or not(r2->>'accepted')::boolean then raise exception 'Closed-year offer failed';end if;
 if(select today from public.cw_world where career_id=cid)<>'2026-11-11'::date or(select primary_season from public.cw_world where career_id=cid)<>sid then raise exception 'Signature moved the calendar';end if;
 if(select to_jsonb(s) from public.career_seasons s where id=sid)<>to_jsonb(season) or(select to_jsonb(f) from public.season_fixtures f where id=fx)<>before_data then raise exception 'Signature rewrote historical progress';end if;
 if(select coins from public.careers where id=cid)<>car.coins+650 or(select level from public.careers where id=cid)<>car.level or(select xp from public.careers where id=cid)<>car.xp then raise exception 'Signature changed progression or duplicated bonus';end if;
 if(select count(*) from public.cw_coach_contracts where career_id=cid and club_id='santos')<>1 then raise exception 'Repeated signature duplicated employment';end if;
 if not exists(select 1 from public.season_offers where id=oid and status='accepted' and expires_on='2026-11-18' and salary=245 and contract_years=2 and budget_guarantee=283044 and bonus_coins=650) then raise exception 'Negotiated terms changed';end if;
 r:=public.career_world_prepare(1,gen_random_uuid(),version_before);
 if not(r->>'requires_refresh')::boolean then raise exception 'Stale browser could advance after the job change';end if;
 raise notice 'PASS active/expired/live protections, same-country and foreign offseason jobs, same-day contract, immutable history and one-time signing bonus';
end $test$;
rollback;
