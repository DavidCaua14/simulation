-- Financial season rehearsal in a local disposable database; no real careers are touched.
do $$ begin if current_database() not like 'simulation_validation_%' then raise exception 'Disposable local database required';end if;end $$;
begin;
do $test$
#variable_conflict use_column
declare own text;uid uuid;cid uuid;r jsonb;sid uuid;m int;first_day date;after_month date;f record;my_goals int;their_goals int;
 initial_cash bigint;final_cash bigint;salary_before bigint;start_coins int;gate_total bigint;prize_total bigint;wages_total bigint;commercial_total bigint;ops_total bigint;debt bigint;cash_floor bigint;
begin
 foreach own in array array['sport','flamengo'] loop
  uid:=gen_random_uuid();cid:=gen_random_uuid();
  insert into auth.users(id) values(uid);
  insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins) values(cid,uid,'Season-'||left(cid::text,8),own,'1',30,1000);
  perform set_config('request.jwt.claim.sub',uid::text,true);
  r:=public.career_runtime_initialize();
  select primary_season into sid from public.cw_world where career_id=cid;
  perform public.cw_prepare_club_economy(cid);
  select cash into initial_cash from public.cw_clubs where career_id=cid and club_id=own;cash_floor:=initial_cash;
  select coins into start_coins from public.careers where id=cid;
  for m in 1..12 loop
   first_day:=make_date(2026,m,1);after_month:=(first_day+interval '1 month')::date;
   for f in select fx.* from public.season_fixtures fx join public.cw_fixture_dates fd on fd.fixture_id=fx.id
    join public.sim_competitions co on co.id=fx.competition_id
    where fx.season_id=sid and fx.status='pending' and co.kind='league' and own in(fx.home_club,fx.away_club)
     and fd.due_on>=first_day and fd.due_on<after_month order by fd.due_on,fx.id loop
    my_goals:=case when f.round_no%10<5 then 2 when f.round_no%10<8 then 1 else 0 end;
    their_goals:=case when f.round_no%10<5 then 0 when f.round_no%10<8 then 1 else 2 end;
    update public.season_fixtures set status='played',home_goals=case when home_club=own then my_goals else their_goals end,
     away_goals=case when home_club=own then their_goals else my_goals end,player_match=false,coach_club=own,played_at=now() where id=f.id;
   end loop;
   update public.cw_world set today=after_month where career_id=cid;
   perform public.cw_settle_month(cid,first_day);
   select cash,cw_clubs.debt into final_cash,debt from public.cw_clubs where career_id=cid and club_id=own;
   cash_floor:=least(cash_floor,final_cash);
   if debt<>0 or exists(select 1 from public.cw_contracts where career_id=cid and club_id=own and arrears>0) then raise exception 'Balanced % developed wage arrears in month %',own,m;end if;
  end loop;
  select coalesce(sum(amount)filter(where kind='matchday'),0),coalesce(sum(amount)filter(where kind='match_prize'),0),
   -coalesce(sum(amount)filter(where kind in('wages','coach_salary')),0),coalesce(sum(amount)filter(where kind='commercial'),0),
   -coalesce(sum(amount)filter(where kind in('operations','matchday_operations')),0)
   into gate_total,prize_total,wages_total,commercial_total,ops_total from public.cw_finance where career_id=cid and club_id=own;
  -- Modelo CM (evolução 62): bilheteria, prêmios e orçamento da diretoria entram na verba; salários não saem dela.
  if gate_total<=0 or prize_total<=0 then raise exception 'Annual rehearsal did not exercise match income';end if;
  if wages_total<>0 or commercial_total<>0 then raise exception 'Wages or monthly commercial entries still move the transfer funds';end if;
  if not exists(select 1 from public.cw_finance where career_id=cid and club_id=own and kind='board_budget') then raise exception 'Board season budget missing';end if;
  if (select wage_budget from public.cw_clubs where career_id=cid and club_id=own)<public.cw_payroll(cid,own) then raise exception 'Wage budget below payroll';end if;
  if final_cash<>initial_cash+gate_total+prize_total-ops_total+coalesce((select sum(amount) from public.cw_finance where career_id=cid and club_id=own and kind='board_budget'),0)
   then raise exception 'Unexplained club cash movement in annual rehearsal';end if;
  if(select coins from public.careers where id=cid)<>start_coins+coalesce((select sum(delta) from public.wallet_ledger where career_id=cid and reason='coach_salary' and currency='coins'),0) then raise exception 'Match income or denomination inflated the personal wallet';end if;
  raise notice 'PASS annual %: initial %, final %, minimum %, gate %, result prizes %, payroll %, commercial %, operations % (all R$)',own,
   initial_cash*1000,final_cash*1000,cash_floor*1000,gate_total*1000,prize_total*1000,wages_total*1000,commercial_total*1000,ops_total*1000;
 end loop;
end $test$;
rollback;
