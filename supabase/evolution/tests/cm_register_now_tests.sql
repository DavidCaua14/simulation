-- Evolução 69: sem limite de contratações por janela; acordo fechado entra no elenco na hora. Banco descartável.
do $$ begin if current_database() not like 'simulation_validation_%' then raise exception 'Disposable local database required';end if;end $$;
begin;
insert into auth.users(id,email) values('69690000-0000-0000-0000-000000000001','cm69@example.test');
insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins,level,xp)
 values('69690000-0000-0000-0000-000000000011','69690000-0000-0000-0000-000000000001','CM69','sport','1',30,1000,3,250);
select set_config('request.jwt.claim.sub','69690000-0000-0000-0000-000000000001',true);
select public.career_runtime_initialize() is not null;
do $test$
#variable_conflict use_column
declare cid uuid:='69690000-0000-0000-0000-000000000011';d date;closed date;opened date;pid text;seller text;ct uuid;nid uuid;r jsonb;
begin
 update public.cw_world set needs_sync=false where career_id=cid;
 update public.cw_clubs set cash=90000000,wage_budget=90000000 where career_id=cid and club_id='sport';
 perform public.mgr_lock();
 select today into d from public.cw_world where career_id=cid;
 select x::date into closed from generate_series(d,d+300,'1 day') x where not public.cw_window_open(public.cw_region('sport'),x::date) order by 1 limit 1;
 select x::date into opened from generate_series(d,d+300,'1 day') x where public.cw_window_open(public.cw_region('sport'),x::date) order by 1 limit 1;
 -- 1) acordo fechado com a janela FECHADA: entra no elenco na hora
 update public.cw_world set today=closed where career_id=cid;
 select mp.player_id,mp.club_id,c.id into pid,seller,ct from public.mgr_players mp join public.cw_contracts c on c.career_id=mp.career_id and c.player_id=mp.player_id and c.status='active'
  where mp.career_id=cid and mp.club_id<>'sport' and mp.club_id in(select public.cw_domestic_clubs(cid)) order by mp.player_id limit 1;
 insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,installments,monthly_salary,contract_years,signing_bonus,role,created_on,reply_on,expires_on,register_on,valuation,agreed_owner_contract)
 values(cid,pid,seller,'sport','user','agreed',1000,1,public.cw_salary_demand(cid,pid,'sport'),3,0,'rotation',closed,closed,closed+7,public.cw_next_window(public.cw_region('sport'),closed),5000,ct) returning id into nid;
 update public.cw_negotiations set register_on=closed where id=nid;
 perform public.cw_register_transfer(nid);
 if (select status from public.cw_negotiations where id=nid)<>'completed' or (select club_id from public.mgr_players where career_id=cid and player_id=pid)<>'sport' then
  raise exception 'Acordo fechado não entrou no elenco: %',(select row_to_json(n) from public.cw_negotiations n where id=nid);
 end if;
 raise notice 'PASS acordo fechado entra no elenco com a janela fechada';
 -- 2) sem limite de 6 contratações na janela
 update public.cw_world set today=opened where career_id=cid;
 for i in 1..7 loop insert into public.cw_transfer_registrations values(cid,gen_random_uuid(),pid,'sport',opened);end loop;
 select mp.player_id into pid from public.mgr_players mp where mp.career_id=cid and mp.club_id<>'sport' and mp.club_id in(select public.cw_domestic_clubs(cid)) order by mp.player_id desc limit 1;
 begin
  r:=public.career_transfer_offer(pid,public.cw_player_value(cid,pid),gen_random_uuid());
 exception when raise_exception then
  if sqlerrm like '%Limite de 6%' then raise exception 'Limite de 6 contratações ainda existe';end if;
 end;
 raise notice 'PASS sem limite de contratações por janela';
end $test$;
rollback;
