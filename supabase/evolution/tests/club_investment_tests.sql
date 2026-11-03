-- Disposable local database only; every fixture, funding action and date change rolls back.
do $$ begin if current_database() not like 'simulation_validation_%' then raise exception 'Disposable local database required';end if;end $$;
begin;
insert into auth.users(id,email) values('56560000-0000-0000-0000-000000000001','club-investment@example.test');
insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins,level,xp)
 values('56560000-0000-0000-0000-000000000011','56560000-0000-0000-0000-000000000001','ClubInvestmentTest','sport','1',30,15000,3,250);
select set_config('request.jwt.claim.sub','56560000-0000-0000-0000-000000000001',true);
select public.career_runtime_initialize() is not null;
do $test$
#variable_conflict use_column
declare cid uuid:='56560000-0000-0000-0000-000000000011';d date:='2026-01-05';pid text;other text;star text;
 q jsonb;r jsonb;r2 jsonb;b jsonb;terms jsonb;req uuid;oid uuid;cash_before bigint;coins_before int;payroll bigint;gap bigint;needed bigint;key text;season_id uuid;old_ct jsonb;signal jsonb;old_count int;support bigint;sum_input bigint;sum_bonus bigint;
begin
 update public.cw_world set today=d,needs_sync=false where career_id=cid;
 update public.cw_clubs set debt=0,financial_risk=0,monthly_revenue=1000000 where career_id=cid;
 select mp.player_id into pid from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
  where mp.career_id=cid and mp.club_id='sport' and pr.rating between 60 and 70 order by mp.player_id limit 1;
 select mp.player_id into other from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
  where mp.career_id=cid and mp.club_id<>'sport' and pr.rating between 60 and 70 order by mp.player_id limit 1;
 if pid is null or other is null then raise exception 'Missing ordinary players';end if;
 -- Read-only plans and previews must never debit coins, change contracts or create campaign rows.
 update public.cw_contracts set monthly_salary=80,expires_on=d+45 where career_id=cid and player_id=pid and status='active';
 select to_jsonb(ct) into old_ct from public.cw_contracts ct where career_id=cid and player_id=pid and status='active';
 select coins into coins_before from public.careers where id=cid;select cash into cash_before from public.cw_clubs where career_id=cid and club_id='sport';
 q:=public.career_club_investment_preview(500);
 if(q->>'board_bonus')::bigint<>100 or(q->>'cash_after')::bigint<>cash_before+600 or(q->>'personal_after')::int<>coins_before-500 then raise exception 'Preview denomination/bonus incorrect: %',q;end if;
 signal:=public.career_world_status()->'investment'->'signal';
 if signal->>'kind'<>'renewal' then raise exception 'Renewal notice missing: %',signal;end if;
 key:=signal->>'key';perform public.career_funding_dismiss(key);
 if(public.career_world_status()->'investment'->'signal')<>'null'::jsonb then raise exception 'Dismissed card reappeared';end if;
 update public.cw_world set today=d+1 where career_id=cid;
 if(public.career_world_status()->'investment'->'signal')<>'null'::jsonb then raise exception 'Card reappeared just because day changed';end if;
 update public.cw_contracts set monthly_salary=90 where career_id=cid and player_id=pid and status='active';
 if(public.career_world_status()->'investment'->'signal'->>'key')=key then raise exception 'Material renewal change retained old dismissal';end if;
 update public.cw_world set today=d where career_id=cid;
 update public.cw_contracts set monthly_salary=80 where career_id=cid and player_id=pid and status='active';
 if(select coins from public.careers where id=cid)<>coins_before or(select cash from public.cw_clubs where career_id=cid and club_id='sport')<>cash_before
  or exists(select 1 from public.cw_board_contributions where career_id=cid) then raise exception 'Read-only preview changed finances';end if;
 -- A direct free-agent offer uses the same quote and remains an explicit separate action.
 begin
  update public.cw_contracts set status='expired',ended_on=d-1 where career_id=cid and player_id=other and status='active';
  update public.mgr_players set club_id=null where career_id=cid and player_id=other;
  payroll:=public.cw_payroll(cid,'sport');needed:=public.cw_salary_demand(cid,other,'sport');
  update public.cw_clubs set cash=2*payroll+8*needed-600,debt=0 where career_id=cid and club_id='sport';
  terms:=jsonb_build_object('monthly_salary',needed,'contract_years',2,'signing_bonus',2*needed,'role','rotation');
  q:=public.career_funding_quote(other,null,terms);
  if(q->>'gap')::bigint<>600 or(q->>'coins_needed')::bigint<>500 then raise exception 'Direct free-agent quote differs from contract rule: %',q;end if;
  q:=public.career_club_investment_preview(500);
  perform public.career_club_investment_confirm(500,q->>'club_id',(q->>'personal_before')::int,(q->>'cash_before')::bigint,(q->>'board_bonus')::bigint,gen_random_uuid());
  if exists(select 1 from public.cw_negotiations where career_id=cid and player_id=other) then raise exception 'Contribution created a player offer';end if;
  r:=public.career_free_agent_offer(other,needed,2,2*needed,'rotation',0,0,gen_random_uuid());
  if not exists(select 1 from public.cw_negotiations where id=(r->>'id')::uuid and status='player_pending') then raise exception 'Funded direct free-agent offer failed';end if;
  raise exception using errcode='P5601',message='rollback free-agent rehearsal';
 exception when sqlstate 'P5601' then null;end;
 -- Exact funding gap includes debt, current payroll reserve and six months of the salary increase.
 payroll:=public.cw_payroll(cid,'sport');
 update public.cw_clubs set cash=2*payroll+100,debt=50 where career_id=cid and club_id='sport';
 r:=public.career_contract_renew(pid,gen_random_uuid());oid:=(r->>'id')::uuid;
 terms:=jsonb_build_object('monthly_salary',greatest(200,(r->>'salary_demand')::bigint),'contract_years',2,'signing_bonus',100,'role','rotation');
 q:=public.career_funding_quote(pid,oid,terms);
 needed:=100+6*greatest(0,public.cw_contract_cost(pid,(terms->>'monthly_salary')::bigint,0,0,'rotation')-80);
 if(q->>'gap')::bigint<>needed+50-100 or q->>'blocked_reason' is not null or not(q->>'can_invest')::boolean then raise exception 'Incorrect actionable funding plan: %',q;end if;
 gap:=(q->>'gap')::bigint;needed:=(q->>'coins_needed')::bigint;b:=q->'board';
 if needed+public.cw_board_bonus(b,needed)<gap or needed-1+public.cw_board_bonus(b,needed-1)>=gap then raise exception 'Suggested coin amount is not minimal';end if;
 req:=gen_random_uuid();q:=public.career_club_investment_preview(needed::int);
 r:=public.career_club_investment_confirm(needed::int,q->>'club_id',(q->>'personal_before')::int,(q->>'cash_before')::bigint,(q->>'board_bonus')::bigint,req);
 r2:=public.career_club_investment_confirm(needed::int,q->>'club_id',(q->>'personal_before')::int,(q->>'cash_before')::bigint,(q->>'board_bonus')::bigint,req);
 if(r-'replayed')<>(r2-'replayed') or not(r2->>'replayed')::boolean then raise exception 'Lost response duplicated funding';end if;
 q:=public.career_funding_quote(pid,oid,terms);
 if(q->>'gap')::bigint<>0 then raise exception 'Suggested contribution did not cover actual requirement';end if;
 perform public.career_player_offer(oid,(terms->>'monthly_salary')::bigint,2,100,'rotation',0,0,gen_random_uuid());
 if old_ct is distinct from(select to_jsonb(ct) from public.cw_contracts ct where career_id=cid and player_id=pid and status='active') then raise exception 'Funding prematurely changed contract';end if;
 -- Confirmation is bound to the displayed club, wallet, cash and board contribution.
 q:=public.career_club_investment_preview(100);
 begin perform public.career_club_investment_confirm(100,'arsenal',(q->>'personal_before')::int,(q->>'cash_before')::bigint,(q->>'board_bonus')::bigint,gen_random_uuid());raise exception 'Expected changed club rejection';
 exception when raise_exception then if sqlerrm not like 'O clube ou os valores mudaram.%' then raise;end if;end;
 begin perform public.career_club_investment_confirm(100,'sport',(q->>'personal_before')::int-1,(q->>'cash_before')::bigint,(q->>'board_bonus')::bigint,gen_random_uuid());raise exception 'Expected changed wallet rejection';
 exception when raise_exception then if sqlerrm not like 'O clube ou os valores mudaram.%' then raise;end if;end;
 begin perform public.career_club_investment_confirm(100,'sport',(q->>'personal_before')::int,(q->>'cash_before')::bigint+1,(q->>'board_bonus')::bigint,gen_random_uuid());raise exception 'Expected changed cash rejection';
 exception when raise_exception then if sqlerrm not like 'O clube ou os valores mudaram.%' then raise;end if;end;
 -- Splitting investments cannot farm rounding or exceed the seasonal board pool.
 select coins into coins_before from public.careers where id=cid;
 perform public.career_club_invest(1,gen_random_uuid());perform public.career_club_invest(4,gen_random_uuid());perform public.career_club_invest(2000,gen_random_uuid());
 b:=public.cw_board_support(cid,'sport');
 if(b->>'bonus_paid')::bigint<>200 or(b->>'bonus_remaining')::bigint<>0 or(b->>'eligible_coins')::bigint<>1000 then raise exception 'Sport campaign cap or rounding failed: %',b;end if;
 r:=public.career_club_invest(100,gen_random_uuid());if(r->>'board_bonus')::bigint<>0 then raise exception 'Seasonal campaign could be repeated';end if;
 select coalesce(-sum(delta),0) into sum_input from public.wallet_ledger where career_id=cid and reason='club_investment';
 select coalesce(sum(amount),0) into sum_bonus from public.cw_finance where career_id=cid and kind='board_contribution';
 if sum_bonus<>200 or(select 15000-coins from public.careers where id=cid)<>sum_input then raise exception 'Principal/bonus accounting does not reconcile';end if;
 -- New season gets a new pool; leaving/rejoining the club during this season does not.
 perform public.cw_ensure_club_finance(cid,'arsenal');
 update public.mgr_coach set club_id='arsenal' where career_id=cid;
 q:=public.career_club_investment_preview(100);if(q->>'board_bonus')::bigint<>20 then raise exception 'New club campaign unavailable';end if;
 update public.mgr_coach set club_id='sport' where career_id=cid;
 if(public.career_club_investment_preview(100)->>'board_bonus')::bigint<>0 then raise exception 'Rejoining reset board support';end if;
 select primary_season into season_id from public.cw_world where career_id=cid;
 update public.career_seasons set year=year+1 where id=season_id;
 if(public.career_club_investment_preview(100)->>'board_bonus')::bigint<>20 then raise exception 'New season pool not available';end if;
 update public.career_seasons set year=year-1 where id=season_id;
 -- Contributions must never bypass project, salary, window or squad rules.
 update public.cw_world set today='2026-05-05' where career_id=cid;
 q:=public.career_funding_quote(other,null,'{}');
 if q->>'blocked_reason' not like 'Janela de transferências fechada.%' or(q->>'can_invest')::boolean then raise exception 'Closed window encouraged contribution';end if;
 update public.cw_world set today=d where career_id=cid;
 select id into star from public.sim_players where id='lamine-yamal-esp';
 q:=public.career_funding_quote(star,null,'{}');
 if q->>'blocked_reason' not like '%nível esportivo%' or(q->>'can_invest')::boolean then raise exception 'Elite project restriction encouraged contribution';end if;
 q:=public.career_funding_quote(pid,oid,jsonb_build_object('monthly_salary',1));
 if q->>'blocked_reason' not like '%salário%' then raise exception 'Low salary not identified';end if;
 -- No uninitialized world, simulation or international materialization is needed for read-only planning.
 select count(*) into old_count from public.mgr_players where career_id=cid;
 q:=public.career_funding_quote(star,null,'{}');
 if(select count(*) from public.mgr_players where career_id=cid)<>old_count or(select today from public.cw_world where career_id=cid)<>d then raise exception 'Quote materialized clubs or advanced time';end if;
 -- A forecast distinguishes predictable income from uncertain matchday receipts; balanced clubs have no funding warning.
 update public.cw_contracts set expires_on=d+730 where career_id=cid and club_id='sport' and status='active';
 update public.cw_negotiations set status='rejected' where career_id=cid;
 update public.cw_commitments set status='released' where career_id=cid and status='reserved';
 update public.cw_clubs set cash=1,monthly_revenue=1000 where career_id=cid and club_id='sport';
 signal:=public.career_world_status()->'investment'->'signal';
 if signal->>'kind'<>'forecast' or(signal->>'monthly_operations')::bigint<>120 then raise exception 'Conservative forecast/operations signal missing';end if;
 update public.cw_clubs set cash=20000000,monthly_revenue=1000000 where career_id=cid and club_id='sport';
 if(public.career_world_status()->'investment'->'signal')<>'null'::jsonb then raise exception 'Balanced club received artificial pressure to invest';end if;
 -- Public wrappers require an authenticated career; internal helpers/tables cannot be called from clients.
 if has_function_privilege('anon','public.career_funding_quote(text,uuid,jsonb)','execute')
  or has_function_privilege('authenticated','public.cw_funding_quote(uuid,text,uuid,jsonb)','execute')
  or has_table_privilege('authenticated','public.cw_board_contributions','select') then raise exception 'Funding internals exposed';end if;
 perform set_config('request.jwt.claim.sub','56560000-0000-0000-0000-000000000099',true);
 begin perform public.career_club_investment_preview(1);raise exception 'Expected missing career rejection';
 exception when raise_exception then if sqlerrm not like 'Carreira ativa não encontrada%' then raise;end if;end;
 raise notice 'PASS read-only quotes, exact shortfall, minimal optional contribution, real renewal funding, replay safety, stale confirmation, capped board support, rounding, renewal notices, persistent dismissal, closed window/project gates and private ACL';
end $test$;
rollback;
