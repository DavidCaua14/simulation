-- Disposable local database only. All changes to game state roll back.
do $$ begin if current_database() not like 'simulation_validation_%' then raise exception 'Disposable local database required';end if;end $$;
begin;
insert into auth.users(id,email) values('53530000-0000-0000-0000-000000000001','market-policy@example.test');
insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins,level,xp)
 values('53530000-0000-0000-0000-000000000011','53530000-0000-0000-0000-000000000001','MarketPolicyTest','sport','1',30,12345,3,250);
select set_config('request.jwt.claim.sub','53530000-0000-0000-0000-000000000001',true);
select public.career_runtime_initialize() is not null;
do $test$
#variable_conflict use_column
declare cid uuid:='53530000-0000-0000-0000-000000000011';d date:='2026-01-05';pid text;p2 text;oid uuid;oid2 uuid;rid uuid;r jsonb;r2 jsonb;
 ct public.cw_contracts;old_ct jsonb;car jsonb;wage bigint;starting_cash bigint;regcount int;i int;candidate text;sid uuid;season_count int;
begin
 update public.cw_world set today=d,needs_sync=false where career_id=cid;
 update public.cw_clubs set cash=20000000,debt=0,financial_risk=0,monthly_revenue=1000000 where career_id=cid;
 select to_jsonb(c) into car from public.careers c where id=cid;
 select mp.player_id into pid from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
  join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position where mp.career_id=cid and mp.club_id<>'sport' and pr.rating between 60 and 70 order by mp.player_id limit 1;
 select mp.player_id into p2 from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
  join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position where mp.career_id=cid and mp.club_id<>'sport' and pr.rating between 60 and 70 and mp.player_id<>pid order by mp.player_id limit 1;
 if pid is null or p2 is null then raise exception 'Missing ordinary players in catalogue';end if;
 -- Seven future agreements caused the reported false quota block; none is a registration.
 begin
  for i in 1..7 loop
   select mp.player_id into candidate from public.mgr_players mp where career_id=cid and club_id<>'sport' and player_id not in(pid,p2) order by player_id offset i limit 1;
   update public.cw_players set age_at_start=19 where career_id=cid and player_id=candidate;
   insert into public.cw_negotiations(career_id,player_id,buyer_club,initiator,status,fee,valuation,created_on,reply_on,expires_on,register_on)
    values(cid,candidate,'sport','user','agreed',0,1000,d,d,d+7,'2026-07-10');
  end loop;
  rid:=gen_random_uuid();r:=public.career_transfer_bid(pid,100000,1,0,false,rid);r2:=public.career_transfer_bid(pid,100000,1,0,false,rid);
  if(r-'replayed')<>(r2-'replayed') or not(r2->>'replayed')::boolean or public.cw_registered_in_window(cid,'sport',d)<>0 then raise exception 'Offers consumed registrations or receipt replayed twice: %, %, %',r,r2,public.cw_registered_in_window(cid,'sport',d);end if;
  for i in 1..6 loop
   insert into public.cw_transfer_registrations values(cid,gen_random_uuid(),pid,'sport',d);
  end loop;
  begin perform public.career_transfer_bid(p2,100000,1,0,false,gen_random_uuid());raise exception 'Expected six-registration cap';
  exception when raise_exception then if sqlerrm not like 'Limite de 6 contratações registradas%' or sqlerrm not like '%10/07/2026%' then raise;end if;end;
  update public.cw_world set today='2026-07-10' where career_id=cid;
  r:=public.career_transfer_bid(p2,100000,1,0,false,gen_random_uuid());
  if public.cw_registered_in_window(cid,'sport','2026-07-10')<>0 then raise exception 'Quota did not reset at next window';end if;
  raise exception using errcode='P5301',message='rollback window trial';
 exception when sqlstate 'P5301' then null;end;
 -- Stars refuse an unsuitable club even after their estimated age reaches veteran status.
 perform public.cw_materialize_club(cid,'barcelona');perform public.cw_materialize_club(cid,'man-united');
 update public.cw_clubs set cash=20000000,debt=0,financial_risk=0,monthly_revenue=1000000 where career_id=cid;
 update public.cw_players set age_at_start=40 where career_id=cid and player_id in('lamine-yamal-esp','luke-shaw-eng');
 if public.cw_project_reason(cid,'lamine-yamal-esp','sport') is null or public.cw_project_reason(cid,'luke-shaw-eng','sport') is null then raise exception 'Veteran exception admitted elite at Sport';end if;
 if public.cw_project_reason(cid,'lamine-yamal-esp','barcelona') is not null then raise exception 'Suitable club rejected';end if;
 if public.cw_salary_floor('lamine-yamal-esp')<=public.cw_salary_floor(pid) or public.cw_salary_floor('lamine-yamal-esp')<=1500 then raise exception 'Salary floor does not reflect quality';end if;
 -- Inactive countries retain contracts/owners, without fixtures or salary settlement abroad.
 begin
  select * into ct from public.cw_contracts where career_id=cid and player_id='lamine-yamal-esp' and status='active';
  update public.cw_contracts set starts_on=d-365,expires_on=d-1 where id=ct.id;
  select monthly_salary into wage from public.cw_contracts where id=ct.id;
  select count(*) into season_count from public.cw_seasons where career_id=cid;
  perform public.cw_ai_contracts_tick(cid);
  if not exists(select 1 from public.cw_contracts where id=ct.id and status='active' and expires_on>d and monthly_salary=wage)
   or(select club_id from public.mgr_players where career_id=cid and player_id=ct.player_id)<>'barcelona'
   or(select count(*) from public.cw_seasons where career_id=cid)<>season_count then raise exception 'Dormant country lost star, changed wage or allocated fixtures';end if;
  raise exception using errcode='P5301',message='rollback dormant trial';
 exception when sqlstate 'P5301' then null;end;
 -- Historical orphan AI stars are projected as owned, then recovered once on a real action.
 begin
  update public.cw_contracts set status='expired',starts_on=d-365,ended_on=d-1,expires_on=d-1 where career_id=cid and player_id='lamine-yamal-esp' and status='active';
  update public.mgr_players set club_id=null where career_id=cid and player_id='lamine-yamal-esp';
  r:=public.career_player_search('Lamine Yamal','','','',null,0,'');
  if r->0->>'club_id' is distinct from 'barcelona' or(select club_id from public.mgr_players where career_id=cid and player_id='lamine-yamal-esp') is not null then raise exception 'Read did not project recovery without mutation';end if;
  if public.cw_recover_ai_free_players(cid,'lamine-yamal-esp')<>1 or public.cw_recover_ai_free_players(cid,'lamine-yamal-esp')<>0 then raise exception 'Recovery not idempotent';end if;
  if not exists(select 1 from public.cw_contracts where career_id=cid and player_id='lamine-yamal-esp' and status='active' and monthly_salary>=public.cw_salary_floor(player_id)) then raise exception 'Recovered star lacks realistic contract';end if;
  -- A later genuine expiry cannot be repaired in an endless loop.
  update public.cw_contracts set status='expired',ended_on=d-1 where career_id=cid and player_id='lamine-yamal-esp' and status='active';
  update public.mgr_players set club_id=null where career_id=cid and player_id='lamine-yamal-esp';
  if public.cw_recover_ai_free_players(cid,'lamine-yamal-esp')<>0 then raise exception 'Recovery repeated after later release';end if;
  raise exception using errcode='P5301',message='rollback recovery trial';
 exception when sqlstate 'P5301' then null;end;
 -- An existing negotiation is preserved; no recovery can steal its target.
 begin
  update public.cw_contracts set status='expired',starts_on=d-365,ended_on=d-1,expires_on=d-1 where career_id=cid and player_id='lamine-yamal-esp' and status='active';
  update public.mgr_players set club_id=null where career_id=cid and player_id='lamine-yamal-esp';
  insert into public.cw_negotiations(career_id,player_id,buyer_club,initiator,status,fee,valuation,created_on,reply_on,expires_on)
   values(cid,'lamine-yamal-esp','sport','user','player_counter',0,1000,d,d,d+7) returning id into oid;
  if public.cw_recover_ai_free_players(cid,'lamine-yamal-esp')<>0 then raise exception 'Recovery stole pending target';end if;
  begin perform public.career_player_offer(oid,10000000,3,10000000,'key',0,0,gen_random_uuid());raise exception 'Expected project rejection';
  exception when raise_exception then if sqlerrm not like '%nível esportivo%' then raise;end if;end;
  if(select status from public.cw_negotiations where id=oid)<>'player_counter' then raise exception 'Failed offer changed progress';end if;
  update public.cw_negotiations set status='player_pending',monthly_salary=100000,signing_bonus=100000,contract_years=3,reply_on=d where id=oid;
  perform public.cw_market_tick(cid);
  if not exists(select 1 from public.cw_negotiations where id=oid and status='rejected' and response like '%nível esportivo%') then raise exception 'Decision engine bypassed the project gate';end if;
  raise exception using errcode='P5301',message='rollback pending trial';
 exception when sqlstate 'P5301' then null;end;
 -- A human release is never reclaimed by the AI, even for a high-rated player.
 begin
  insert into public.mgr_spells(career_id,club_id,started_season,started_year,started_day) values(cid,'barcelona',1,2026,0);
  update public.cw_contracts set status='expired',starts_on=d-365,ended_on=d-1,expires_on=d-1 where career_id=cid and player_id='lamine-yamal-esp' and status='active';
  update public.mgr_players set club_id=null where career_id=cid and player_id='lamine-yamal-esp';
  if public.cw_recover_ai_free_players(cid,'lamine-yamal-esp')<>0 then raise exception 'Human history overwritten';end if;
  raise exception using errcode='P5301',message='rollback human release trial';
 exception when sqlstate 'P5301' then null;end;
 -- Clubs in the active country renew affordable stars before expiry; the human decides their own renewals.
 begin
  select x.* into ct from public.cw_contracts x join public.sim_players sp on sp.id=x.player_id join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
   where x.career_id=cid and x.club_id='flamengo' and x.status='active' and pr.rating>=80 order by pr.rating desc limit 1;
  update public.cw_contracts set starts_on=d-365,expires_on=d-1 where id=ct.id;
  select to_jsonb(x) into old_ct from public.cw_contracts x where career_id=cid and club_id='sport' and status='active' order by id limit 1;
  perform public.cw_ai_contracts_tick(cid);
  if not exists(select 1 from public.cw_contracts where career_id=cid and player_id=ct.player_id and status='active' and expires_on>d and monthly_salary>=public.cw_salary_floor(player_id)) then raise exception 'Affordable AI star became free';end if;
  if(select to_jsonb(x) from public.cw_contracts x where id=(old_ct->>'id')::uuid)<>old_ct then raise exception 'Human contract changed automatically';end if;
  raise exception using errcode='P5301',message='rollback renewal trial';
 exception when sqlstate 'P5301' then null;end;
 -- New free-agent deals need salary, signing bonus and six months of incremental payroll.
 begin
  update public.cw_contracts set status='expired',starts_on=d-365,ended_on=d-1,expires_on=d-1 where career_id=cid and player_id in(pid,p2) and status='active';
  update public.mgr_players set club_id=null where career_id=cid and player_id in(pid,p2);
  r:=public.career_transfer_bid(pid,0,1,0,false,gen_random_uuid());oid:=(r->>'id')::uuid;
  wage:=public.cw_salary_demand(cid,pid,'sport');
  begin perform public.career_player_offer(oid,1,3,1000000,'rotation',100000,100000,gen_random_uuid());raise exception 'Expected monthly salary floor';
  exception when raise_exception then if sqlerrm not like 'Salário mensal insuficiente%' then raise;end if;end;
  begin perform public.career_player_offer(oid,wage,3,0,'rotation',0,0,gen_random_uuid());raise exception 'Expected signing bonus floor';
  exception when raise_exception then if sqlerrm not like 'Atleta livre exige%' then raise;end if;end;
  update public.cw_clubs set cash=100 where career_id=cid and club_id='sport';
  begin perform public.career_player_offer(oid,wage,3,2*wage,'rotation',0,0,gen_random_uuid());raise exception 'Expected financial rejection';
  exception when raise_exception then if sqlerrm not like 'Orçamento livre insuficiente%' and sqlerrm not like 'Verba de transferências insuficiente%' then raise;end if;end;
  update public.cw_clubs set cash=20000000 where career_id=cid and club_id='sport';
  for i in 1..5 loop insert into public.cw_transfer_registrations values(cid,gen_random_uuid(),pid,'sport',d);end loop;
  update public.cw_negotiations set monthly_salary=wage,signing_bonus=2*wage,contract_years=3,status='agreed',register_on=d where id=oid;
  perform public.cw_reserve_offer(oid);
  select cash into starting_cash from public.cw_clubs where career_id=cid and club_id='sport';
  if not public.cw_register_transfer(oid) or not public.cw_register_transfer(oid) then raise exception 'Valid sixth registration failed';end if;
  if public.cw_registered_in_window(cid,'sport',d)<>6 or(select cash from public.cw_clubs where career_id=cid and club_id='sport')<>starting_cash-2*wage then raise exception 'Registration/bonus duplicated';end if;
  -- A seventh valid agreement stays valid for the next window; it is never silently lost.
  wage:=public.cw_salary_demand(cid,p2,'sport');
  insert into public.cw_negotiations(career_id,player_id,buyer_club,initiator,status,fee,valuation,monthly_salary,signing_bonus,contract_years,created_on,reply_on,expires_on,register_on)
   values(cid,p2,'sport','user','agreed',0,1000,wage,2*wage,3,d,d,d+7,d) returning id into oid2;
  if public.cw_register_transfer(oid2) or public.cw_register_transfer(oid2) then raise exception 'Seventh registration exceeded cap';end if;
  if not exists(select 1 from public.cw_negotiations where id=oid2 and status='agreed' and register_on='2026-07-10') then raise exception 'Seventh agreement lost or postponed a year';end if;
  delete from public.cw_offer_history where negotiation_id=oid;
  delete from public.cw_commitments where negotiation_id=oid;
  delete from public.cw_negotiations where id=oid;
  if public.cw_registered_in_window(cid,'sport',d)<>6 then raise exception 'Pruning restored consumed quota';end if;
  raise exception using errcode='P5301',message='rollback registration trial';
 exception when sqlstate 'P5301' then null;end;
 if(select to_jsonb(c)-array['energy','energy_reset_at'] from public.careers c where id=cid)<>car-array['energy','energy_reset_at'] then raise exception 'Policy changed human level, XP, wallet or club';end if;
 raise notice 'PASS offers vs registrations, window reset/durable receipts, elite/veteran project gate, salary/bonus/payroll guards, inactive retention, one-time AI repair, human/pending protections and idempotent sixth/seventh registrations';
end $test$;
rollback;
