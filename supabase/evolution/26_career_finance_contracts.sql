begin;
create or replace function public.cw_player_value(p_career uuid,p_player text)
returns bigint language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare rating numeric;age numeric;pot numeric;performance numeric:=1;
begin
 select r.rating,coalesce(cp.age_at_start,p.age,case when p.is_youth then 19 else 26 end)+coalesce(floor((w.today-w.started_on)/365.25),0),coalesce(cp.potential,r.rating)
 into rating,age,pot from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 left join public.cw_players cp on cp.career_id=p_career and cp.player_id=p.id left join public.cw_world w on w.career_id=p_career where p.id=p_player;
 if rating is null then raise exception 'Atleta sem avaliação';end if;
 select greatest(.85,least(1.15,1+(coalesce(avg(x.rating),6.5)-6.5)*.06)) into performance from(
  select a.rating from public.cw_appearances a where a.career_id=p_career and a.player_id=p_player and a.minutes>0 order by a.on_date desc,a.fixture_id desc limit 5)x;
 return round(performance*greatest(300,power(greatest(5,rating-45),2.7)*8)*case when age<23 then 1.25 when age<29 then 1 when age<33 then .75 else .4 end*(1+greatest(0,pot-rating)*.025))::bigint;
end $$;
create or replace function public.cw_cash(p_career uuid,p_club text,p_delta bigint,p_kind text,p_ref text,p_description text,p_allow_debt boolean default false,p_meta jsonb default '{}')
returns bigint language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare account public.cw_clubs;previous public.cw_finance;shortfall bigint:=0;next_cash bigint;
begin
 select * into account from public.cw_clubs where career_id=p_career and club_id=p_club for update;
 if not found then raise exception 'Caixa do clube inexistente nesta carreira';end if;
 select * into previous from public.cw_finance where career_id=p_career and club_id=p_club and kind=p_kind and reference=p_ref;
 if found then return previous.cash_after;end if;
 next_cash:=account.cash+p_delta;
 if next_cash<0 then
  if not p_allow_debt then raise exception 'Orçamento do clube insuficiente';end if;
  shortfall:=-next_cash;next_cash:=0;
 end if;
 update public.cw_clubs set cash=next_cash,debt=debt+shortfall where career_id=p_career and club_id=p_club;
 insert into public.cw_finance(career_id,club_id,on_date,kind,amount,cash_after,reference,description,metadata)
 values(p_career,p_club,(select today from public.cw_world where career_id=p_career),p_kind,p_delta,next_cash,p_ref,p_description,p_meta||jsonb_build_object('new_debt',shortfall));
 return next_cash;
end $$;
create or replace function public.cw_reserved(p_career uuid,p_club text)
returns bigint language sql stable security definer set search_path=public as $$
 select coalesce(sum(amount),0)::bigint from public.cw_commitments where career_id=p_career and club_id=p_club and status='reserved'
$$;
create or replace function public.cw_contract_cost(p_player text,p_salary bigint,p_appearance bigint,p_goal bigint,p_role text)
returns bigint language sql stable security definer set search_path=public as $$
 select p_salary+round((case p_role when 'key' then 4 when 'starter' then 3 when 'rotation' then 1.5 else .5 end)*
 (p_appearance+p_goal*case when p.position in('ATA','PD','PE') then .35 when p.position in('MEI','MC','ME','MD') then .12 when p.position='GOL' then 0 else .03 end))::bigint
 from public.sim_players p where p.id=p_player
$$;
create or replace function public.cw_payroll(p_career uuid,p_club text)
returns bigint language sql stable security definer set search_path=public as $$
 select (select coalesce(sum(public.cw_contract_cost(player_id,monthly_salary,appearance_bonus,goal_bonus,role)),0) from public.cw_contracts where career_id=p_career and club_id=p_club and status='active')+(select coalesce(sum(monthly_salary),0) from public.cw_coach_contracts where career_id=p_career and club_id=p_club and ended_on is null and expires_on>=(select today from public.cw_world where career_id=p_career))
$$;
create or replace function public.cw_available_budget(p_career uuid,p_club text)
returns bigint language sql stable security definer set search_path=public as $$
 select case when financial_risk>=75 then 0 else greatest(0,cash-public.cw_reserved(p_career,p_club)-public.cw_payroll(p_career,p_club)*(select reserve_salary_months from public.cw_rules)-debt) end
 from public.cw_clubs where career_id=p_career and club_id=p_club
$$;
create or replace function public.cw_initialize_finances(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare w public.cw_world;
begin
 select * into w from public.cw_world where career_id=p_career;
 if not w.stats_initialized then
  insert into public.cw_stats_opening(career_id,season_id,player_id,competition_id,club_id,apps,minutes,goals,assists,rating_sum)
   select p_career,st.season_id,st.player_id,st.competition_id,st.club_id,st.apps,st.minutes,st.goals,st.assists,st.rating_sum
   from public.mgr_player_stats st join public.career_seasons cs on cs.id=st.season_id where cs.career_id=p_career on conflict do nothing;
  update public.cw_world set stats_initialized=true where career_id=p_career;
 end if;
 insert into public.cw_clubs(career_id,club_id,cash,initial_budget,monthly_revenue,prestige,strategy,fanbase)
 select p_career,c.id,round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 round((2000+power(greatest(5,c.strength-40),2)*25)*case when public.cw_region(c.id)='ENG' then 1.5 else 1 end),
 c.strength,case abs(hashtext(c.id)::bigint)%4 when 0 then 'youth' when 1 then 'balanced' when 2 then 'ambitious' else 'sustainable' end,
 greatest(1000,(c.strength-30)*(c.strength-30)*150)
 from public.sim_clubs c on conflict do nothing;
 insert into public.cw_players(career_id,player_id,age_at_start,age_estimated,potential)
 select p_career,p.id,coalesce(p.age,case when p.is_youth then 19 else 26 end),p.age is null,
 least(99,round(r.rating)+case when coalesce(p.age,case when p.is_youth then 19 else 26 end)<23 then 12 else 3 end)
 from public.mgr_players mp join public.sim_players p on p.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where mp.career_id=p_career on conflict do nothing;
 update public.cw_players set market_value=public.cw_player_value(p_career,player_id) where career_id=p_career and market_value=0;
 insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,role)
 select p_career,mp.player_id,mp.club_id,w.today,(w.today+make_interval(years=>1+(abs(hashtext(mp.player_id)::bigint)%4)::int))::date,
 greatest(40,round(public.cw_player_value(p_career,mp.player_id)*.0065)),case when p.is_youth then 'prospect' when r.rating>=82 then 'key' when r.rating>=74 then 'starter' else 'rotation' end
 from public.mgr_players mp join public.sim_players p on p.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where mp.career_id=p_career and mp.club_id is not null and not exists(select 1 from public.cw_contracts ct where ct.career_id=p_career and ct.player_id=mp.player_id);
 update public.cw_players cp set promised_role=ct.role from public.cw_contracts ct where ct.career_id=cp.career_id and ct.player_id=cp.player_id and ct.status='active' and cp.career_id=p_career;
 insert into public.cw_finance(career_id,club_id,on_date,kind,amount,cash_after,reference,description)
 select p_career,c.club_id,w.today,'opening',c.cash,c.cash,'opening','Orçamento inicial estimado do clube' from public.cw_clubs c where c.career_id=p_career on conflict do nothing;
 insert into public.cw_coach_contracts(career_id,spell_id,club_id,starts_on,expires_on,monthly_salary)
 select p_career,c.spell_id,c.club_id,w.today,(w.today+interval '2years')::date,p.monthly_salary from public.mgr_coach c join public.cw_coach p on p.career_id=c.career_id
 where c.career_id=p_career and c.status='employed' and c.spell_id is not null on conflict do nothing;
end $$;

create or replace function public.cw_settle_month(p_career uuid,p_month date)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare month_end date:=(p_month+interval '1 month - 1 day')::date;month_days int;ct public.cw_contracts;staff public.cw_coach_contracts;club public.cw_clubs;
 due bigint;paid bigint;before_cash bigint;overlap int;ref text;apps int;goals int;revenue bigint;surplus bigint;debt_paid bigint;
begin
 perform 1 from public.careers where id=p_career for update;
 month_days:=month_end-p_month+1;
 for club in select * from public.cw_clubs where career_id=p_career order by club_id loop
  ref:=to_char(p_month,'YYYY-MM');
  select count(*) into apps from public.season_fixtures f join public.cw_fixture_dates d on d.fixture_id=f.id
   where d.career_id=p_career and f.status='played' and f.home_club=club.club_id and d.due_on between p_month and month_end;
  revenue:=club.monthly_revenue+apps*(300+club.prestige::int*12);
  perform public.cw_cash(p_career,club.club_id,revenue,'commercial',ref,'Receitas comerciais, torcida e bilheteria');
  perform public.cw_cash(p_career,club.club_id,-round(revenue*.12)::bigint,'operations',ref,'Comissão técnica e operação do clube',true);
 end loop;
 for ct in select * from public.cw_contracts where career_id=p_career and starts_on<=month_end and coalesce(ended_on,expires_on)>=p_month order by club_id,id loop
  ref:=ct.id::text||':'||to_char(p_month,'YYYY-MM');
  if exists(select 1 from public.cw_finance where career_id=p_career and club_id=ct.club_id and kind='wages' and reference=ref) then continue;end if;
  overlap:=greatest(0,least(month_end,ct.expires_on,coalesce(ct.ended_on,ct.expires_on))-greatest(p_month,ct.starts_on)+1);
  select count(*),coalesce(sum(mp.goals),0) into apps,goals from public.cw_appearances mp
   where mp.career_id=p_career and mp.player_id=ct.player_id and mp.club_id=ct.club_id and mp.minutes>0 and mp.on_date between greatest(p_month,ct.starts_on) and least(month_end,ct.expires_on,coalesce(ct.ended_on,ct.expires_on));
  due:=round(ct.monthly_salary*overlap::numeric/month_days)+apps*ct.appearance_bonus+goals*ct.goal_bonus;
  if due<=0 then continue;end if;
  select cash into before_cash from public.cw_clubs where career_id=p_career and club_id=ct.club_id;
  paid:=least(before_cash,due);
  perform public.cw_cash(p_career,ct.club_id,-due,'wages',ref,'Salário de '||public.mgr_player_name(ct.player_id),true,jsonb_build_object('contract_id',ct.id,'paid',paid,'owed',due-paid));
  update public.cw_contracts set arrears=arrears+due-paid where id=ct.id;
 end loop;
 for staff in select * from public.cw_coach_contracts where career_id=p_career and starts_on<=month_end and coalesce(ended_on,expires_on)>=p_month order by id loop
  ref:=staff.id::text||':'||to_char(p_month,'YYYY-MM');
  if exists(select 1 from public.cw_finance where career_id=p_career and club_id=staff.club_id and kind='coach_salary' and reference=ref) then continue;end if;
  overlap:=greatest(0,least(month_end,staff.expires_on,coalesce(staff.ended_on,staff.expires_on))-greatest(p_month,staff.starts_on)+1);
  due:=round(staff.monthly_salary*overlap::numeric/month_days);
  if due<=0 then continue;end if;
  select cash into before_cash from public.cw_clubs where career_id=p_career and club_id=staff.club_id;
  paid:=least(before_cash,due);
  perform public.cw_cash(p_career,staff.club_id,-due,'coach_salary',ref,'Salário do treinador',true,jsonb_build_object('paid',paid,'owed',due-paid));
  if paid>0 then perform public.econ_apply(p_career,'coins',paid::int,'coach_salary',ref);end if;
  update public.cw_coach_contracts set arrears=arrears+due-paid where id=staff.id;
 end loop;
 for club in select * from public.cw_clubs where career_id=p_career order by club_id loop
  -- Retained surpluses are recorded as club infrastructure, not unlimited cash for players.
  surplus:=greatest(0,club.cash-3*club.initial_budget);
  if surplus>0 and club.debt=0 and not exists(select 1 from public.cw_finance where career_id=p_career and club_id=club.club_id and kind='infrastructure' and reference=to_char(p_month,'YYYY-MM')) then
   perform public.cw_cash(p_career,club.club_id,-surplus,'infrastructure',to_char(p_month,'YYYY-MM'),'Investimento patrimonial da diretoria');
   update public.cw_clubs set infrastructure=infrastructure+surplus where career_id=p_career and club_id=club.club_id;
  end if;
 end loop;
end $$;

create or replace function public.cw_repay_arrears(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c public.cw_clubs;ct public.cw_contracts;st public.cw_coach_contracts;paid bigint;ref text;d date;
begin
 select today into d from public.cw_world where career_id=p_career;
 for c in select * from public.cw_clubs where career_id=p_career and debt>0 order by club_id loop
  for ct in select * from public.cw_contracts where career_id=p_career and club_id=c.club_id and arrears>0 order by starts_on,id loop
   ref:=ct.id||':'||d;
   if exists(select 1 from public.cw_finance where career_id=p_career and club_id=c.club_id and kind='arrears' and reference=ref) then continue;end if;
   select least(cash,ct.arrears) into paid from public.cw_clubs where career_id=p_career and club_id=c.club_id;
   if paid>0 then
    perform public.cw_cash(p_career,c.club_id,-paid,'arrears',ref,'Quitação de salários atrasados');
    update public.cw_contracts set arrears=arrears-paid where id=ct.id;
    update public.cw_clubs set debt=greatest(0,debt-paid) where career_id=p_career and club_id=c.club_id;
   end if;
  end loop;
  for st in select * from public.cw_coach_contracts where career_id=p_career and club_id=c.club_id and arrears>0 order by starts_on,id loop
   ref:=st.id||':'||d;
   if exists(select 1 from public.cw_finance where career_id=p_career and club_id=c.club_id and kind='staff_arrears' and reference=ref) then continue;end if;
   select least(cash,st.arrears) into paid from public.cw_clubs where career_id=p_career and club_id=c.club_id;
   if paid>0 then
    perform public.cw_cash(p_career,c.club_id,-paid,'staff_arrears',ref,'Quitação do salário do treinador');
    perform public.econ_apply(p_career,'coins',paid::int,'coach_arrears',ref);
    update public.cw_coach_contracts set arrears=arrears-paid where id=st.id;
    update public.cw_clubs set debt=greatest(0,debt-paid) where career_id=p_career and club_id=c.club_id;
   end if;
  end loop;
  select least(debt,greatest(0,cash-public.cw_payroll(p_career,c.club_id))) into paid from public.cw_clubs where career_id=p_career and club_id=c.club_id;
  if paid>0 and not exists(select 1 from public.cw_finance where career_id=p_career and club_id=c.club_id and kind='debt_repayment' and reference=d::text) then
   perform public.cw_cash(p_career,c.club_id,-paid,'debt_repayment',d::text,'Amortização da dívida do clube');
   update public.cw_clubs set debt=greatest(0,debt-paid) where career_id=p_career and club_id=c.club_id;
  end if;
 end loop;
end $$;

create or replace function public.cw_finance_tick(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare w public.cw_world;club public.cw_clubs;coach public.mgr_coach;risk numeric;rescue bigint;ref text;ct public.cw_contracts;staff public.cw_coach_contracts;paid bigint;balance bigint;
begin
 select * into w from public.cw_world where career_id=p_career;
 if extract(day from w.today)=1 then perform public.cw_settle_month(p_career,(date_trunc('month',w.today)-interval '1month')::date);end if;
 perform public.cw_repay_arrears(p_career);
 select * into coach from public.mgr_coach where career_id=p_career;
 for club in select * from public.cw_clubs where career_id=p_career order by club_id loop
  risk:=least(100,round(100.0*club.debt/greatest(club.monthly_revenue*6,1)+case when club.cash<public.cw_payroll(p_career,club.club_id) then 25 else 0 end,2));
  update public.cw_clubs set financial_risk=risk,distress_since=case when risk>=75 then coalesce(distress_since,w.today) else null end where career_id=p_career and club_id=club.club_id;
  if risk>=75 and club.rescue_year is distinct from extract(year from w.today)::int then
   rescue:=round(club.initial_budget*(select annual_rescue_fraction from public.cw_rules));
   perform public.cw_cash(p_career,club.club_id,rescue,'recovery',extract(year from w.today)::text,'Plano limitado de recuperação financeira');
   update public.cw_clubs set debt=debt+rescue,rescue_year=extract(year from w.today)::int where career_id=p_career and club_id=club.club_id;
   perform public.cw_news_add(p_career,'recovery:'||club.club_id||':'||extract(year from w.today),'finance',public.mgr_club_name(club.club_id)||' adota recuperação financeira',
    'A diretoria limita novas contratações e oferece um plano de recuperação. O clube segue disputando suas competições.',case when coach.club_id=club.club_id then 95 else 45 end,club.club_id);
  end if;
  if coach.club_id=club.club_id and risk>=75 then
   perform public.cw_news_add(p_career,'finance-warning:'||club.club_id||':'||to_char(w.today,'IYYY-IW'),'board','A diretoria cobra responsabilidade financeira',
    'A dívida ameaça a folha salarial. Venda atletas por negociação, reduza gastos ou invista recursos. Persistir nesta situação coloca seu emprego em risco.',95,club.club_id);
   if club.distress_since is not null and w.today-club.distress_since>=45 then
    update public.mgr_coach set board_confidence=greatest(0,board_confidence-3) where career_id=p_career;
    if w.today-club.distress_since>=60 then perform public.mgr_fire(p_career,'má gestão financeira persistente');end if;
   end if;
  end if;
 end loop;
 -- Expiry is a real release; pre-contracts are registered by the market service.
 for ct in select * from public.cw_contracts where career_id=p_career and status='active' and expires_on<w.today for update loop
  update public.cw_contracts set status='expired',ended_on=expires_on where id=ct.id;
  update public.mgr_players set club_id=null where career_id=p_career and player_id=ct.player_id and club_id=ct.club_id;
  perform public.cw_prune_lineups(p_career,ct.player_id);
  perform public.cw_news_add(p_career,'expiry:'||ct.id,'contract',public.mgr_player_name(ct.player_id)||' encerra seu contrato',
   'O atleta está livre após o encerramento do vínculo com '||public.mgr_club_name(ct.club_id)||'.',case when ct.club_id=coach.club_id then 85 else 30 end,ct.club_id,ct.player_id);
 end loop;
end $$;

create or replace function public.career_club_invest(p_amount int,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;club text;previous jsonb;cash bigint;
begin
 car:=public.mgr_lock();perform public.cw_ensure(car.id);
 previous:=public.econ_request_get(car.id,p_request,'club_invest');if previous is not null then return previous;end if;
 select club_id into club from public.mgr_coach where career_id=car.id and status='employed';
 if club is null then raise exception 'Assuma um clube antes de investir';end if;
 if p_amount is null or p_amount<1 or p_amount>1000000 then raise exception 'Investimento inválido';end if;
 perform public.econ_apply(car.id,'coins',-p_amount,'club_investment',p_request::text);
 cash:=public.cw_cash(car.id,club,p_amount,'coach_investment',p_request::text,'Investimento pessoal do treinador');
 perform public.cw_news_add(car.id,'investment:'||p_request,'finance','Treinador reforça o caixa do clube',p_amount||' moedas foram transferidas da carteira pessoal para o orçamento do clube.',70,club);
 return public.econ_request_save(car.id,p_request,'club_invest',jsonb_build_object('ok',true,'club_cash',cash,'personal_coins',car.coins-p_amount));
end $$;
revoke all on function public.career_club_invest(int,uuid) from public,anon;
grant execute on function public.career_club_invest(int,uuid) to authenticated;
commit;
