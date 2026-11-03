-- Transfer integrity: no existing career, contract or negotiated agreement is rewritten at install.
begin;
-- Private, durable receipts survive the pruning of negotiation details.
do $$ begin
 if to_regclass('public.cw_transfer_registrations') is null then
  create table public.cw_transfer_registrations(
   career_id uuid not null references public.careers(id) on delete cascade,
   negotiation_id uuid not null,player_id text not null,buyer_club text not null,registered_on date not null,
   primary key(career_id,negotiation_id));
  create index cw_transfer_registrations_window_idx on public.cw_transfer_registrations(career_id,buyer_club,registered_on);
  insert into public.cw_transfer_registrations
   select career_id,id,player_id,buyer_club,register_on from public.cw_negotiations
   where status='completed' and initiator='user' and register_on is not null;
 end if;
 if to_regclass('public.cw_market_legacy_agreements') is null then
  create table public.cw_market_legacy_agreements(
   negotiation_id uuid primary key references public.cw_negotiations(id) on delete cascade,
   career_id uuid not null references public.careers(id) on delete cascade);
  insert into public.cw_market_legacy_agreements select id,career_id from public.cw_negotiations where status in('agreed','precontract');
 end if;
end $$;
create table if not exists public.cw_ai_roster_recoveries(
 career_id uuid not null references public.careers(id) on delete cascade,player_id text not null,
 club_id text not null,restored_on date not null,primary key(career_id,player_id));
alter table public.cw_ai_roster_recoveries enable row level security;
revoke all on public.cw_ai_roster_recoveries from public,anon,authenticated;
alter table public.cw_transfer_registrations enable row level security;
alter table public.cw_market_legacy_agreements enable row level security;
revoke all on public.cw_transfer_registrations,public.cw_market_legacy_agreements from public,anon,authenticated;

create or replace function public.cw_transfer_window(p_region text,p_date date,out starts_on date,out ends_on date)
returns record language sql stable security definer set search_path=public as $$
 select s,e from(
  select make_date(extract(year from p_date)::int+y.n,w.start_month,w.start_day) s,
   make_date(extract(year from p_date)::int+y.n+case when(w.end_month,w.end_day)<(w.start_month,w.start_day) then 1 else 0 end,w.end_month,w.end_day) e
  from public.cw_windows w cross join generate_series(-1,2)y(n) where w.region=p_region
 )x where e>=p_date order by case when p_date between s and e then 0 else 1 end,s limit 1
$$;
create or replace function public.cw_registered_in_window(p_career uuid,p_club text,p_date date)
returns int language sql stable security definer set search_path=public as $$
 select count(*)::int from public.cw_transfer_registrations r
 cross join public.cw_transfer_window(public.cw_region(p_club),p_date) b
 where r.career_id=p_career and r.buyer_club=p_club and r.registered_on between b.starts_on and b.ends_on
$$;
create or replace function public.cw_salary_floor(p_player text)
returns bigint language sql stable security definer set search_path=public as $$
 select greatest(80,ceil(power(greatest(1,r.rating-45),2)*.65+power(greatest(0,r.rating-75),2)*12))::bigint
 from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position where p.id=p_player
$$;
create or replace function public.cw_salary_demand(p_career uuid,p_player text,p_buyer text)
returns bigint language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare wage bigint;source_club text;prestige numeric;buyer_prestige numeric;
begin
 select monthly_salary,club_id into wage,source_club from public.cw_contracts where career_id=p_career and player_id=p_player
 order by(status='active') desc,starts_on desc,id limit 1;
 select coalesce(source_club,club_id) into source_club from public.sim_players where id=p_player;
 select coalesce((select c.prestige from public.cw_clubs c where c.career_id=p_career and c.club_id=source_club),(select strength from public.sim_clubs where id=source_club),0) into prestige;
 select coalesce((select c.prestige from public.cw_clubs c where c.career_id=p_career and c.club_id=p_buyer),(select strength from public.sim_clubs where id=p_buyer),0) into buyer_prestige;
 return ceil(greatest(public.cw_salary_floor(p_player),coalesce(wage,0)*case when source_club=p_buyer then 1.08 else 1.12 end)
  *(1+least(.75,greatest(0,prestige-buyer_prestige)*.025)))::bigint;
end $$;
create or replace function public.cw_project_reason(p_career uuid,p_player text,p_buyer text)
returns text language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare rating numeric;prestige numeric;current_club text;
begin
 select club_id into current_club from public.mgr_players where career_id=p_career and player_id=p_player;
 if current_club=p_buyer then return null;end if;
 select r.rating into rating from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position where p.id=p_player;
 select coalesce((select c.prestige from public.cw_clubs c where c.career_id=p_career and c.club_id=p_buyer),(select strength from public.sim_clubs where id=p_buyer)) into prestige;
 if rating is null or prestige is null then return 'Projeto esportivo indisponível para este atleta.';end if;
 -- Quality still matters for veterans and for players with an estimated age.
 if rating-prestige>(case when rating>=85 then 10 else 14 end) then
  return 'O atleta considera o nível esportivo do clube insuficiente e prefere uma equipe compatível com sua qualidade.';
 end if;
 if rating>=85 and public.cw_club_level(p_buyer)>1 then return 'Um atleta de elite não aceita este projeto em uma divisão inferior.';end if;
 return null;
end $$;
create or replace function public.cw_minimum_signing(p_career uuid,p_player text,p_buyer text)
returns bigint language plpgsql stable security definer set search_path=public as $$
begin
 if public.cw_effective_player_club(p_career,p_player) is null then return 2*public.cw_salary_demand(p_career,p_player,p_buyer);end if;
 return 0;
end $$;
create or replace function public.cw_can_afford_contract(p_id uuid)
returns boolean language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare n public.cw_negotiations;c public.cw_clubs;payroll bigint;increment bigint;existing bigint;
begin
 select * into n from public.cw_negotiations where id=p_id;
 select * into c from public.cw_clubs where career_id=n.career_id and club_id=n.buyer_club;
 if c.club_id is null or c.financial_risk>=75 then return false;end if;
 payroll:=public.cw_payroll(n.career_id,n.buyer_club);
 select coalesce(sum(public.cw_contract_cost(player_id,monthly_salary,appearance_bonus,goal_bonus,role)),0) into existing
  from public.cw_contracts where career_id=n.career_id and player_id=n.player_id and club_id=n.buyer_club and status='active';
 increment:=greatest(0,public.cw_contract_cost(n.player_id,n.monthly_salary,n.appearance_bonus,n.goal_bonus,n.role)-existing);
 return c.cash-c.debt-public.cw_reserved(n.career_id,n.buyer_club)
   +coalesce((select amount from public.cw_commitments where career_id=n.career_id and reference=n.id||':offer' and status='reserved'),0)
  >=n.fee+n.signing_bonus+n.performance_bonus+(select reserve_salary_months from public.cw_rules)*payroll+6*increment;
end $$;

-- A catalogue owner may be recovered only for an untouched AI star, never a human release or an open deal.
create or replace function public.cw_ai_recovery_club(p_career uuid,p_player text)
returns text language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare owner text;candidate text;rating numeric;d date;
begin
 select club_id into owner from public.mgr_players where career_id=p_career and player_id=p_player;
 if not found or owner is not null then return null;end if;
 select coalesce((select ct.club_id from public.cw_contracts ct where ct.career_id=p_career and ct.player_id=p_player order by ct.expires_on desc,ct.starts_on desc,ct.id limit 1),p.club_id),r.rating into candidate,rating from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position where p.id=p_player and p.active;
 if candidate is null or rating<80 then return null;end if;
 select today into d from public.cw_world where career_id=p_career;
 if exists(select 1 from public.cw_ai_roster_recoveries where career_id=p_career and player_id=p_player)
  or exists(select 1 from public.cw_clubs c where c.career_id=p_career and c.club_id=candidate and(c.financial_risk>=75 or c.cash-c.debt-public.cw_reserved(p_career,candidate)<2*public.cw_payroll(p_career,candidate)+6*public.cw_salary_floor(p_player) or c.monthly_revenue<public.cw_payroll(p_career,candidate)+public.cw_salary_floor(p_player)))
  or exists(select 1 from public.cw_contracts where career_id=p_career and player_id=p_player and status='active')
  or exists(select 1 from public.mgr_spells where career_id=p_career and club_id=candidate)
  or exists(select 1 from public.cw_contracts ct join public.mgr_spells s on s.career_id=ct.career_id and s.club_id=ct.club_id where ct.career_id=p_career and ct.player_id=p_player)
  or exists(select 1 from public.mgr_transfers t join public.mgr_spells s on s.career_id=t.career_id and s.club_id in(t.from_club,t.to_club) where t.career_id=p_career and t.player_id=p_player)
  or exists(select 1 from public.mgr_player_stats st join public.career_seasons s on s.id=st.season_id where s.career_id=p_career and st.player_id=p_player and s.was_coached and st.club_id=s.club_id)
  or exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=p_player and
   (n.status in('agreed','precontract') or(n.status in('seller_review','club_pending','club_counter','player_pending','player_counter') and n.expires_on>=d)))
 then return null;end if;
 return candidate;
end $$;
create or replace function public.cw_effective_player_club(p_career uuid,p_player text)
returns text language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare owner text;
begin
 select club_id into owner from public.mgr_players where career_id=p_career and player_id=p_player;
 if not found then select club_id into owner from public.sim_players where id=p_player;return owner;end if;
 return coalesce(owner,public.cw_ai_recovery_club(p_career,p_player));
end $$;
create or replace function public.cw_recover_ai_free_players(p_career uuid,p_player text default null)
returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare p record;candidate text;d date;n int:=0;
begin
 perform 1 from public.careers where id=p_career for update;
 select today into d from public.cw_world where career_id=p_career;
 for p in select mp.player_id from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
  join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
  where mp.career_id=p_career and mp.club_id is null and r.rating>=80 and(p_player is null or mp.player_id=p_player) order by mp.player_id loop
  candidate:=public.cw_ai_recovery_club(p_career,p.player_id);
  if candidate is null then continue;end if;
  perform public.cw_ensure_club_finance(p_career,candidate);
  update public.mgr_players set club_id=candidate where career_id=p_career and player_id=p.player_id and club_id is null;
  insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,role)
   values(p_career,p.player_id,candidate,d,d+730,public.cw_salary_floor(p.player_id),'key');
  insert into public.cw_ai_roster_recoveries values(p_career,p.player_id,candidate,d) on conflict do nothing;
  n:=n+1;
 end loop;
 return n;
end $$;
create or replace function public.cw_ai_contracts_tick(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ct public.cw_contracts;d date;own text;wage bigint;payroll bigint;revenue bigint;cash bigint;inactive boolean;
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 perform public.cw_recover_ai_free_players(p_career);
 for ct in select x.* from public.cw_contracts x join public.mgr_players mp on mp.career_id=x.career_id and mp.player_id=x.player_id and mp.club_id=x.club_id
  where x.career_id=p_career and x.status='active' and x.club_id is distinct from own and x.expires_on<=d+45
  and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=x.player_id and
   (n.status in('agreed','precontract') or(n.status in('seller_review','club_pending','club_counter','player_pending','player_counter') and n.expires_on>=d)))
  order by x.club_id,x.player_id for update of x loop
  inactive:=public.cw_runtime_enabled(p_career) and ct.club_id not in(select public.cw_domestic_clubs(p_career));
  if inactive then
   -- Dormant leagues retain their clubs; no salary, cash, results or market simulation is advanced there.
   if ct.expires_on<d then update public.cw_contracts set expires_on=ct.expires_on+make_interval(years=>greatest(2,ceil((d-ct.expires_on)/365.0)::int+2)) where id=ct.id;end if;
   continue;
  end if;
  wage:=greatest(ct.monthly_salary,public.cw_salary_floor(ct.player_id));
  select c.monthly_revenue,c.cash-c.debt-public.cw_reserved(p_career,ct.club_id) into revenue,cash from public.cw_clubs c where c.career_id=p_career and c.club_id=ct.club_id and c.financial_risk<75;
  payroll:=public.cw_payroll(p_career,ct.club_id);
  if revenue is not null and cash>=2*payroll+6*greatest(0,wage-ct.monthly_salary)
   and payroll-ct.monthly_salary+wage<=revenue
   and((select r.rating>=80 from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position where p.id=ct.player_id)
    or coalesce((select morale from public.cw_players where career_id=p_career and player_id=ct.player_id),65)>=35) then
   update public.cw_contracts set status='ended',ended_on=d-1 where id=ct.id;
   insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,appearance_bonus,goal_bonus,role)
    values(p_career,ct.player_id,ct.club_id,d,d+730,wage,ct.appearance_bonus,ct.goal_bonus,ct.role);
  end if;
 end loop;
end $$;

-- Existing engines with localized corrections.
CREATE OR REPLACE FUNCTION public.cw_market_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare d date;own text;n public.cw_negotiations;ct public.cw_contracts;cp public.cw_players;rk int;minfee numeric;
 sb public.sim_clubs;bb public.sim_clubs;age int;rating numeric;wants_out boolean;
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 -- Every new decision uses the same salary floor, including renewals and free agents.
 for n in select * from public.cw_negotiations where career_id=p_career and status='player_pending' and reply_on<=d and expires_on>=d order by created_on,id for update loop
  if n.initiator<>'renewal' and public.cw_project_reason(p_career,n.player_id,n.buyer_club) is not null then
   perform public.cw_neg_close(n.id,'rejected',public.cw_project_reason(p_career,n.player_id,n.buyer_club));continue;
  end if;
  if n.monthly_salary<public.cw_salary_demand(p_career,n.player_id,n.buyer_club)
   or(n.seller_club is null and n.initiator<>'renewal' and n.signing_bonus<public.cw_minimum_signing(p_career,n.player_id,n.buyer_club)) then
   if n.round_no>=3 then perform public.cw_neg_close(n.id,'rejected','O atleta recusou as condições salariais e as luvas.');
   else
    update public.cw_negotiations set status='player_counter',monthly_salary=greatest(monthly_salary,public.cw_salary_demand(p_career,n.player_id,n.buyer_club)),
     signing_bonus=greatest(signing_bonus,case when seller_club is null and initiator<>'renewal' then public.cw_minimum_signing(p_career,n.player_id,n.buyer_club) else 0 end),
     round_no=round_no+1,expires_on=public.cw_deadline(d),response='O atleta exige salário e luvas compatíveis com sua qualidade e com o projeto esportivo.' where id=n.id;
    perform public.cw_neg_history(n.id,'player','Exigência salarial e de luvas atualizada.');
   end if;
  end if;
 end loop;
 -- Comprador da IA aceita o pedido salarial do atleta (evolução 37).
 update public.cw_negotiations set status='player_pending',reply_on=d,response='O clube comprador aceitou as condições pedidas pelo atleta.'
  where career_id=p_career and status='player_counter' and initiator<>'renewal' and buyer_club is distinct from own and expires_on>=d;

 for n in select * from public.cw_negotiations where career_id=p_career and status in('club_pending','player_pending') and reply_on<=d and expires_on>=d
   and initiator<>'renewal' order by created_on,id for update loop
  select * into ct from public.cw_contracts where career_id=p_career and player_id=n.player_id and status='active';
  select * into cp from public.cw_players where career_id=p_career and player_id=n.player_id;
  select * into bb from public.sim_clubs where id=n.buyer_club;
  select * into sb from public.sim_clubs where id=n.seller_club;
  select r.rating into rating from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position where p.id=n.player_id;
  age:=cp.age_at_start+floor((d-(select started_on from public.cw_world where career_id=p_career))/365.25)::int;
  wants_out:=coalesce(cp.transfer_requested,false) or coalesce(cp.morale,60)<30;

  -- Clube vendedor da IA: pilares e titulares não saem por qualquer valor.
  if n.status='club_pending' and n.seller_club is not null and n.seller_club is distinct from own
     and not wants_out and coalesce(ct.expires_on,d+999)>=d+180 and n.register_on is null then
   rk:=public.cw_squad_rank(p_career,n.seller_club,n.player_id);
   if rk<=3 and not(bb.strength>sb.strength+5 and n.fee>=n.valuation*3 and n.decision_roll>.7) then
    perform public.cw_neg_close(n.id,'rejected',public.mgr_club_name(n.seller_club)||' considera '||public.mgr_player_name(n.player_id)||' intocável: é um dos pilares do elenco.');
   elsif rk between 4 and 7 or (rk between 8 and 11 and n.initiator<>'ai') then
    if n.decision_roll<.2 then
     perform public.cw_neg_close(n.id,'rejected',public.mgr_club_name(n.seller_club)||' não quer perder um titular agora.');
    else
     -- Titulares principais (4º–7º) custam 1,6–2× o valor; os demais titulares (8º–11º), 1,25–1,5×. Comprador menor paga 20% a mais.
     minfee:=n.valuation*case when rk<=7 then 1.6+n.decision_roll*.4 else 1.25+n.decision_roll*.25 end*case when bb.strength<sb.strength then 1.2 else 1 end;
     if n.fee<minfee then
      if n.initiator='ai' and n.decision_roll>.3 and public.cw_available_budget(p_career,n.buyer_club)>=minfee then
       -- Comprador da IA com caixa topa pagar o preço de um titular.
       update public.cw_negotiations set fee=ceil(minfee) where id=n.id;
       perform public.cw_neg_history(n.id,'buyer','Comprador aceitou pagar o preço pedido por um titular.');
      elsif n.round_no>=2 or n.initiator='ai' then
       perform public.cw_neg_close(n.id,'rejected','O clube só libera um titular por um valor bem acima do mercado.');
      else
       update public.cw_negotiations set status='club_counter',fee=ceil(minfee),round_no=round_no+1,expires_on=public.cw_deadline(d),
        response='Titular do elenco: o clube só negocia por '||ceil(minfee)||' moedas.' where id=n.id;
       perform public.cw_neg_history(n.id,'seller','Contraproposta por um titular.');
      end if;
     end if;
    end if;
   end if;

  -- Atleta: carreira em primeiro lugar (não desce de divisão nem vai para clube bem menor sem motivo).
  elsif n.status='player_pending' and bb.id is not null then
   if sb.id is null then
    if rating>=bb.strength+12 and age<31 then
     perform public.cw_neg_close(n.id,'rejected',public.mgr_player_name(n.player_id)||' prefere esperar uma proposta de um clube do seu nível.');
    end if;
   elsif public.cw_club_level(n.buyer_club)>public.cw_club_level(n.seller_club)
      and not(age>=32 or (wants_out and n.monthly_salary>=coalesce(ct.monthly_salary,0)*1.3)) then
    perform public.cw_neg_close(n.id,'rejected',public.mgr_player_name(n.player_id)||' não aceita deixar a primeira divisão por um clube de divisão inferior: seria um retrocesso na carreira.');
   elsif public.cw_club_level(n.buyer_club)=public.cw_club_level(n.seller_club) and bb.strength<sb.strength-8
      and not(age>=31 or wants_out or n.monthly_salary>=coalesce(ct.monthly_salary,0)*1.5) then
    perform public.cw_neg_close(n.id,'rejected',public.mgr_player_name(n.player_id)||' considera '||public.mgr_club_name(n.buyer_club)||' pequeno para o momento da carreira.');
   end if;
  end if;
 end loop;
 perform public.cw_market_tick_before_v37(p_career);
end $function$;

CREATE OR REPLACE FUNCTION public.cw_market_tick_before_v37(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare d date;own text;n public.cw_negotiations;ct public.cw_contracts;threshold numeric;interest numeric;buyer public.cw_clubs;seller public.cw_clubs;
 r record;c public.cw_clubs;p record;id uuid;value bigint;cnt int;expected numeric;apps int;games int;new_morale numeric;paid bigint;user_region text;depth jsonb;style text;
begin
 select today into d from public.cw_world where career_id=p_career;
 if extract(doy from d)=1 then update public.cw_players set market_value=public.cw_player_value(p_career,player_id) where career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or player_id in(select player_id from public.mgr_players where career_id=p_career and club_id in (select public.cw_domestic_clubs(p_career))));end if;
 select club_id into own from public.mgr_coach where career_id=p_career;
 for n in select * from public.cw_negotiations where career_id=p_career and status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract') order by created_on,id for update loop
  if n.status in('agreed','precontract') then perform public.cw_register_transfer(n.id);continue;end if;
  if n.expires_on<d then perform public.cw_neg_close(n.id,'expired','Prazo da proposta encerrado.');continue;end if;
  if n.reply_on>d or n.status in('seller_review','club_counter','player_counter') then continue;end if;
  select * into ct from public.cw_contracts where career_id=p_career and player_id=n.player_id and status='active';
  select * into buyer from public.cw_clubs where career_id=p_career and club_id=n.buyer_club;
  select * into seller from public.cw_clubs where career_id=p_career and club_id=n.seller_club;
  if n.status='club_pending' then
   select count(*) into cnt from public.mgr_players where career_id=p_career and club_id=n.seller_club;
   threshold:=n.valuation*(case when seller.financial_risk>=50 then .85 else 1.05 end)+n.valuation*case when ct.role='key' then .35 else .05 end;
   threshold:=threshold*(.9+n.decision_roll*.3)*case when ct.expires_on<d+180 then .65 else 1 end;
   if exists(select 1 from public.cw_rivalries rv where rv.club_a=least(n.buyer_club,n.seller_club) and rv.club_b=greatest(n.buyer_club,n.seller_club)) then threshold:=threshold*1.12;end if;
   threshold:=threshold*(1+least(.20,.04*(select count(*) from public.cw_negotiations z where z.career_id=p_career and z.player_id=n.player_id and z.id<>n.id and z.status in('club_pending','player_pending','seller_review'))));
   if n.seller_club is null or n.register_on>coalesce(ct.expires_on,d+999) then threshold:=0;end if;
   if (cnt<=18 and threshold>0) or n.decision_roll<.04 then
    perform public.cw_neg_close(n.id,'rejected','O clube considera o atleta indispensável ou não tem reposição.');
   elsif n.fee+n.performance_bonus*.5<threshold then
    if n.round_no>=2 or n.fee<threshold*.55 then perform public.cw_neg_close(n.id,'rejected','Os valores não atendem à avaliação do clube.');
    else
     update public.cw_negotiations set status='club_counter',fee=ceil(threshold),round_no=round_no+1,expires_on=public.cw_deadline(d),response='O clube pede uma revisão do valor.' where id=n.id;
     if n.initiator='ai' then perform public.cw_neg_close(n.id,'rejected','O comprador desistiu da contraproposta.');else perform public.cw_neg_history(n.id,'seller','Contraproposta do clube vendedor.');end if;
    end if;
   else
    update public.cw_negotiations set status='player_counter',response='Clube de acordo. Apresente salário, duração, luvas e papel ao atleta.',expires_on=public.cw_deadline(d) where id=n.id;
    if n.initiator='ai' then
     update public.cw_negotiations set status='player_pending',monthly_salary=public.cw_salary_demand(p_career,n.player_id,n.buyer_club),contract_years=3,signing_bonus=ceil(n.valuation*.02),reply_on=d+2 where id=n.id;
    end if;
    perform public.cw_neg_history(n.id,'seller','Condições entre clubes aprovadas.');
   end if;
  elsif n.status='player_pending' then
   interest:=coalesce(public.cw_contract_cost(ct.player_id,ct.monthly_salary,ct.appearance_bonus,ct.goal_bonus,ct.role),greatest(40,n.valuation*.0065))*case when buyer.prestige>=coalesce(seller.prestige,0)+5 then 1.02 else 1.12 end;
   interest:=interest*(1+greatest(0,coalesce(seller.prestige,0)-buyer.prestige)*.015);
   interest:=interest*case when (select morale from public.cw_players where career_id=p_career and player_id=n.player_id)<35 and n.initiator='renewal' then 1.35 else 1 end;
   interest:=interest*case when n.role='prospect' and coalesce(ct.role,'rotation') in('key','starter') then 1.35 else 1 end;
   if n.decision_roll<.06 and buyer.prestige<coalesce(seller.prestige,0) then
    perform public.cw_neg_close(n.id,'rejected','O atleta recusou o projeto esportivo, independentemente da remuneração.');continue;
   end if;
   if (public.cw_contract_cost(n.player_id,n.monthly_salary,n.appearance_bonus,n.goal_bonus,n.role)+n.signing_bonus/greatest(12*n.contract_years,1))<interest then
    if n.round_no>=3 or n.monthly_salary<interest*.65 then perform public.cw_neg_close(n.id,'rejected','O atleta recusou salário, papel ou projeto esportivo.');
    else update public.cw_negotiations set status='player_counter',monthly_salary=ceil(interest),round_no=round_no+1,expires_on=public.cw_deadline(d),response='O atleta pede melhores condições salariais.' where id=n.id;perform public.cw_neg_history(n.id,'player','Contraproposta salarial do atleta.');end if;
   elsif exists(select 1 from public.cw_negotiations where career_id=p_career and player_id=n.player_id and id<>n.id and status in('agreed','precontract')) then
    perform public.cw_neg_close(n.id,'rejected','O atleta já assinou um acordo.');
   else
    begin
     perform public.cw_reserve_offer(n.id);
     update public.cw_negotiations set status=case when n.register_on is not null then 'precontract' else 'agreed' end,response='Ambas as partes aprovaram. Aguardando registro.',register_on=coalesce(n.register_on,case when n.seller_club is not null and n.initiator<>'renewal' and not public.cw_window_open(public.cw_region(n.buyer_club),d) then public.cw_next_window(public.cw_region(n.buyer_club),d) else d end) where id=n.id;
     perform public.cw_neg_history(n.id,'player','Condições do atleta aprovadas.');perform public.cw_register_transfer(n.id);
    exception when raise_exception then perform public.cw_neg_close(n.id,'failed_funds',sqlerrm);end;
   end if;
  end if;
 end loop;
 -- Scheduled transfer liabilities are paid once; performance clauses require ten actual appearances.
 for r in select cm.*,n.player_id,n.seller_club,n.register_on from public.cw_commitments cm join public.cw_negotiations n on n.id=cm.negotiation_id
  where cm.career_id=p_career and cm.status='reserved' and n.status='completed' and cm.kind in('installment','performance') order by cm.due_on,cm.id loop
  if r.kind='performance' then
   select count(*) into apps from public.cw_appearances mp where mp.career_id=p_career and mp.player_id=r.player_id and mp.club_id=r.club_id and mp.minutes>0 and mp.on_date>=r.register_on;
   if apps<10 and d<r.due_on then continue;end if;
   if apps<10 then update public.cw_commitments set status='released' where id=r.id;continue;end if;
  elsif r.due_on>d then continue;end if;
  perform public.cw_cash(p_career,r.club_id,-r.amount,'transfer_clause',r.id::text,'Parcela ou bônus da contratação',true);
  if r.seller_club is not null then perform public.cw_cash(p_career,r.seller_club,r.amount,'player_sale_clause',r.id::text,'Recebimento de parcela ou bônus');end if;
  update public.cw_commitments set status='paid' where id=r.id;
 end loop;
 -- Satisfação semanal pelos minutos reais x papel prometido e pelos salários em dia (evolução 34).
 -- Reservas e promessas aceitam o papel (não caem abaixo de 40 só por minutos); quem cobra espaço é o titular encostado.
 for p in select cp.*,mp.club_id,ct.arrears,ct.starts_on,ct.role from public.cw_players cp join public.mgr_players mp using(career_id,player_id)
  join public.cw_contracts ct on ct.career_id=cp.career_id and ct.player_id=cp.player_id and ct.status='active'
  where cp.career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or mp.club_id in (select public.cw_domestic_clubs(p_career)) or mp.club_id=own) and (cp.last_morale_on is null or cp.last_morale_on<=d-7) loop
  if d-p.starts_on<28 then update public.cw_players set last_morale_on=d where career_id=p_career and player_id=p.player_id;continue;end if;
  select count(*) into games from public.cw_club_dates fd join public.season_fixtures f on f.id=fd.fixture_id where fd.career_id=p_career and fd.club_id=p.club_id and f.status='played' and fd.due_on between d-28 and d;
  select count(*) into apps from public.cw_appearances mp where mp.career_id=p_career and mp.player_id=p.player_id and mp.club_id=p.club_id and mp.minutes>=30 and mp.on_date between d-28 and d;
  expected:=case p.promised_role when 'key' then .70 when 'starter' then .50 when 'rotation' then .20 else 0 end;
  -- Clubes da IA conversam com quem não tem espaço: o papel prometido passa a ser de reserva (o seu clube decide sozinho).
  if p.club_id is distinct from own and games>=3 and expected>.2 and apps::numeric/games<expected*.4 and random()<.5 then
   update public.cw_players set promised_role='rotation' where career_id=p_career and player_id=p.player_id;
   update public.cw_contracts set role='rotation' where career_id=p_career and player_id=p.player_id and status='active';
   expected:=.20;
  end if;
  if games<3 or expected=0 or apps::numeric/games>=expected then
   -- Papel cumprido (ou sem jogos suficientes): recupera, mais rápido quando estava insatisfeito; perto do topo sobe devagar.
   new_morale:=p.morale+case when p.morale<50 then 6 when p.morale<80 then 3 else 1 end;
  else
   new_morale:=greatest(least(p.morale,case p.promised_role when 'key' then 5 when 'starter' then 15 else 40 end),
    p.morale-round(2+4*(expected-apps::numeric/games)/expected));
  end if;
  new_morale:=greatest(0,least(100,new_morale-case when p.arrears>0 then 12 else 0 end));
  update public.cw_players set morale=new_morale,last_morale_on=d,transfer_requested=new_morale<30,
   last_warning_on=case when new_morale<45 then coalesce(last_warning_on,d) else null end where career_id=p_career and player_id=p.player_id;
  if new_morale<45 and p.morale>=45 and p.club_id=own then perform public.cw_news_add(p_career,'morale:'||p.player_id||':'||to_char(d,'IYYY-IW'),'squad',public.mgr_player_name(p.player_id)||' cobra espaço no time',
   'O papel prometido, os minutos recentes e os pagamentos estão afetando a satisfação. Reveja as oportunidades ou o papel no contrato.',90,own,p.player_id);
  elsif new_morale<30 and p.morale>=30 and p.club_id=own then perform public.cw_news_add(p_career,'morale-out:'||p.player_id||':'||to_char(d,'IYYY-IW'),'squad',public.mgr_player_name(p.player_id)||' pede para sair',
   'Muito insatisfeito, o atleta quer ser negociado e rende menos em campo. Dê minutos, ajuste o papel ou negocie a saída.',95,own,p.player_id);
  elsif new_morale>=45 and p.morale<45 and p.club_id=own then perform public.cw_news_add(p_career,'morale-up:'||p.player_id||':'||to_char(d,'IYYY-IW'),'squad',public.mgr_player_name(p.player_id)||' volta a ficar satisfeito',
   'Com mais oportunidades, o atleta voltou a se dedicar e esquece a ideia de sair.',60,own,p.player_id);
  end if;
 end loop;
 -- Alvos realistas (evolução 40): pilares (3 melhores de cada clube) não são alvo, e atletas com menos de 32 anos
 -- não são procurados por clubes de divisão inferior à deles. Calculado uma vez por dia.
 create temp table if not exists _cw_pillars(player_id text primary key) on commit drop;
 create temp table if not exists _cw_levels(club_id text primary key,lvl int not null) on commit drop;
 truncate _cw_pillars;truncate _cw_levels;
 insert into _cw_pillars select x.player_id from(select mp.player_id,row_number() over(partition by mp.club_id order by r.rating desc,mp.player_id) rk
  from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
  where mp.career_id=p_career and mp.club_id is not null) x where x.rk<=3 on conflict do nothing;
 insert into _cw_levels select c.id,public.cw_club_level(c.id) from public.sim_clubs c on conflict do nothing;
 -- One AI decision per club/date, with budgets and squad needs. User sales always await explicit approval.
 for c in select * from public.cw_clubs where career_id=p_career and club_id is distinct from own and (not (select public.cw_runtime_enabled(p_career)) or club_id in (select public.cw_domestic_clubs(p_career))) order by club_id loop
  insert into public.cw_ai_days values(p_career,c.club_id,d) on conflict do nothing;if not found then continue;end if;
  -- Janela fechada: só atletas livres (como na vida real). Elenco acima do limite + 6 não compra.
  if c.financial_risk>=75 or random()>public.cw_tick_probability((select ai_bid_chance from public.cw_rules))*(case when public.cw_window_open(public.cw_region(c.club_id),d) then 1 else .35 end)
     or public.cw_squad_count(p_career,c.club_id)>=public.cw_squad_limit()+6 then continue;end if;
  paid:=public.cw_available_budget(p_career,c.club_id);
  select coalesce(jsonb_object_agg(position,n),'{}') into depth from(select sp2.position,count(*) as n from public.mgr_players t join public.sim_players sp2 on sp2.id=t.player_id where t.career_id=p_career and t.club_id=c.club_id group by sp2.position)x;
  select a.style into style from public.mgr_ai_clubs a where a.career_id=p_career and a.club_id=c.club_id;
  select sp.id,mp.club_id,sp.position,coalesce(cp.potential,70) as potential into p from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id
   join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
   where mp.career_id=p_career and mp.club_id is distinct from c.club_id and sp.active and (not (select public.cw_runtime_enabled(p_career)) or mp.club_id is null or mp.club_id in (select public.cw_domestic_clubs(p_career)))
    and (mp.club_id is null or public.cw_window_open(public.cw_region(c.club_id),d))
    and cp.market_value<paid*.65
    and not exists(select 1 from public.cw_negotiations x where x.career_id=p_career and x.player_id=sp.id and x.buyer_club=c.club_id and x.status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract'))
    and pr.rating>=c.prestige-12
    and (mp.club_id is null or not exists(select 1 from _cw_pillars pl where pl.player_id=sp.id))
    and (mp.club_id is null or cp.age_at_start+floor((d-(select started_on from public.cw_world where career_id=p_career))/365.25)>=32
     or (select lvl from _cw_levels where club_id=c.club_id)<=(select lvl from _cw_levels where club_id=mp.club_id))
   order by (pr.rating+case when c.strategy='youth' then cp.potential-pr.rating else 0 end)
    /greatest(1,coalesce((depth->>sp.position)::int,0))*random() +case when (style='wide' and sp.position in('PD','PE','LD','LE')) or(style='counter' and sp.position in('ATA','PD','PE')) or(style='possession' and sp.position in('MC','MEI','VOL')) then 5 else 0 end
    +case when public.cw_region(mp.club_id)<>public.cw_region(c.club_id) then 20*(select ai_foreign_preference from public.cw_rules) else 0 end desc limit 1;
  if p.id is null then continue;end if;
  select * into ct from public.cw_contracts where career_id=p_career and player_id=p.id and status='active';
  value:=public.cw_player_value(p_career,p.id);
  insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,signing_bonus,created_on,reply_on,expires_on,valuation,agreed_owner_contract)
   values(p_career,p.id,p.club_id,c.club_id,'ai',case when p.club_id=own then 'seller_review' else 'club_pending' end,case when p.club_id is null then 0 else round(value*(1.1+random()*.35)) end,
    public.cw_salary_demand(p_career,p.id,c.club_id),3,greatest(ceil(value*.02),case when p.club_id is null then public.cw_minimum_signing(p_career,p.id,c.club_id) else 0 end),d,d+2,public.cw_deadline(d),value,ct.id) returning id into id;
  begin perform public.cw_reserve_offer(id);exception when raise_exception then perform public.cw_neg_close(id,'failed_funds',sqlerrm);continue;end;
  perform public.cw_neg_history(id,'buyer','Proposta enviada pelo clube interessado.');
  if p.club_id=own then perform public.cw_news_add(p_career,'incoming:'||id,'transfer',public.mgr_club_name(c.club_id)||' faz proposta por '||public.mgr_player_name(p.id),'A venda depende da sua decisão. Abra Negociações para aceitar, recusar ou apresentar uma contraproposta.',95,own,p.id);end if;
 end loop;
 -- Contract continuity and rational renewals run before expiry in cw_finance_tick.
end $function$;

CREATE OR REPLACE FUNCTION public.cw_finance_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;club public.cw_clubs;coach public.mgr_coach;risk numeric;rescue bigint;ref text;ct public.cw_contracts;staff public.cw_coach_contracts;paid bigint;balance bigint;
begin
 perform public.cw_ai_contracts_tick(p_career);
 select * into w from public.cw_world where career_id=p_career;
 if extract(day from w.today)=1 then perform public.cw_settle_month(p_career,(date_trunc('month',w.today)-interval '1month')::date);end if;
 perform public.cw_repay_arrears(p_career);
 select * into coach from public.mgr_coach where career_id=p_career;
 for club in select * from public.cw_clubs where career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or club_id in (select public.cw_domestic_clubs(p_career)) or club_id=coach.club_id) order by club_id loop
  risk:=least(100,round(100.0*club.debt/greatest(club.monthly_revenue*6,1)+case when club.cash<public.cw_payroll(p_career,club.club_id) then 25 else 0 end,2));
  update public.cw_clubs set financial_risk=risk,distress_since=case when risk>=75 then coalesce(distress_since,w.today) else null end where career_id=p_career and club_id=club.club_id and (financial_risk is distinct from risk or (risk>=75 and distress_since is null) or (risk<75 and distress_since is not null));
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
 for ct in select * from public.cw_contracts where career_id=p_career and status='active' and expires_on<w.today
  and(not public.cw_runtime_enabled(p_career) or club_id=coach.club_id or club_id in(select public.cw_domestic_clubs(p_career))
   or exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=cw_contracts.player_id and n.status='precontract')) for update loop
  update public.cw_contracts set status='expired',ended_on=expires_on where id=ct.id;
  update public.mgr_players set club_id=null where career_id=p_career and player_id=ct.player_id and club_id=ct.club_id;
  perform public.cw_prune_lineups(p_career,ct.player_id);
  perform public.cw_news_add(p_career,'expiry:'||ct.id,'contract',public.mgr_player_name(ct.player_id)||' encerra seu contrato',
   'O atleta está livre após o encerramento do vínculo com '||public.mgr_club_name(ct.club_id)||'.',case when ct.club_id=coach.club_id then 85 else 30 end,ct.club_id,ct.player_id);
 end loop;
end $function$;

CREATE OR REPLACE FUNCTION public.cw_initialize_finances(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;r record;fresh boolean;
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
 from public.sim_clubs c where exists(select 1 from public.mgr_players mp where mp.career_id=p_career and mp.club_id=c.id) on conflict do nothing;
 insert into public.cw_players(career_id,player_id,age_at_start,age_estimated,potential)
 select p_career,p.id,coalesce(p.age,case when p.is_youth then 19 else 26 end),p.age is null,
 least(99,round(r.rating)+case when coalesce(p.age,case when p.is_youth then 19 else 26 end)<23 then 12 else 3 end)
 from public.mgr_players mp join public.sim_players p on p.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where mp.career_id=p_career on conflict do nothing;
 update public.cw_players set market_value=public.cw_player_value(p_career,player_id) where career_id=p_career and market_value=0;
 fresh:=not exists(select 1 from public.cw_contracts where career_id=p_career);
 insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,role)
 select p_career,mp.player_id,mp.club_id,w.today,(w.today+make_interval(years=>1+(abs(hashtext(mp.player_id)::bigint)%4)::int))::date,
 greatest(public.cw_salary_floor(mp.player_id),round(public.cw_player_value(p_career,mp.player_id)*.0065)),case when p.is_youth then 'prospect' when r.rating>=82 then 'key' when r.rating>=74 then 'starter' else 'rotation' end
 from public.mgr_players mp join public.sim_players p on p.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where mp.career_id=p_career and mp.club_id is not null and (fresh or not exists(select 1 from public.cw_contracts ct where ct.career_id=p_career and ct.player_id=mp.player_id));
 -- Papel prometido = papel do contrato ativo. Atualiza atleta a atleta pela chave primária: numa carreira
 -- recém-criada as estatísticas das tabelas não existem e um join cruzava todos os atletas com todos os contratos.
 for r in select ct.player_id,ct.role from public.cw_contracts ct where ct.career_id=p_career and ct.status='active' and not exists(select 1 from public.cw_runtime where career_id=p_career) loop
  update public.cw_players set promised_role=r.role where career_id=p_career and player_id=r.player_id and promised_role is distinct from r.role;
 end loop;
 insert into public.cw_finance(career_id,club_id,on_date,kind,amount,cash_after,reference,description)
 select p_career,c.club_id,w.today,'opening',c.cash,c.cash,'opening','Orçamento inicial estimado do clube' from public.cw_clubs c where c.career_id=p_career on conflict do nothing;
 insert into public.cw_coach_contracts(career_id,spell_id,club_id,starts_on,expires_on,monthly_salary)
 select p_career,c.spell_id,c.club_id,w.today,(w.today+interval '2years')::date,p.monthly_salary from public.mgr_coach c join public.cw_coach p on p.career_id=c.career_id
 where c.career_id=p_career and c.status='employed' and c.spell_id is not null on conflict do nothing;
end $function$;

CREATE OR REPLACE FUNCTION public.cw_v32_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare d date;own text;p record;buyer text;value bigint;nid uuid;ct public.cw_contracts;club public.cw_clubs;spell_start date;lim int:=public.cw_squad_limit();
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 -- 1) venda dos listados
 if own is not null and public.cw_window_open(public.cw_region(own),d) then
  for p in select cp.player_id,cp.transfer_listed,ct.id as contract_id,ct.monthly_salary from public.cw_players cp join public.mgr_players mp using(career_id,player_id)
    join public.cw_contracts ct on ct.career_id=cp.career_id and ct.player_id=cp.player_id and ct.status='active'
    where cp.career_id=p_career and mp.club_id=own and (cp.transfer_listed or cp.transfer_requested)
     and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=cp.player_id and n.status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract'))
     and random()<public.cw_tick_probability(case when cp.transfer_listed then .12 else .05 end) loop
   value:=public.cw_player_value(p_career,p.player_id);
   -- amostra de clubes com caixa (o orçamento livre completo só é calculado para a amostra)
   select c.club_id into buyer from (select z.* from public.cw_clubs z where z.career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or z.club_id in (select public.cw_domestic_clubs(p_career))) and z.club_id<>own and z.financial_risk<75 and z.cash-z.debt>value*1.3
     order by random() limit 30) c
    where public.cw_available_budget(p_career,c.club_id)>value*1.1 and public.cw_squad_count(p_career,c.club_id)<lim+6
    order by (public.cw_region(c.club_id)=public.cw_region(own)) desc,random() limit 1;
   if buyer is null then continue;end if;
   insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,signing_bonus,created_on,reply_on,expires_on,valuation,agreed_owner_contract)
    values(p_career,p.player_id,own,buyer,'ai','seller_review',round(value*(case when p.transfer_listed then .85 else .95 end+random()*.25)),
     greatest(40,ceil(p.monthly_salary*1.1)),3,ceil(value*.02),d,d+2,public.cw_deadline(d),value,p.contract_id) returning id into nid;
   begin perform public.cw_reserve_offer(nid);exception when raise_exception then perform public.cw_neg_close(nid,'failed_funds',sqlerrm);continue;end;
   perform public.cw_neg_history(nid,'buyer','Proposta por atleta disponível para venda.');
   perform public.cw_news_add(p_career,'incoming:'||nid,'transfer',public.mgr_club_name(buyer)||' faz proposta por '||public.mgr_player_name(p.player_id),
    'A venda depende da sua decisão. Abra Negociações para aceitar, recusar ou apresentar uma contraproposta.',95,own,p.player_id);
  end loop;
 end if;
 -- 2) pré-contratos (dias 1 e 15): o atleta sem renovação assina com outro clube e sai de graça no fim do vínculo
 if extract(day from d) in(1,15) then
  for ct in select x.* from public.cw_contracts x where x.career_id=p_career and x.status='active' and (not (select public.cw_runtime_enabled(p_career)) or x.club_id=own or x.club_id in (select public.cw_domestic_clubs(p_career))) and x.expires_on between d and d+180
   and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=x.player_id and n.status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract'))
   and random()<case when x.club_id=own then .35 else .12 end
   order by (x.club_id=own) desc,random() limit 25 loop
   value:=public.cw_player_value(p_career,ct.player_id);
   select c.club_id into buyer from (select z.* from public.cw_clubs z where z.career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or z.club_id in (select public.cw_domestic_clubs(p_career))) and z.club_id is distinct from ct.club_id and z.club_id is distinct from own
     and z.financial_risk<75 and z.cash-z.debt>ct.monthly_salary*8 order by random() limit 30) c
    order by abs(c.prestige-coalesce((select prestige from public.cw_clubs z where z.career_id=p_career and z.club_id=ct.club_id),c.prestige)) limit 1;
   if buyer is null or public.cw_squad_count(p_career,buyer)>=lim+6
    or public.cw_project_reason(p_career,ct.player_id,buyer) is not null then continue;end if;
   -- Atleta satisfeito tende a esperar a renovação do clube atual.
   if (select morale from public.cw_players where career_id=p_career and player_id=ct.player_id)>=70 and random()<.6 then continue;end if;
   insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,signing_bonus,created_on,reply_on,expires_on,register_on,valuation,agreed_owner_contract,response)
    values(p_career,ct.player_id,ct.club_id,buyer,'ai','precontract',0,public.cw_salary_demand(p_career,ct.player_id,buyer),2+floor(random()*3)::int,0,d,d,greatest(public.cw_deadline(d),ct.expires_on+1),ct.expires_on+1,value,ct.id,
     'Pré-contrato assinado: o atleta chega sem custo ao fim do vínculo atual.') returning id into nid;
   perform public.cw_neg_history(nid,'player','Pré-contrato assinado com o novo clube.');
   perform public.cw_news_add(p_career,'precontract:'||nid,'transfer',public.mgr_player_name(ct.player_id)||' assina pré-contrato com '||public.mgr_club_name(buyer),
    'Sem renovação com '||coalesce(public.mgr_club_name(ct.club_id),'o clube')||', o atleta sai de graça em '||to_char(ct.expires_on+1,'DD/MM/YYYY')||'.',case when ct.club_id=own then 95 else 35 end,ct.club_id,ct.player_id);
  end loop;
  -- aviso mensal dos vínculos do seu elenco que terminam em até seis meses
  if extract(day from d)=1 and own is not null then
   for ct in select x.* from public.cw_contracts x where x.career_id=p_career and x.club_id=own and x.status='active' and x.expires_on between d and d+180
    and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=x.player_id and n.status in('agreed','precontract')) loop
    perform public.cw_news_add(p_career,'expiring:'||ct.id||':'||to_char(d,'YYYY-MM'),'contract','Contrato de '||public.mgr_player_name(ct.player_id)||' termina em '||to_char(ct.expires_on,'DD/MM/YYYY'),
     'Sem renovação, o atleta pode assinar pré-contrato com outro clube e sair de graça. Negocie em Time ou em Mundo → Contratos.',80,own,ct.player_id);
   end loop;
  end if;
 end if;
 -- 3) falência iminente: risco ≥ 90 por 21 dias (com o treinador há pelo menos 45 dias no cargo)
 if own is not null then
  select * into club from public.cw_clubs where career_id=p_career and club_id=own;
  select min(starts_on) into spell_start from public.cw_coach_contracts where career_id=p_career and club_id=own and ended_on is null;
  if club.financial_risk>=90 and club.distress_since is not null then
   if d-club.distress_since>=21 and d-coalesce(spell_start,d-999)>=45 then
    perform public.mgr_fire(p_career,'irresponsabilidade financeira: o clube está à beira da falência');
   else
    perform public.cw_news_add(p_career,'bankrupt-warning:'||own||':'||to_char(d,'IYYY-IW'),'board','Último aviso: clube à beira da falência',
     'O risco financeiro chegou a '||round(club.financial_risk)||'%. Sem vender atletas, cortar a folha ou investir recursos, você será demitido por irresponsabilidade financeira.',100,own);
   end if;
  end if;
 end if;
end $function$;

CREATE OR REPLACE FUNCTION public.cw_reserve_offer(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare n public.cw_negotiations;needed bigint;available bigint;
begin
 select * into n from public.cw_negotiations where id=p_id;
 needed:=n.fee+n.signing_bonus+n.performance_bonus;
 if n.monthly_salary>0 and not exists(select 1 from public.cw_market_legacy_agreements where negotiation_id=n.id) then
  needed:=needed+6*greatest(0,public.cw_contract_cost(n.player_id,n.monthly_salary,n.appearance_bonus,n.goal_bonus,n.role)
   -coalesce((select public.cw_contract_cost(player_id,monthly_salary,appearance_bonus,goal_bonus,role) from public.cw_contracts where career_id=n.career_id and player_id=n.player_id and club_id=n.buyer_club and status='active'),0));
 end if;
 select public.cw_available_budget(n.career_id,n.buyer_club)+coalesce((select amount from public.cw_commitments where career_id=n.career_id and reference=n.id||':offer'),0) into available;
 if needed>available then raise exception 'Orçamento livre insuficiente para taxa, luvas e bônus';end if;
 insert into public.cw_commitments(career_id,club_id,negotiation_id,kind,amount,due_on,reference)
 values(n.career_id,n.buyer_club,n.id,'offer',needed,n.expires_on,n.id||':offer')
 on conflict(career_id,club_id,reference) do update set amount=excluded.amount,status='reserved',due_on=excluded.due_on;
end $function$;

CREATE OR REPLACE FUNCTION public.career_player_offer(p_id uuid, p_salary bigint, p_years integer, p_signing bigint, p_role text, p_appearance bigint, p_goal bigint, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare car public.careers;n public.cw_negotiations;own text;prev jsonb;d date;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'player_offer');if prev is not null then return prev;end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';select today into d from public.cw_world where career_id=car.id;
 select * into n from public.cw_negotiations where id=p_id and career_id=car.id and buyer_club=own for update;
 if not found or n.status<>'player_counter' or n.expires_on<d then raise exception 'Etapa de contrato indisponível';end if;
 if p_salary is null or p_salary not between 1 and 10000000 or p_years is null or (p_years<1 or p_years>(select max_contract_years from public.cw_rules)) or p_signing is null or p_signing not between 0 and 10000000 or p_role not in('key','starter','rotation','prospect') or p_appearance is null or p_appearance not between 0 and 1000000 or p_goal is null or p_goal not between 0 and 1000000 then raise exception 'Contrato inválido';end if;
 if n.initiator<>'renewal' and public.cw_project_reason(car.id,n.player_id,own) is not null then raise exception '%',public.cw_project_reason(car.id,n.player_id,own);end if;
 if p_salary<public.cw_salary_demand(car.id,n.player_id,own) then raise exception 'Salário mensal insuficiente. O atleta exige pelo menos % moedas.',public.cw_salary_demand(car.id,n.player_id,own);end if;
 if n.seller_club is null and n.initiator<>'renewal' and p_signing<public.cw_minimum_signing(car.id,n.player_id,own) then raise exception 'Atleta livre exige ao menos % moedas de luvas.',public.cw_minimum_signing(car.id,n.player_id,own);end if;
 update public.cw_negotiations set monthly_salary=p_salary,contract_years=p_years,signing_bonus=p_signing,role=p_role,appearance_bonus=p_appearance,goal_bonus=p_goal,status='player_pending',reply_on=d+2,expires_on=public.cw_deadline(d) where id=n.id;
 perform public.cw_reserve_offer(n.id);perform public.cw_neg_history(n.id,'user','Condições contratuais apresentadas ao atleta.');
 return public.econ_request_save(car.id,p_request,'player_offer',jsonb_build_object('ok',true));
end $function$;

CREATE OR REPLACE FUNCTION public.career_player_search(p_query text DEFAULT ''::text, p_position text DEFAULT ''::text, p_region text DEFAULT ''::text, p_club text DEFAULT ''::text, p_max_value bigint DEFAULT NULL::bigint, p_page integer DEFAULT 0, p_country text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare car uuid:=public.cw_current_career();own text;w public.cw_world;
begin
 if car is null then raise exception 'Carreira ativa não encontrada';end if;
 select * into w from public.cw_world where career_id=car;
 select club_id into own from public.mgr_coach where career_id=car;
 return(select coalesce(jsonb_agg(to_jsonb(x) order by x.overall desc,x.id),'[]') from(
 select b.*,public.cw_player_value(car,b.id) value,ct.monthly_salary,ct.expires_on,ct.role,ct.arrears,
 public.cw_salary_demand(car,b.id,own) salary_demand,public.cw_minimum_signing(car,b.id,own) minimum_signing_bonus,
 public.cw_project_reason(car,b.id,own) project_reason,
 coalesce((select sum(st.minutes) from public.mgr_player_stats st join public.career_seasons ss on ss.id=st.season_id where ss.career_id=car and ss.status='active' and st.player_id=b.id),0) minutes
 from(
 select sp.id,sp.full_name name,sp.short_name,sp.position,e.club_id,sp.nationality,round(pr.rating) overall,
 round(coalesce(mp.condition,100)) condition,
 coalesce(cp.age_at_start,sp.age,case when sp.is_youth then 19 else 26 end)+coalesce(floor((w.today-w.started_on)/365.25)::int,0) age,
 coalesce(cp.age_estimated,sp.age is null) age_estimated,coalesce(cp.potential,least(99,round(pr.rating)+case when coalesce(sp.age,26)<23 then 12 else 3 end)) potential,
 coalesce(cp.morale,65) morale,coalesce(cp.promised_role,'rotation') promised_role,coalesce(cp.transfer_requested,false) transfer_requested,
 coalesce(cp.shirt_number,sp.shirt_number) number
 from public.sim_players sp join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
 left join public.mgr_players mp on mp.career_id=car and mp.player_id=sp.id
 left join public.cw_players cp on cp.career_id=car and cp.player_id=sp.id
 cross join lateral(select public.cw_effective_player_club(car,sp.id) club_id)e
 left join public.sim_clubs sc on sc.id=e.club_id
 where sp.active and (coalesce(p_query,'')='' or sp.full_name ilike '%'||left(p_query,60)||'%')
 and (coalesce(p_country,'')='' or sc.country=upper(p_country))
 and (coalesce(p_position,'')='' or sp.position=p_position)
 and (coalesce(p_region,'')='' or public.cw_region(e.club_id)=p_region or(p_region='free' and e.club_id is null))
 and (coalesce(p_club,'')='' or e.club_id=case when p_club='mine' then own else p_club end)
 and (p_max_value is null or public.cw_player_value(car,sp.id)<=p_max_value)
 order by pr.rating desc,sp.id limit 30 offset least(greatest(coalesce(p_page,0),0),200)*30)b
 left join public.cw_contracts ct on ct.career_id=car and ct.player_id=b.id and ct.status='active')x);
end $function$;

CREATE OR REPLACE FUNCTION public.career_negotiations()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare car public.careers;own text;
begin
 car:=public.mgr_lock();select club_id into own from public.mgr_coach where career_id=car.id;
 return(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select n.id,n.player_id,public.mgr_player_name(n.player_id) as player_name,n.seller_club,n.buyer_club,n.status,n.initiator,n.fee,n.installments,n.performance_bonus,n.monthly_salary,n.contract_years,n.signing_bonus,n.role,n.appearance_bonus,n.goal_bonus,n.created_on,n.reply_on,n.expires_on,n.register_on,n.round_no,n.response,n.valuation,
  public.cw_salary_demand(car.id,n.player_id,n.buyer_club) salary_demand,public.cw_minimum_signing(car.id,n.player_id,n.buyer_club) minimum_signing_bonus,
  public.cw_project_reason(car.id,n.player_id,n.buyer_club) project_reason,
  (select coalesce(jsonb_agg(jsonb_build_object('date',h.on_date,'actor',h.actor,'state',h.state,'explanation',h.explanation,'terms',h.terms) order by h.id),'[]') from public.cw_offer_history h where h.negotiation_id=n.id and h.career_id=car.id) as history
 from public.cw_negotiations n where n.career_id=car.id and own in(n.buyer_club,n.seller_club) order by n.created_on desc,n.id limit 60)x);
end $function$;

create or replace function public.career_transfer_bid(p_player text,p_fee bigint,p_installments int,p_bonus bigint,p_precontract boolean,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;own text;d date;b record;receipt jsonb;owner text;
begin
 car:=public.mgr_lock();receipt:=public.econ_request_get(car.id,p_request,'transfer_bid');if receipt is not null then return receipt;end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 select today into d from public.cw_world where career_id=car.id;
 if own is null then raise exception 'Assuma um clube para negociar';end if;
 if not coalesce(p_precontract,false) and public.cw_window_open(public.cw_region(own),d)
  and public.cw_registered_in_window(car.id,own,d)>=6 then
  select * into b from public.cw_transfer_window(public.cw_region(own),d);
  raise exception 'Limite de 6 contratações registradas nesta janela atingido. Próxima janela: %.',to_char(public.cw_next_window(public.cw_region(own),b.ends_on+1),'DD/MM/YYYY');
 end if;
 -- A search never mutates the save. Materialize only the target club when an actual bid is made.
 owner:=public.cw_effective_player_club(car.id,p_player);
 if not exists(select 1 from public.mgr_players where career_id=car.id and player_id=p_player) and owner is not null then perform public.cw_materialize_club(car.id,owner);end if;
 perform public.cw_recover_ai_free_players(car.id,p_player);
 return public.career_transfer_bid_before_v39(p_player,p_fee,p_installments,p_bonus,p_precontract,p_request);
end $$;

create or replace function public.cw_register_transfer(p_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n public.cw_negotiations;own text;d date;region text;b record;next_date date;legacy boolean;result boolean;reason text;
begin
 select career_id into n.career_id from public.cw_negotiations where id=p_id;
 if n.career_id is null then return false;end if;
 perform 1 from public.careers where id=n.career_id for update;
 select * into n from public.cw_negotiations where id=p_id for update;
 if n.status='completed' then return true;end if;
 if n.status not in('agreed','precontract') then return false;end if;
 select today into d from public.cw_world where career_id=n.career_id;
 if n.register_on>d then return false;end if;
 select club_id into own from public.mgr_coach where career_id=n.career_id and status='employed';
 region:=public.cw_region(n.buyer_club);
 legacy:=exists(select 1 from public.cw_market_legacy_agreements where negotiation_id=n.id);
 if not legacy then
  reason:=case when n.initiator<>'renewal' then public.cw_project_reason(n.career_id,n.player_id,n.buyer_club) end;
  if reason is not null then perform public.cw_neg_close(n.id,'rejected',reason);return false;end if;
  if n.monthly_salary<public.cw_salary_demand(n.career_id,n.player_id,n.buyer_club)
   or(n.seller_club is null and n.initiator<>'renewal' and n.signing_bonus<public.cw_minimum_signing(n.career_id,n.player_id,n.buyer_club)) then
   perform public.cw_neg_close(n.id,'rejected','Os termos não atendem ao salário e às luvas exigidos pelo atleta.');return false;
  end if;
  if not public.cw_can_afford_contract(n.id) then
   perform public.cw_neg_close(n.id,'failed_funds','O clube não consegue sustentar taxa, luvas, dívidas e seis meses do acréscimo da folha.');return false;
  end if;
 end if;
 if n.initiator<>'renewal' then
  if not public.cw_window_open(region,d) and(n.status='agreed' or not legacy) then
   if n.buyer_club is not distinct from own or n.seller_club is not null or(select count(*) from public.mgr_players where career_id=n.career_id and club_id=n.buyer_club)>=18 then
    next_date:=public.cw_next_window(region,d);
   end if;
  elsif not legacy and n.buyer_club=own and public.cw_registered_in_window(n.career_id,own,d)>=6 then
   select * into b from public.cw_transfer_window(region,d);
   next_date:=public.cw_next_window(region,b.ends_on+1);
  end if;
  if next_date is not null then
   update public.cw_negotiations set register_on=next_date,response='Acordo preservado. O registro aguarda a próxima janela disponível: '||to_char(next_date,'DD/MM/YYYY')||'.' where id=n.id and register_on is distinct from next_date;
   update public.cw_commitments set due_on=next_date where negotiation_id=n.id and kind='offer' and status='reserved';
   return false;
  end if;
 end if;
 result:=public.cw_register_transfer_before_v39(p_id);
 if result and n.initiator<>'renewal' and n.buyer_club=own then
  insert into public.cw_transfer_registrations(career_id,negotiation_id,player_id,buyer_club,registered_on)
   values(n.career_id,n.id,n.player_id,n.buyer_club,d) on conflict do nothing;
 end if;
 return result;
end $$;

revoke all on function public.cw_transfer_window(text,date),public.cw_registered_in_window(uuid,text,date),
 public.cw_salary_floor(text),public.cw_salary_demand(uuid,text,text),public.cw_project_reason(uuid,text,text),
 public.cw_minimum_signing(uuid,text,text),public.cw_can_afford_contract(uuid),public.cw_ai_recovery_club(uuid,text),
 public.cw_effective_player_club(uuid,text),public.cw_recover_ai_free_players(uuid,text),public.cw_ai_contracts_tick(uuid)
 from public,anon,authenticated;
revoke all on function public.career_transfer_bid(text,bigint,integer,bigint,boolean,uuid),
 public.career_player_offer(uuid,bigint,integer,bigint,text,bigint,bigint,uuid),public.career_player_search(text,text,text,text,bigint,integer,text),public.career_negotiations() from public,anon;
grant execute on function public.career_transfer_bid(text,bigint,integer,bigint,boolean,uuid),
 public.career_player_offer(uuid,bigint,integer,bigint,text,bigint,bigint,uuid),public.career_player_search(text,text,text,text,bigint,integer,text),public.career_negotiations() to authenticated;
notify pgrst,'reload schema';
commit;
