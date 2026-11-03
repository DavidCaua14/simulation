-- Isolated fixtures only: every action and date change rolls back.
do $$ begin if current_database() not like 'simulation_validation_%' then raise exception 'Disposable local database required';end if;end $$;
begin;
insert into auth.users(id,email) values('55550000-0000-0000-0000-000000000001','renewal-window@example.test');
insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins,level,xp)
 values('55550000-0000-0000-0000-000000000011','55550000-0000-0000-0000-000000000001','RenewalWindowTest','sport','1',30,12345,3,250);
select set_config('request.jwt.claim.sub','55550000-0000-0000-0000-000000000001',true);
select public.career_runtime_initialize() is not null;
do $test$
#variable_conflict use_column
declare cid uuid:='55550000-0000-0000-0000-000000000011';d date:='2026-05-05';pid text;other text;elite text;oid uuid;rid uuid;r jsonb;wage bigint;before_ct jsonb;before_cash bigint;req uuid;next_date date;legacy boolean;st text;registered boolean;
begin
 update public.cw_world set today=d,needs_sync=false where career_id=cid;
 update public.cw_clubs set cash=20000000,debt=0,financial_risk=0,monthly_revenue=1000000 where career_id=cid;
 if public.cw_window_open(public.cw_region('sport'),d) then raise exception 'Expected closed window';end if;
 select mp.player_id into pid from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
  join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position where mp.career_id=cid and mp.club_id='sport' and pr.rating between 60 and 70 order by mp.player_id limit 1;
 select mp.player_id into other from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
  join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position where mp.career_id=cid and mp.club_id<>'sport' and pr.rating between 60 and 70 order by mp.player_id limit 1;
 if pid is null or other is null then raise exception 'Missing ordinary test players';end if;
 -- Valid own-club renewal works in a closed window and quotes the new salary scale.
 update public.cw_contracts set monthly_salary=80,expires_on=d+365 where career_id=cid and player_id=pid and status='active';
 select to_jsonb(ct) into before_ct from public.cw_contracts ct where career_id=cid and player_id=pid and status='active';
 req:=gen_random_uuid();r:=public.career_contract_renew(pid,req);oid:=(r->>'id')::uuid;wage:=(r->>'salary_demand')::bigint;
 if wage<public.cw_salary_floor(pid) or wage<=80 then raise exception 'Legacy renewal kept low salary';end if;
 if(public.career_contract_renew(pid,req)->>'id')::uuid<>oid then raise exception 'Renewal retry duplicated negotiation';end if;
 begin perform public.career_player_offer(oid,wage-1,2,0,'rotation',0,0,gen_random_uuid());raise exception 'Expected salary rejection';
 exception when raise_exception then if sqlerrm not like 'Salário mensal insuficiente.%' then raise;end if;end;
 perform public.career_player_offer(oid,wage*2,2,0,'rotation',0,0,gen_random_uuid());
 update public.cw_negotiations set reply_on=d,decision_roll=.9 where id=oid;
 perform public.cw_market_tick(cid);
 if not exists(select 1 from public.cw_negotiations where id=oid and status='completed') then raise exception 'Own renewal could not complete outside window: %',(select row_to_json(n) from public.cw_negotiations n where id=oid);end if;
 if not exists(select 1 from public.cw_contracts where career_id=cid and player_id=pid and status='active' and monthly_salary=wage*2) then raise exception 'Renewal salary not applied';end if;
 if exists(select 1 from public.cw_transfer_registrations where career_id=cid) then raise exception 'Renewal used recruitment quota';end if;
 -- Another club's player cannot be disguised as a renewal, even with a stale offer.
 begin perform public.career_contract_renew(other,gen_random_uuid());raise exception 'Expected ownership rejection';
 exception when raise_exception then if sqlerrm not like 'Só é possível renovar%' then raise;end if;end;
 insert into public.cw_negotiations(career_id,player_id,buyer_club,initiator,status,fee,valuation,monthly_salary,contract_years,created_on,reply_on,expires_on)
  values(cid,other,'sport','renewal','player_counter',0,1000,10000,2,d,d,d+7) returning id into rid;
 begin perform public.career_player_offer(rid,10000,2,0,'key',0,0,gen_random_uuid());raise exception 'Expected stale renewal rejection';
 exception when raise_exception then if sqlerrm not like 'Só é possível renovar%' then raise;end if;end;
 update public.cw_negotiations set status='agreed',register_on=d where id=rid;
 if public.cw_register_transfer(rid) then raise exception 'Stale renewal transferred another club player';end if;
 -- All recruitment endpoints refuse closed windows, including direct free-agent offers and precontracts.
 begin perform public.career_transfer_bid(other,100000,1,0,false,gen_random_uuid());raise exception 'Expected closed window';
 exception when raise_exception then if sqlerrm not like 'Janela de transferências fechada.%' then raise;end if;end;
 begin perform public.career_transfer_bid(other,0,1,0,true,gen_random_uuid());raise exception 'Expected closed precontract';
 exception when raise_exception then if sqlerrm not like 'Janela de transferências fechada.%' then raise;end if;end;
 update public.cw_contracts set status='expired',ended_on=d-1 where career_id=cid and player_id=other and status='active';
 update public.mgr_players set club_id=null where career_id=cid and player_id=other;
 begin perform public.career_free_agent_offer(other,10000,2,20000,'rotation',0,0,gen_random_uuid());raise exception 'Expected closed free signing';
 exception when raise_exception then if sqlerrm not like 'Janela de transferências fechada.%' then raise;end if;end;
 insert into public.cw_negotiations(career_id,player_id,buyer_club,initiator,status,fee,valuation,monthly_salary,contract_years,created_on,reply_on,expires_on)
  values(cid,other,'sport','user','player_counter',0,1000,10000,2,d,d,d+7) returning id into rid;
 begin perform public.career_player_offer(rid,10000,2,20000,'rotation',0,0,gen_random_uuid());raise exception 'Expected closed pending contract';
 exception when raise_exception then if sqlerrm not like 'Janela de transferências fechada.%' then raise;end if;end;
 update public.cw_negotiations set status='club_counter' where id=rid;
 begin perform public.career_transfer_respond(rid,'accept',null,gen_random_uuid());raise exception 'Expected closed counteroffer';
 exception when raise_exception then if sqlerrm not like 'Janela de transferências fechada.%' then raise;end if;end;
 perform public.career_transfer_respond(rid,'reject',null,gen_random_uuid());
 -- Legacy, AI short-roster and human agreements all wait. No cash, contract or quota changes.
 next_date:=public.cw_next_window('BRA',d);
 select cash into before_cash from public.cw_clubs where career_id=cid and club_id='sport';
 for st in select unnest(array['agreed','precontract']) loop
  foreach legacy in array array[false,true] loop
   insert into public.cw_negotiations(career_id,player_id,buyer_club,initiator,status,fee,valuation,monthly_salary,contract_years,signing_bonus,created_on,reply_on,expires_on,register_on)
    values(cid,other,'sport','user',st,0,1000,10000,2,20000,d,d,d+7,d) returning id into rid;
   if legacy then insert into public.cw_market_legacy_agreements values(rid,cid);end if;
   registered:=public.cw_register_transfer(rid);
   if registered or not exists(select 1 from public.cw_negotiations where id=rid and status=st and register_on=next_date) then raise exception 'Agreement was lost or registered outside window: %, expected % / % / %',(select row_to_json(n) from public.cw_negotiations n where id=rid),next_date,st,legacy;end if;
   if legacy then
    begin
     update public.cw_world set today=next_date+10 where career_id=cid;
     registered:=public.cw_register_transfer(rid);
     if not registered or not exists(select 1 from public.cw_negotiations where id=rid and status='completed') then raise exception 'Preserved agreement failed to register in next open window';end if;
     raise exception using errcode='P5501',message='rollback future arrival';
    exception when sqlstate 'P5501' then null;end;
   end if;
   perform public.cw_neg_close(rid,'rejected','test cleanup');
  end loop;
 end loop;
 if(select cash from public.cw_clubs where career_id=cid and club_id='sport')<>before_cash or exists(select 1 from public.cw_transfer_registrations where career_id=cid) or (select club_id from public.mgr_players where career_id=cid and player_id=other) is not null then raise exception 'Deferred deal changed progress';end if;
 perform public.cw_ensure_club_finance(cid,'arsenal');
 insert into public.cw_negotiations(career_id,player_id,buyer_club,initiator,status,fee,valuation,monthly_salary,contract_years,created_on,reply_on,expires_on,register_on)
  values(cid,other,'arsenal','ai','agreed',0,1000,10000,2,d,d,d+7,d) returning id into rid;
 registered:=public.cw_register_transfer(rid);
 if registered or (select register_on from public.cw_negotiations where id=rid)<>public.cw_next_window('ENG',d) then raise exception 'AI free-agent exception bypassed closed window';end if;
 -- Reproduce an old elite bargain signing: refusal never terminates the current contract early.
 perform public.cw_materialize_club(cid,'arsenal');
 select sp.id into elite from public.sim_players sp join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position where sp.club_id='arsenal' and pr.rating>=85 order by (sp.full_name ilike '%raya%') desc,sp.id limit 1;
 if elite is null then raise exception 'Missing Arsenal elite player';end if;
 update public.mgr_players set club_id='sport' where career_id=cid and player_id=elite;
 update public.cw_contracts set club_id='sport',monthly_salary=80,expires_on=d+2 where career_id=cid and player_id=elite and status='active';
 select to_jsonb(ct) into before_ct from public.cw_contracts ct where career_id=cid and player_id=elite and status='active';
 begin perform public.career_contract_renew(elite,gen_random_uuid());raise exception 'Expected elite renewal refusal';
 exception when raise_exception then if sqlerrm not like 'O atleta recusou a renovação:%' then raise;end if;end;
 if before_ct is distinct from(select to_jsonb(ct) from public.cw_contracts ct where career_id=cid and player_id=elite and status='active') then raise exception 'Renewal refusal changed existing contract';end if;
 insert into public.cw_negotiations(career_id,player_id,buyer_club,initiator,status,fee,valuation,monthly_salary,contract_years,created_on,reply_on,expires_on)
  values(cid,elite,'sport','renewal','player_pending',0,1000,10000000,2,d,d,d+7) returning id into rid;
 perform public.cw_market_tick(cid);
 if not exists(select 1 from public.cw_negotiations where id=rid and status='rejected' and response like '%nível esportivo%') then raise exception 'Already pending renewal bypassed project gate';end if;
 if not exists(select 1 from public.mgr_players where career_id=cid and player_id=elite and club_id='sport') then raise exception 'Refusal removed elite player before expiry';end if;
 update public.cw_world set today=d+3 where career_id=cid;
 perform public.cw_finance_tick(cid);
 if not exists(select 1 from public.mgr_players where career_id=cid and player_id=elite and club_id is null)
  or not exists(select 1 from public.cw_contracts where career_id=cid and player_id=elite and status='expired' and ended_on=d+2) then raise exception 'Unrenewed elite contract did not expire naturally';end if;
 raise notice 'PASS renewal salaries, project refusal, natural expiry, own-club validation and closed-window recruitment';
end $test$;
rollback;
